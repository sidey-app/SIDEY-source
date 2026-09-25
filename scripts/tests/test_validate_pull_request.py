import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "skills" / "create-pr"))

from validate_pull_request import (  # noqa: E402
    GENERAL_MARKER,
    PullRequestValidationError,
    validate_pr_body,
)


ROOT = Path(__file__).parents[2]


class PullRequestValidationTests(unittest.TestCase):
    def test_accepts_template_and_custom_descriptions(self):
        template = (ROOT / ".github/PULL_REQUEST_TEMPLATE/general.md").read_text(
            encoding="utf-8"
        )
        for body in (
            template,
            "## Validation\n\nPassed locally.\n\n## Changes\n\nFixed scroll.",
            "Fixed scroll after late item measurement.",
            GENERAL_MARKER + "\n\nCustom description",
        ):
            with self.subTest(body=body):
                self.assertEqual(validate_pr_body(ROOT, body, ["docs/guide.md"]), "general")

    def test_rejects_empty_or_comment_only_body(self):
        for body in ("", "  \n", GENERAL_MARKER):
            with self.subTest(body=body):
                with self.assertRaisesRegex(PullRequestValidationError, "description"):
                    validate_pr_body(ROOT, body, ["docs/guide.md"])

    def test_default_github_template_matches_general_template(self):
        default = (ROOT / ".github/pull_request_template.md").read_text(
            encoding="utf-8"
        )
        general = (ROOT / ".github/PULL_REQUEST_TEMPLATE/general.md").read_text(
            encoding="utf-8"
        )
        self.assertEqual(default, general)


if __name__ == "__main__":
    unittest.main()
