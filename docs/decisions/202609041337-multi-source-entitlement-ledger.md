# 여러 지급 source를 보존하는 entitlement ledger

Status: Accepted
Decided: 2026-09-04 13:37 KST
Evidence: [commit 222428b](https://github.com/sidey-app/SIDEY-source/commit/222428b92579712e7d9e242c1dbc81200f8efcb3)

## Context

직접 결제, App Store transaction과 complimentary 지급이 같은 상품 권리를 만들 수
있다. 한 entitlement 행에 source를 덮어쓰면 한 source의 refund가 다른 유효한 지급까지
회수할 수 있었다.

## Decision

Backend는 payment source별 grant와 transaction을 private ledger에 보존한다. Client가
읽는 entitlement는 현재 활성 grant의 projection이다. Purchase, restore, refund와
revocation은 source별로 멱등하게 처리한다.

## Consequences

한 grant가 회수돼도 다른 활성 source가 남으면 entitlement는 유지된다. Client는
ledger를 수정하지 않는다. 내부 schema와 verifier 구현은 비공개 backend가 소유하고
public repository에는 client-facing projection contract만 둔다.
