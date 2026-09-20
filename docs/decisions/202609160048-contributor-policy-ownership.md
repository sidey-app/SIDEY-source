# Contributor policy와 실행 검증의 소유권

Status: Accepted
Decided: 2026-09-16 00:48 KST
Evidence: [commit 5c8a857](https://github.com/sidey-app/SIDEY-source/commit/5c8a857637f315d2339bd027a2dc3a50ae0d642a)

## Context

Agent instruction, 사람용 contribution 안내, specialist skill과 validation script가 같은
정책을 반복하면 시간이 지나며 서로 다른 규칙을 말하게 된다. 모든 변경을 chronological
decision log에 추가하는 방식도 현재 작업에 필요한 source를 찾기 어렵게 만들었다.

## Decision

`AGENTS.md` 계층은 scope별 source와 안전 규칙으로 routing하고, `CONTRIBUTING.md`는
사람용 contribution flow를 설명한다. 반복 가능하고 기계적으로 판정할 수 있는 조건은
tracked script와 CI가 소유한다. Skill은 특정 판단과 evidence workflow만 추가하며 정책과
validation logic을 복제하지 않는다. Ordinary implementation history는 Git/PR에 맡긴다.

## Consequences

Contributor가 모든 장기 지식을 하나의 instruction file에서 읽을 필요가 없다. 정책을
바꿀 때는 실제 owner를 한 곳에서 바꾸고 router와 validator가 그 owner를 가리키게 해야
한다. Repository-wide migration은 명시된 예외와 affected CI scope를 지켜야 한다.
