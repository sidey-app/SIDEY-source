# SIDEY Release-note Format

Read this reference before writing or revising a canonical macOS or Windows release note.

## Default GitHub Release body

Write a short final-user summary, then the exact `## 변경사항` heading, attributed bullets and the comparison URL:

```markdown
SIDEY를 설치할 수 있는 Windows 버전을 넓히고, 프로그램 안정성을 개선했어요.

## 변경사항

- Windows 10 1809 이상 x64에서도 설치 가능하도록 수정했어요. ( #107, @patulus )
- 창 크기를 바꿀 때 앱이 종료되는 문제를 수정했어요. ( #108, @patulus )

**전체 변경 내역**: https://github.com/sidey-app/SIDEY/compare/windows-v1.3.0...windows-v1.3.1
```

The opening summary describes the important outcome at a higher level than the bullets. Prefer `프로그램 안정성을 개선했어요.` over repeating a detailed fix such as `창 크기를 바꿀 때 앱이 종료되는 문제를 수정했어요.`

## Change bullets

- Describe included pull requests and direct commits. Use a separate bullet when the same PR or commit contains materially different user outcomes. Combine closely related work into one sentence when it is one coherent feature or fix.
- Keep each bullet to one sentence and one physical line. Avoid chaining unrelated changes with connective endings.
- End a PR bullet with `( #번호, @작성자 )`, using the PR opener's GitHub login.
- End a direct-commit bullet with `( 7자리커밋, @작성자 )` as described in the evidence reference.
- Use the same PR or commit reference on multiple bullets when distinct outcomes genuinely require separate bullets.

For Windows and historical Direct macOS GitHub Release bodies, the comparison line is the last nonblank line and uses the exact platform tags:

```markdown
**전체 변경 내역**: https://github.com/sidey-app/SIDEY/compare/이전-태그...대상-태그
```

## App Store Connect notes

An App Store note is a separate artifact. Require the exact submitted build, prior published App Store build, App Store Connect evidence and requested localization before drafting it. Do not add a GitHub comparison link or write it over `docs/releases/v<version>.md`; those files preserve historical Direct GitHub Release bodies.

## User-requested preamble or sections

When the user supplies wording but does not designate a separate section, preserve that wording before a thematic break, then write the normal summary and body:

```markdown
사용자 요청 문구

---

최종 사용자 친화적 설명

## 변경사항

- 변경 사항을 설명해요. ( #123, @author )

**전체 변경 내역**: https://github.com/sidey-app/SIDEY/compare/이전-태그...대상-태그
```

Add installation, warnings, known limitations or another heading only when the user explicitly requests it or verified user action or risk makes the section necessary. Do not add a title or date by default; the canonical file is also the GitHub Release body.
