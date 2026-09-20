# Server-authoritative entitlement

Status: Accepted
Decided: 2026-09-02 00:57 KST
Evidence: [commit a03c922](https://github.com/sidey-app/SIDEY-source/commit/a03c922d72402e61e4cbbd243cfd988e57742271)

## Context

Client 가격, 결제 성공 redirect와 local cache를 구매 완료나 상품 선택 권한의 근거로
사용하면 client를 변조해 권리를 우회할 수 있었다.

## Decision

Backend가 주문 가격, 결제 승인과 entitlement를 판정한다. Client는 활성 entitlement가
있는 상품만 선택하고 장착하며 server-confirmed snapshot만 소유권 근거로 사용한다.

## Consequences

Client는 redirect, local receipt 또는 catalog만으로 권리를 만들지 못한다. 회수된
entitlement는 안전한 기본값으로 돌아가며 결제 secret과 검증 구현은 backend에만 둔다.
