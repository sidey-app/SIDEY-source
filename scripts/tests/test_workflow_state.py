import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / "scripts" / "skills" / "workflow.py"
SKILL_SCRIPTS = WORKFLOW_PATH.parent
sys.path.insert(0, str(SKILL_SCRIPTS))


def load_workflow():
    spec = importlib.util.spec_from_file_location(
        "sidey_workflow_state_tests",
        WORKFLOW_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the workflow script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


workflow = load_workflow()


class WorkflowStateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        subprocess.run(
            ["git", "init", "--quiet", str(self.root)],
            check=True,
        )

    def test_task_state_uses_git_common_dir_and_round_trips(self):
        task = {
            "worktree": str(self.root),
            "branch": "shared/readability",
            "platform": "shared",
            "app": "SIDEY",
            "base": "base-sha",
            "status": "started",
        }

        workflow.update_task(self.root, "readability", task)

        state_path = self.root / ".git" / "sidey-workflow" / "tasks.json"
        self.assertTrue(state_path.is_file())
        self.assertEqual(workflow.read_state(self.root), {"readability": task})
        self.assertEqual(
            json.loads(state_path.read_text(encoding="utf-8")),
            {"readability": task},
        )
        self.assertTrue(state_path.read_bytes().endswith(b"\n"))

    def test_start_records_the_initial_status_fields(self):
        state_directory = self.root / "state"
        state_directory.mkdir()
        destination = self.root / "readability-worktree"
        resolved_destination = destination.resolve()
        expected = {
            "worktree": str(resolved_destination),
            "branch": "shared/readability",
            "platform": "shared",
            "app": "SIDEY",
            "base": "remote-main",
            "status": "started",
        }

        with (
            patch.object(workflow, "root_at", return_value=self.root),
            patch.object(
                workflow,
                "fetch_main",
                return_value="remote-main",
            ),
            patch.object(workflow, "lock") as lock,
            patch.object(workflow, "git") as git,
            patch("sys.stdout", new_callable=io.StringIO) as stdout,
        ):
            lock.return_value.__enter__.return_value = state_directory
            result = workflow.main(
                [
                    "--repo",
                    str(self.root),
                    "start",
                    "readability",
                    "--platform",
                    "shared",
                    "--worktree",
                    str(destination),
                ]
            )

        self.assertEqual(result, 0)
        self.assertEqual(json.loads(stdout.getvalue()), expected)
        self.assertEqual(
            json.loads(
                (state_directory / "tasks.json").read_text(
                    encoding="utf-8"
                )
            ),
            {"readability": expected},
        )
        git.assert_called_once_with(
            self.root,
            "worktree",
            "add",
            "-b",
            "shared/readability",
            str(resolved_destination),
            "remote-main",
        )

    def test_update_preserves_other_tasks_and_status_fields(self):
        workflow.update_task(
            self.root,
            "first",
            {"status": "started", "base": "base-one"},
        )
        published = {
            "status": "published",
            "base": "base-two",
            "checked": {
                "head": "checked-head",
                "base": "base-two",
                "snapshot": "snapshot",
            },
            "published": {
                "head": "checked-head",
                "base": "base-two",
                "time": 1.0,
            },
            "pr": "42",
        }

        workflow.update_task(self.root, "second", published)

        self.assertEqual(
            workflow.read_state(self.root),
            {
                "first": {"status": "started", "base": "base-one"},
                "second": published,
            },
        )


class WorkflowExactHeadTests(unittest.TestCase):
    def test_exact_task_pr_accepts_one_same_repository_current_head(self):
        pull_requests = [
            {
                "number": 42,
                "headRefOid": "checked-head",
                "isCrossRepository": False,
            }
        ]

        with patch.object(workflow, "head", return_value="checked-head"):
            number = workflow.require_exact_task_pr(ROOT, pull_requests)

        self.assertEqual(number, "42")

    def test_exact_task_pr_rejects_missing_ambiguous_or_stale_heads(self):
        current = {
            "number": 42,
            "headRefOid": "checked-head",
            "isCrossRepository": False,
        }
        invalid = (
            [],
            [
                current,
                {
                    **current,
                    "number": 43,
                    "isCrossRepository": True,
                },
            ],
            [
                {
                    **current,
                    "headRefOid": "stale-head",
                    "isCrossRepository": True,
                }
            ],
        )

        with patch.object(workflow, "head", return_value="checked-head"):
            for pull_requests in invalid:
                with self.subTest(pull_requests=pull_requests):
                    with self.assertRaisesRegex(
                        workflow.WorkflowError,
                        "exact task head",
                    ):
                        workflow.require_exact_task_pr(
                            ROOT,
                            pull_requests,
                        )

    def test_recovery_requires_checked_head_snapshot_and_merge_intent(self):
        task = self.recoverable_task()
        invalid_tasks = (
            {**task, "checked": {**task["checked"], "head": "old-head"}},
            {
                **task,
                "checked": {
                    **task["checked"],
                    "snapshot": "old-snapshot",
                },
            },
            {**task, "merge_intent": {**task["merge_intent"], "head": "old"}},
            {**task, "merge_intent": {**task["merge_intent"], "base": "old"}},
        )

        with (
            patch.object(workflow, "head", return_value="checked-head"),
            patch.object(
                workflow,
                "snapshot",
                return_value="checked-snapshot",
            ),
            patch.object(workflow, "run") as run,
        ):
            for invalid in invalid_tasks:
                with self.subTest(task=invalid):
                    self.assertIsNone(
                        workflow.recover_merged_task(
                            ROOT,
                            invalid,
                            "remote-main",
                        )
                    )

        run.assert_not_called()

    def test_recovery_accepts_one_exact_merged_tree(self):
        task = self.recoverable_task()
        pull_request = {
            "number": 42,
            "headRefOid": "checked-head",
            "mergeCommit": {"oid": "merge-sha"},
            "isCrossRepository": False,
        }

        with (
            patch.object(workflow, "head", return_value="checked-head"),
            patch.object(
                workflow,
                "snapshot",
                return_value="checked-snapshot",
            ),
            patch.object(
                workflow,
                "run",
                return_value=json.dumps([pull_request]),
            ),
            patch.object(workflow, "is_ancestor", return_value=True),
            patch.object(workflow, "same_tree", return_value=True),
        ):
            recovered = workflow.recover_merged_task(
                ROOT,
                task,
                "remote-main",
            )

        self.assertEqual(
            recovered,
            {
                **task,
                "status": "integrated",
                "pr": "42",
                "merge": "merge-sha",
            },
        )

    @staticmethod
    def recoverable_task():
        return {
            "status": "published",
            "checked": {
                "head": "checked-head",
                "snapshot": "checked-snapshot",
                "base": "checked-base",
            },
            "merge_intent": {
                "head": "checked-head",
                "base": "checked-base",
            },
        }


if __name__ == "__main__":
    unittest.main()
