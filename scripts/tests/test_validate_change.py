import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import call, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "skills"))

from sidey_tools import WorkflowError  # noqa: E402
from sidey_tools.process import decode_output, run  # noqa: E402
from sidey_tools.repository import (  # noqa: E402
    changed_paths,
    platform_for,
    validate_paths,
)
from validate_change import (  # noqa: E402
    commit_messages,
    resolve_change,
    validate_pr_paths,
    verify_commit_contract,
    verify_gate,
    verify_pr_contract,
)


class GateTests(unittest.TestCase):
    def test_process_output_normalizes_line_endings(self):
        self.assertEqual(decode_output(b"a\r\nb\rc\n"), "a\nb\nc\n")

    def test_process_failure_uses_workflow_error(self):
        completed = subprocess.CompletedProcess(
            args=("git", "status"),
            returncode=2,
            stdout=b"",
            stderr=b"failure\r\n",
        )
        with patch(
            "sidey_tools.process.subprocess.run",
            return_value=completed,
        ):
            with self.assertRaisesRegex(
                WorkflowError,
                "git status failed: failure",
            ):
                run(Path("."), "git", "status")

    def test_validate_change_uses_repository_git_helper(self):
        self.assertEqual(
            commit_messages.__globals__["git"].__module__,
            "sidey_tools.repository",
        )

    def test_changed_paths_uses_merge_base_and_nul_delimited_diff(self):
        with patch(
            "sidey_tools.repository.git",
            side_effect=["merge-base", "b.py\x00a.py\x00b.py\x00"],
        ) as git:
            self.assertEqual(
                changed_paths(Path("."), "base", "head"),
                ["a.py", "b.py"],
            )
        self.assertEqual(
            git.call_args_list,
            [
                call(
                    Path("."),
                    "merge-base",
                    "base",
                    "head",
                ),
                call(
                    Path("."),
                    "diff",
                    "--no-renames",
                    "--name-only",
                    "-z",
                    "merge-base",
                    "head",
                ),
            ],
        )

    def test_path_validation_preserves_platform_policy(self):
        self.assertEqual(
            validate_paths("windows/task", ["windows/SIDEY/App.xaml.cs"]),
            "windows",
        )
        with self.assertRaisesRegex(WorkflowError, "platform boundary"):
            validate_paths(
                "windows/task",
                [".github/workflows/macos-build-and-tests.yml"],
            )

    def test_renamed_platform_workflows_keep_their_ownership(self):
        expected_platforms = {
            ".github/workflows/macos-build-and-tests.yml": "macos",
            ".github/workflows/validate-macos.yml": "macos",
            ".github/workflows/windows-build-and-tests.yml": "windows",
            ".github/workflows/validate-windows.yml": "windows",
            ".github/workflows/windows-release.yml": "windows",
            ".github/workflows/publish-windows-release.yml": "windows",
        }
        for path, expected in expected_platforms.items():
            with self.subTest(path=path):
                self.assertEqual(platform_for(path), expected)

    def test_commit_messages_preserve_bodies_and_remove_record_newlines(self):
        output = (
            'fix: 첫 번째 변경\n\n변경 이유를 설명해요.\x00\n'
            "Merge branch 'main' into shared/task\x00\n"
        )
        with patch("validate_change.git", return_value=output):
            self.assertEqual(
                commit_messages(Path("."), "base", "head"),
                [
                    "fix: 첫 번째 변경\n\n변경 이유를 설명해요.",
                    "Merge branch 'main' into shared/task",
                ],
            )

    def test_new_commit_range_and_pr_title_follow_policy(self):
        verify_commit_contract(
            [
                "chore(commit): 기여자 구조 정리",
                "Merge branch 'main' into shared/contributor-architecture",
            ],
            "chore(commit): AI 기여자 구조 최종화",
        )

    def test_invalid_new_commit_or_pr_title_fails_gate(self):
        with self.assertRaisesRegex(WorkflowError, "commit subject"):
            verify_commit_contract(["Contributor architecture cleanup"])
        with self.assertRaisesRegex(WorkflowError, "PR title"):
            verify_commit_contract(
                ["chore(commit): 기여자 구조 정리"],
                "Contributor architecture cleanup",
            )

    def test_long_new_commit_body_fails_gate(self):
        message = f"docs: 규칙 추가\n\n{'가' * 73}"
        with self.assertRaisesRegex(WorkflowError, "commit message"):
            verify_commit_contract([message])

    def test_manual_pr_body_must_use_repository_template(self):
        root = Path(__file__).parents[2]
        body = (
            root / ".github/PULL_REQUEST_TEMPLATE/general.md"
        ).read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            verify_pr_contract(root, body, ["docs/guide.md"]),
            "general",
        )
        with self.assertRaisesRegex(WorkflowError, "template validation"):
            verify_pr_contract(root, "## 변경 내용\n", ["docs/guide.md"])

    def test_maintainer_asset_pr_uses_general_template(self):
        root = Path(__file__).parents[2]
        general_body = (
            root / ".github/PULL_REQUEST_TEMPLATE/general.md"
        ).read_text(encoding="utf-8")
        paths = ["assets/v1/characters/capybara/idle.png"]
        self.assertEqual(
            verify_pr_contract(root, general_body, paths),
            "general",
        )
        with self.assertRaisesRegex(WorkflowError, "retired asset template"):
            verify_pr_contract(
                root,
                "<!-- SIDEY_CHARACTER_ASSET_PR_TEMPLATE: keep -->\n",
                paths,
            )

    def test_shared_branch_cannot_cross_platform_boundary(self):
        with self.assertRaisesRegex(WorkflowError, "platform boundary"):
            validate_pr_paths(
                "shared/script-relocation",
                ["scripts/macos/archive_app_store.sh"],
            )

    def test_required_job_cannot_be_skipped_missing_cancelled_or_failed(self):
        for status in ("skipped", "failure", "cancelled", None):
            needs = {
                "scope": {"result": "success"},
                "shared": {"result": "success"},
            }
            if status:
                needs["macos"] = {"result": status}
            with self.assertRaises(WorkflowError):
                verify_gate(["shared", "macos"], needs)

    def test_unaffected_platform_may_skip(self):
        verify_gate(
            ["shared"],
            {
                "scope": {"result": "success"},
                "shared": {"result": "success"},
                "windows": {"result": "skipped"},
            },
        )

    def test_edited_pr_revalidates_policy_without_scheduling_heavy_jobs(self):
        event = {
            "action": "edited",
            "pull_request": {
                "base": {"sha": "base"},
                "head": {"sha": "head", "ref": "shared/task"},
                "title": "docs: update policy",
                "body": "body",
                "labels": [],
            },
        }
        with (
            patch(
                "validate_change.changed_paths",
                return_value=["docs/guide.md"],
            ),
            patch(
                "validate_change.commit_messages",
                return_value=["docs: update policy"],
            ),
            patch("validate_change.verify_commit_contract") as commits,
            patch("validate_change.verify_pr_contract") as body,
            patch("validate_change.validate_pr_paths") as paths,
            patch("validate_change.required_scopes") as scopes,
        ):
            result = resolve_change(Path("."), event)
        self.assertEqual(result["scopes"], [])
        commits.assert_called_once_with(
            ["docs: update policy"],
            "docs: update policy",
        )
        body.assert_called_once_with(
            Path("."),
            "body",
            ["docs/guide.md"],
        )
        paths.assert_called_once_with("shared/task", ["docs/guide.md"])
        scopes.assert_not_called()

    def test_normal_pr_emits_resolved_scopes(self):
        event = {
            "action": "synchronize",
            "pull_request": {
                "base": {"sha": "base"},
                "head": {"sha": "head", "ref": "windows/task"},
                "title": "fix(Windows): update app",
                "body": "body",
                "labels": [],
            },
        }
        with (
            patch(
                "validate_change.changed_paths",
                return_value=["windows/SIDEY/App.xaml.cs"],
            ),
            patch("validate_change.commit_messages", return_value=[]),
            patch("validate_change.verify_commit_contract"),
            patch("validate_change.verify_pr_contract"),
            patch("validate_change.validate_pr_paths"),
            patch(
                "validate_change.required_scopes",
                return_value=["shared", "windows"],
            ) as scopes,
        ):
            result = resolve_change(Path("."), event)
        self.assertEqual(result["scopes"], ["shared", "windows"])
        scopes.assert_called_once_with(["windows/SIDEY/App.xaml.cs"])

    def test_empty_edited_scope_requires_only_scope_job(self):
        verify_gate(
            [],
            {
                "scope": {"result": "success"},
                "shared": {"result": "skipped"},
                "windows": {"result": "skipped"},
            },
        )

    def test_scope_failure_never_passes_empty_requirements(self):
        with self.assertRaises(WorkflowError):
            verify_gate(
                [],
                {
                    "scope": {"result": "failure"},
                    "shared": {"result": "success"},
                },
            )
