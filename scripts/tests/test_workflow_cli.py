import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / "scripts" / "skills" / "workflow.py"
SKILL_SCRIPTS = WORKFLOW_PATH.parent
sys.path.insert(0, str(SKILL_SCRIPTS))


def load_workflow():
    spec = importlib.util.spec_from_file_location(
        "sidey_workflow_cli_tests",
        WORKFLOW_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the workflow script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


workflow = load_workflow()


class WorkflowCommandSurfaceTests(unittest.TestCase):
    def help_text(self, *arguments):
        result = subprocess.run(
            [sys.executable, str(WORKFLOW_PATH), *arguments],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_top_level_help_lists_every_supported_command(self):
        output = self.help_text("--help")

        self.assertIn(
            "{doctor,start,sync,check,publish,finish,open}",
            output,
        )
        self.assertIn("--repo REPO", output)

    def test_command_help_preserves_public_options(self):
        expected_options = {
            "start": (
                "--platform {shared,macos,windows}",
                "--worktree WORKTREE",
                "--app {SIDEYAppStore,SIDEY,sidey-reals,windows}",
            ),
            "check": (
                "--ci",
                "--base BASE",
                "--head HEAD",
                "--branch BRANCH",
            ),
            "publish": (
                "--title TITLE",
                "--body-file BODY_FILE",
                "--push-remote PUSH_REMOTE",
            ),
            "finish": ("--windows-run WINDOWS_RUN",),
            "open": (
                "--task TASK",
                "--preview PREVIEW",
                "--offline",
                "--scheme {SIDEYAppStore,SIDEY,sidey-reals}",
            ),
        }

        for command, options in expected_options.items():
            with self.subTest(command=command):
                output = self.help_text(command, "--help")
                for option in options:
                    self.assertIn(option, output)

    def test_ci_check_prints_indented_utf8_json(self):
        expected = {
            "paths": ["docs/architecture.md"],
            "scopes": ["shared"],
        }

        with (
            patch.object(workflow, "root_at", return_value=ROOT),
            patch.object(
                workflow,
                "changed_paths",
                return_value=expected["paths"],
            ),
            patch.object(workflow, "validate_paths"),
            patch.object(
                workflow,
                "required_scopes",
                return_value=expected["scopes"],
            ),
            patch("sys.stdout", new_callable=io.StringIO) as stdout,
        ):
            result = workflow.main(
                [
                    "--repo",
                    str(ROOT),
                    "check",
                    "--ci",
                    "--base",
                    "base-sha",
                    "--head",
                    "head-sha",
                    "--branch",
                    "shared/readability",
                ]
            )

        self.assertEqual(result, 0)
        self.assertEqual(json.loads(stdout.getvalue()), expected)
        self.assertTrue(stdout.getvalue().endswith("\n"))

    def test_script_reports_workflow_errors_on_stderr(self):
        result = subprocess.run(
            [
                sys.executable,
                str(WORKFLOW_PATH),
                "--repo",
                str(ROOT),
                "check",
                "--ci",
                "--branch",
                "shared/readability",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            result.stderr,
            "workflow: CI requires explicit --base and --branch\n",
        )

    def test_finish_uses_gh_cli_supported_pr_base_field(self):
        source = WORKFLOW_PATH.read_text(encoding="utf-8")

        self.assertIn("baseRefName", source)
        self.assertNotIn("baseRefOid", source)


if __name__ == "__main__":
    unittest.main()
