"""Tests for deterministic SIDEY release evidence collection."""

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).parents[1] / "collect_release_evidence.py"
SPEC = importlib.util.spec_from_file_location(
    "collect_release_evidence",
    SCRIPT,
)
COLLECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COLLECTOR)


class FakeRunner:
    """Return fixed Git and GitHub results for one two-commit range."""

    def __init__(self):
        self.baseline = "a" * 40
        self.pull_commit = "b" * 40
        self.direct_commit = "c" * 40
        self.multiple_pulls = False

    def __call__(self, command, _root):
        command = tuple(command)
        if command[:3] == ("git", "rev-parse", "--verify"):
            return (
                self.baseline
                if command[3].startswith("windows-v1.0.0")
                else self.direct_commit
            )
        if command[:3] == ("git", "merge-base", "--is-ancestor"):
            return ""
        if command[:4] == (
            "git",
            "rev-list",
            "--first-parent",
            "--reverse",
        ):
            return f"{self.pull_commit}\n{self.direct_commit}"
        if command[:3] == ("git", "show", "-s"):
            commit = command[-1]
            return (
                f"{commit}\0subject {commit[0]}\0Author\0author@example.test"
                "\0"
                "2026-09-16T00:00:00+09:00"
            )
        if command[:3] == ("git", "diff-tree", "--root"):
            return "windows/file.cs\0"
        if command[:3] == ("git", "diff", "--name-only"):
            return "windows/file.cs\0docs/shared.md\0"
        if command[:2] == ("gh", "api"):
            endpoint = command[-1]
            if endpoint.endswith(f"/{self.pull_commit}/pulls"):
                pulls = [
                    {
                        "number": 108,
                        "title": "fix(Windows): 안정성 개선",
                        "user": {"login": "patulus"},
                        "html_url": "https://example.test/108",
                        "merged_at": "2026-09-16T00:00:00Z",
                        "merge_commit_sha": self.pull_commit,
                    }
                ]
                if self.multiple_pulls:
                    pulls.append({**pulls[0], "number": 109})
                return COLLECTOR.json.dumps(pulls)
            if endpoint.endswith(f"/{self.direct_commit}/pulls"):
                return "[]"
            if endpoint.endswith(f"/commits/{self.direct_commit}"):
                return COLLECTOR.json.dumps(
                    {
                        "author": {"login": "aryu1217"},
                        "html_url": "https://example.test/commit",
                    }
                )
        raise AssertionError(f"Unexpected command: {command}")


class CollectReleaseEvidenceTests(unittest.TestCase):
    def test_collects_exact_pull_request_and_direct_commit(self):
        runner = FakeRunner()
        result = COLLECTOR.collect_evidence(
            Path("."),
            "windows-v1.0.0",
            runner.direct_commit,
            target_tag="windows-v1.0.1",
            runner=runner,
        )

        self.assertEqual(
            [record["reference"] for record in result["integrations"]],
            ["#108", runner.direct_commit[:7]],
        )
        self.assertEqual(result["integrations"][0]["author"], "patulus")
        self.assertEqual(result["integrations"][1]["author"], "aryu1217")
        self.assertEqual(result["target"]["reference"], "windows-v1.0.1")
        self.assertEqual(
            result["target"]["source_reference"],
            runner.direct_commit,
        )
        self.assertEqual(
            result["net_changed_paths"],
            ["docs/shared.md", "windows/file.cs"],
        )
        self.assertEqual(
            result["source_repository"],
            "sidey-app/SIDEY-source",
        )
        self.assertEqual(
            result["public_release_url"],
            "https://github.com/sidey-app/SIDEY/releases/tag/"
            "windows-v1.0.1",
        )

    def test_rejects_multiple_exact_pull_requests(self):
        runner = FakeRunner()
        runner.multiple_pulls = True

        with self.assertRaisesRegex(
            COLLECTOR.CollectionError,
            "multiple exact PRs",
        ):
            COLLECTOR.collect_evidence(
                Path("."),
                "windows-v1.0.0",
                "windows-v1.0.1",
                runner=runner,
            )

    def test_app_store_source_range_has_no_github_release_url(self):
        runner = FakeRunner()

        result = COLLECTOR.collect_evidence(
            Path("."),
            "windows-v1.0.0",
            runner.direct_commit,
            runner=runner,
        )

        self.assertIsNone(result["public_release_url"])


if __name__ == "__main__":
    unittest.main()
