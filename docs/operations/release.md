# Release operation

이 문서는 반복 가능한 공개 release 순서를 요약한다. 실제 version, build와 artifact
이름은 machine-readable source에서 읽으며 이 문서에 고정하지 않는다. Release, store
submission, upload, website deployment와 production backend deployment는 각각 명시적인
사용자 승인이 필요하다.

현재 source와 release workflow는 비공개 `sidey-app/SIDEY-source`에서 관리한다. 공개
`sidey-app/SIDEY`는 website output, 공개 정책, release metadata, 설치 artifact와
계속 배포하는 과거 AGPL binary에 필요한 source archive를 받는 배포 저장소다. Public
저장소의 파일을 source-of-truth로 역수정하지 않는다.

## 1. 범위와 version 확인

1. Target platform과 실제 shipped diff를 확정한다.
2. [version audit](../../.agents/skills/version-audit/SKILL.md) 절차로 최소 version/build
   변경을 판단한다.
3. Platform project source와 해당 [`release/` manifest](../../release/README.md)를
   일치시킨다. macOS manifest는 App Store target build 계약이며 공개 게시 여부는
   App Store Connect에서 별도로 확인한다. Windows manifest는 공개 release를 따른다.

Commerce 또는 backend contract가 바뀌는 release라면 private source catalog의 검토된 commit과
backend snapshot provenance를 먼저 확인한다. Backend migration과 배포는 비공개
backend 저장소의 절차로 수행하며 이 저장소에서 대신 실행하지 않는다.

## 2. 검증과 release note

1. 변경 경로에 해당하는 integration check와 platform test를 정확한 candidate commit에
   실행한다.
2. Project version, release manifest, update source와 website metadata의 일치는
   `python3 scripts/skills/verify_release_consistency.py`로 검사한다.
3. Windows GitHub Release note는 [`docs/releases/`](../releases/)에
   [release-notes skill](../../.agents/skills/release-notes/SKILL.md)의 commit/PR evidence로
   작성하고 link와 attribution을 검증한다. App Store release note는 정확한 제출 build와
   App Store Connect 기록을 기준으로 작성하며, 같은 marketing version의 과거 Direct
   GitHub Release note를 재사용하거나 덮어쓰지 않는다.
4. 서명, 공증, installer 실행, store purchase 또는 실제 장시간 test처럼 수행하지 않은
   검사를 통과했다고 기록하지 않는다.

Candidate source가 검증 뒤 바뀌면 영향을 받는 검사를 다시 실행한다.

## 3. Artifact 생성과 검사

### Mac App Store

[`scripts/macos/archive_app_store.sh`](../../scripts/macos/archive_app_store.sh)로 App Store
archive를 만든다. App Store target의 bundle identity, sandbox entitlement, signing과
StoreKit 환경을 확인한다. 서명 정보와 App Store Connect 자격 증명은 저장소나 CI log에
넣지 않는다. Archive 검사 후 별도 승인된 App Store Connect upload·submission을 수행하고
심사·게시 상태를 확인한다. 직접 배포 DMG, Sparkle feed와 Homebrew Cask를 생성하거나
갱신하지 않는다. 과거 release 기록과 고객 데이터는 삭제하지 않는다.

### Windows

Private source `main`의 수동
[SIDEY Windows release workflow](../../.github/workflows/windows-release.yml)를
사용한다. Workflow가 전체 Windows 검사, installer 생성, draft asset 재다운로드와 hash
대조를 한 runner에서 마친 뒤에만 공개 배포 저장소에 publish한다. Local build나 artifact
존재만으로 공개 release를 대체하지 않는다. 교차 저장소 게시 자격 증명은 공개
`SIDEY`의 content만 쓸 수 있는 최소 권한으로 제한하며 source repository 접근 권한을
부여하지 않는다.

AGPL-covered historical binary를 계속 공개하는 release에는 binary를 만든 정확한 commit의
Corresponding Source archive, AGPL license와 필요한 notice가 함께 있어야 한다. Archive가
현재 private revision을 포함하지 않는지 확인하고 source commit, filename, size와 SHA-256을
release migration 기록에 고정한다. 이 조건을 충족하지 못하면 해당 binary를 공개 저장소로
이관하지 않는다.

## 4. 게시 후 확인

1. App Store 게시 상태 또는 Windows 공개 release artifact와 기대 hash를 다시 확인한다.
2. macOS 링크가 App Store를 가리키는지, Windows update manifest와 website가
   같은 공개 release를 가리키는지 확인한다.
3. App Store Connect 또는 GitHub의 platform release note가 공개 결과와 일치하는지 확인한다.
4. 별도 승인된 경우에만 store submission, website deployment 또는 backend deployment를
   수행하고 각각의 결과를 해당 system에서 검증한다.

과거 특정 release의 시행착오와 일회성 checklist는 Git/PR 및 GitHub Release history에
맡긴다.
