# 캐릭터와 cosmetic의 독립 소유권

Status: Accepted
Decided: 2026-09-12 00:31 KST
Evidence: [commit 2ff9169](https://github.com/sidey-app/SIDEY-source/commit/2ff9169fe2866c87774914d6445a9b9a782cee53)

## Context

초기 character 상품에는 관련 projectile 권리가 함께 묶여 있었다. Cosmetic을 별도
상품으로 제공하고 모든 character에 장착하려면 신규 구매의 독립 소유권과 과거 포함
구매의 기존 권리를 동시에 보존해야 했다.

## Decision

Character, bubble과 projectile entitlement를 서로 독립시킨다. 캐릭터–애착 물건 관계는
preview와 소개를 위한 metadata이며 신규 character 구매가 물건 권리를 자동 부여하지
않는다. 과거 포함 구매의 물건 권리는 원래 grant source에 연결해 보존한다. 장착하지
않은 projectile은 공통 기본값을 사용한다.

## Consequences

사용자는 보유한 cosmetic을 지원되는 어떤 character에도 장착할 수 있다. Refund나
revocation은 해당 source가 부여한 권리만 회수한다. Client와 backend는 ownership과
equipped state를 별도로 처리해야 한다.
