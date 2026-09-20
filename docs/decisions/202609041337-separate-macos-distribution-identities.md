# macOS distribution identity 분리

Status: Superseded
Superseded by: [macOS App Store 단일화](20260918-macos-app-store-only.md)
Decided: 2026-09-04 13:37 KST
Evidence: [commit 222428b](https://github.com/sidey-app/SIDEY/commit/222428b92579712e7d9e242c1dbc81200f8efcb3)

## Context

기존 Developer ID 직접 배포판의 익명 session, 외부 identity 연결, 결제와 Sparkle
update를 유지하면서 Mac App Store의 sandbox, Sign in with Apple과 StoreKit 규칙을
충족해야 했다. 같은 local identity와 storage를 두 distribution이 공유하면 기존
session과 App Store account의 의미가 모호해졌다.

## Decision

직접 배포판과 Mac App Store판을 별도 product identity로 운영한다. 핵심 app source는
공유하지만 bundle, authentication, Keychain, preferences, commerce, entitlement,
signing과 update 경계는 분리한다. Direct account와 App Store account는 자동으로
이전하거나 병합하지 않는다.

## Consequences

같은 사람도 두 distribution에서 별도 SIDEY user가 될 수 있고 같은 room에서는 각각
member로 계산된다. Group을 이어 쓰려면 새 account를 초대해야 한다. 기능을 공유할 때도
distribution-specific dependency나 credential이 다른 target에 들어가지 않도록 검증한다.
