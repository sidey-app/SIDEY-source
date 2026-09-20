"""Tests for the canonical SIDEY release-note format."""

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).parents[1] / "validate_release_note.py"
SPEC = importlib.util.spec_from_file_location("validate_release_note", SCRIPT)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


BASE = "windows-v1.3.0"
TARGET = "windows-v1.3.1"
def note(heading="## 변경사항", attribution="PR 108, @patulus"):
    """Return one minimal valid note with replaceable fields."""

    return (
        "프로그램 안정성을 개선했어요.\n\n"
        f"{heading}\n\n"
        f"- 창 크기 변경 문제를 수정했어요. ( {attribution} )\n"
    )


def evidence(author="patulus"):
    """Return exact collector evidence for the example note."""

    return {
        "baseline": {"reference": BASE, "commit": "a" * 40},
        "target": {"reference": TARGET, "commit": "b" * 40},
        "integrations": [
            {"reference": "#108", "author": author},
        ],
    }


class ValidateReleaseNoteTests(unittest.TestCase):
    def test_accepts_default_and_user_preamble_forms(self):
        VALIDATOR.validate_note(note(), BASE, TARGET, evidence())
        source = "사용자 요청 문구\n\n---\n\n" + note()
        VALIDATOR.validate_note(source, BASE, TARGET, evidence())

    def test_rejects_old_heading_and_public_source_comparison(self):
        with self.assertRaisesRegex(VALIDATOR.NoteError, "one exact"):
            VALIDATOR.validate_note(note(heading="## 변경 사항"), BASE, TARGET)
        comparison = (
            note()
            + "\n**전체 변경 내역**: "
            + "https://github.com/sidey-app/SIDEY/compare/"
            + f"{BASE}...{TARGET}\n"
        )
        with self.assertRaisesRegex(VALIDATOR.NoteError, "must not claim"):
            VALIDATOR.validate_note(comparison, BASE, TARGET)

    def test_rejects_private_source_links_anywhere_in_public_body(self):
        source = (
            note()
            + "\n## 참고\n\n"
            + "https://github.com/SIDEY-APP/sidey-SOURCE/pull/108\n"
        )

        with self.assertRaisesRegex(VALIDATOR.NoteError, "must not link"):
            VALIDATOR.validate_note(source, BASE, TARGET)

    def test_rejects_missing_or_mismatched_attribution(self):
        with self.assertRaisesRegex(VALIDATOR.NoteError, "attributed bullet"):
            VALIDATOR.validate_note(
                note(attribution="#108"),
                BASE,
                TARGET,
            )
        with self.assertRaisesRegex(VALIDATOR.NoteError, "absent from exact"):
            VALIDATOR.validate_note(
                note(),
                BASE,
                TARGET,
                evidence("someone-else"),
            )

    def test_accepts_direct_commit_attribution_without_public_link(self):
        source = note(attribution="commit 1a2b3c4, @patulus")
        direct_evidence = evidence()
        direct_evidence["integrations"] = [
            {"reference": "1a2b3c4", "author": "patulus"},
        ]

        VALIDATOR.validate_note(source, BASE, TARGET, direct_evidence)


if __name__ == "__main__":
    unittest.main()
