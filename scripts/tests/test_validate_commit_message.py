import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "validate_commit_message",
    Path(__file__).parents[1] / "skills" / "commit" / "validate_commit_message.py",
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class CommitMessageValidatorTests(unittest.TestCase):
    def test_supported_types_and_scopes(self):
        for commit_type in validator.ALLOWED_TYPES:
            with self.subTest(commit_type=commit_type):
                self.assertEqual(validator.validate_subject(f"{commit_type}: 변경"), [])
        self.assertEqual(validator.validate_subject("test(test/release): 변경"), [])

    def test_rejects_invalid_type_scope_or_empty_summary(self):
        self.assertTrue(validator.validate_subject("feature: 변경"))
        self.assertTrue(validator.validate_subject("chore(bad scope): 변경"))
        self.assertTrue(validator.validate_subject("chore:   "))
        self.assertTrue(validator.validate_subject("chore 변경"))

    def test_accepts_long_english_subject_with_period(self):
        subject = "fix(history): " + "Messages remain visible after resize " * 3 + "."
        self.assertEqual(validator.validate_subject(subject), [])

    def test_accepts_long_body_without_exact_footer_format(self):
        message = (
            "fix(history): 스크롤 수정\n\n"
            + "늦게 측정된 메시지도 최신 위치까지 이동하도록 처리합니다. " * 5
            + "\n\nRelated to: #305, #306\n"
            + "Co-authored-by: codex <codex@openai.com>\n"
        )
        self.assertEqual(validator.validate_message(message), [])

    def test_accepts_body_without_blank_separator(self):
        self.assertEqual(
            validator.validate_message("docs: 설명 추가\nShort context\n"), []
        )

    def test_rejects_empty_message_or_invalid_subject(self):
        self.assertTrue(validator.validate_message(""))
        self.assertTrue(validator.validate_message("Invalid title\n\nContext"))

    def test_accepts_generated_merge_subject(self):
        self.assertEqual(
            validator.validate_subject(
                "Merge pull request #115 from sidey-app/windows/ci-runtime-windows"
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
