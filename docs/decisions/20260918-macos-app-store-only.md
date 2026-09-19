# macOS 배포를 Mac App Store로 단일화

- Status: Accepted
- Decided: 2026-09-18
- Supersedes: [macOS distribution identity 분리](202609041337-separate-macos-distribution-identities.md)

## 결정

macOS 직접 배포판의 개발·지원과 DMG, Sparkle, Homebrew 배포 경로를 종료한다.
macOS는 Mac App Store판만 유지하고 Windows 지원·설치·업데이트는 유지한다.

## 이유와 경계

서로 다른 macOS signing, update, storage와 commerce 경계를 중복 유지하는 비용을
줄이고 App Store판의 안정성과 실시간 이관 작업에 집중한다. 과거 공개 release 기록과
기존 사용자 계정, 메시지, 구매 원본은 삭제하지 않는다. 기존 distribution 사이의
계정·저장소 자동 병합 금지 경계는 유지한다. 배포 종료가 기존 고객의
entitlement 회수나 자동 데이터 이전을 의미하지 않는다.

웹과 README의 macOS 설치 링크는 App Store만 제공한다. 직접 배포용 build·검증·배포
경로를 제거하되 Windows checkout과 공용 commerce 자산은 보존한다. 소스 변경은
App Store 제출, website 배포 또는 기존 release 삭제를 자동으로 승인하지 않는다.

현재 배포 계약은 [배포와 제공 채널](../product/distribution.md), 실행 절차는
[release operation](../operations/release.md)을 따른다.
