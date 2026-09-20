# 공유 asset manifest

Status: Accepted
Decided: 2026-09-03 17:56 KST
Evidence: [commit 79f3afb](https://github.com/sidey-app/SIDEY-source/commit/79f3afbdfe2a76b4c3a156aa341a078ec0b64594)

## Context

Platform별 manifest와 작업 중 image가 각각 원본처럼 남아 있으면 path, frame 규격,
fallback, platform support와 hash가 서로 어긋날 수 있었다.

## Decision

`assets/v1/manifest.json`과 그 아래 승인 asset을 canonical source로 둔다. Native app과
website의 배포용 asset은 manifest에서 생성하고 원본과 일치를 검증하는 mirror로
취급한다. Candidate와 review image는 승인 원본에 포함하지 않는다.

## Consequences

정확한 asset 목록, 규격, platform support와 SHA-256은 manifest가 소유하며 Markdown에
표로 복제하지 않는다. Mirror를 독립 원본으로 편집하지 않고 provenance를 검증한다.
