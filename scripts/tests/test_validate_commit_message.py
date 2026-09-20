import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "validate_commit_message",
    Path(__file__).parents[1]
    / "skills"
    / "commit"
    / "validate_commit_message.py",
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

ROOT = Path(__file__).parents[2]


class CommitMessageValidatorTests(unittest.TestCase):
    def test_accepts_each_supported_type_with_optional_scope(self):
        for commit_type in validator.ALLOWED_TYPES:
            with self.subTest(commit_type=commit_type):
                self.assertEqual(
                    validator.validate_subject(
                        f"{commit_type}: 기여자 계약 정리"
                    ),
                    [],
                )
        for scope in ("release", "test/release", "Shared"):
            with self.subTest(scope=scope):
                self.assertEqual(
                    validator.validate_subject(
                        f"chore({scope}): 검증 계약 정리"
                    ),
                    [],
                )

    def test_rejects_nonstandard_type_spellings(self):
        for commit_type in ("feature", "preformance", "cicd"):
            with self.subTest(commit_type=commit_type):
                violations = validator.validate_subject(
                    f"{commit_type}: 기여자 계약 정리"
                )
                self.assertTrue(
                    any("type" in violation for violation in violations)
                )

    def test_rejects_invalid_scope(self):
        violations = validator.validate_subject(
            "chore(macOS Direct): 기여자 계약 정리"
        )
        self.assertTrue(any("scope" in violation for violation in violations))

    def test_rejects_malformed_or_non_korean_subject(self):
        self.assertTrue(validator.validate_subject("chore Shared: 기여자 계약 정리"))
        self.assertTrue(
            validator.validate_subject("chore: contributor contract")
        )
        self.assertTrue(
            validator.validate_subject("chore: 기여자 계약 정리 ")
        )

    def test_summary_limit_excludes_generated_pr_number_suffix(self):
        summary = "가" * validator.MAX_SUMMARY_LENGTH
        self.assertEqual(
            validator.validate_subject(f"feat: {summary} (#123)"),
            [],
        )
        violations = validator.validate_subject(f"feat: {summary}가")
        self.assertTrue(
            any("characters or fewer" in item for item in violations)
        )

    def test_rejects_summary_ending_with_period(self):
        violations = validator.validate_subject("fix: 연결 오류 수정.")
        self.assertTrue(any("period" in item for item in violations))

    def test_full_message_accepts_72_character_body_and_attribution(self):
        message = (
            "chore(commit): 커밋 검증기 추가\n\n"
            f"{'가' * validator.MAX_BODY_LINE_LENGTH}\n\n"
            "Co-authored-by: codex <codex@openai.com>\n"
        )
        self.assertEqual(validator.validate_message(message), [])

    def test_rejects_long_body_or_missing_subject_separator(self):
        long_body = "가" * (validator.MAX_BODY_LINE_LENGTH + 1)
        violations = validator.validate_message(
            f"docs: 규칙 설명 추가\n\n{long_body}\n"
        )
        self.assertTrue(any("body line" in item for item in violations))
        violations = validator.validate_message(
            "docs: 규칙 설명 추가\n본문을 바로 시작해요.\n"
        )
        self.assertTrue(any("blank line" in item for item in violations))

    def test_accepts_supported_issue_footers_and_rejects_bad_reference(self):
        for token in (
            "Resolves",
            "Closes",
            "Fixes",
            "See also",
            "Ref",
            "Related to",
        ):
            with self.subTest(token=token):
                message = f"fix: 문제 수정\n\n{token}: #123\n"
                self.assertEqual(validator.validate_message(message), [])
        violations = validator.validate_message(
            "fix: 문제 수정\n\nResolves: issue-123\n"
        )
        self.assertTrue(any("Issue footer" in item for item in violations))

    def test_accepts_documented_korean_example(self):
        message = (
            "fix: 클라이언트에서 API 응답에 접근할 수 없는 문제 수정\n\n"
            "CORS 설정이 없어 SOP에 의해 API 응답에 접근할 수 없어요.\n"
            "CORS 헤더를 추가하도록 요청과 응답 필터를 수정해요.\n\n"
            "Resolves: #273\n"
            "See also: #266\n"
        )
        self.assertEqual(validator.validate_message(message), [])

    def test_accepts_known_generated_merge_subjects(self):
        subjects = (
            "Merge pull request #115 from sidey-app/windows/ci-runtime-windows",
            "Merge commit 'e4458779167777e95cc2636047f241a595386c30' into windows/ci-runtime-windows",
            "Merge branch 'main' into shared/example",
            "Merge remote-tracking branch 'origin/main' into windows/example",
        )
        for subject in subjects:
            with self.subTest(subject=subject):
                self.assertEqual(validator.validate_subject(subject), [])

    def test_does_not_exempt_explicit_legacy_release_subject(self):
        self.assertTrue(
            validator.validate_subject("Publish Sparkle appcast for v1.2.3")
        )



if __name__ == "__main__":
    unittest.main()
