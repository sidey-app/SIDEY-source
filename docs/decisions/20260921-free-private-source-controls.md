# GitHub Free 비공개 source 운영

Status: Accepted
Decided: 2026-09-21
Refines: [비공개 source와 공개 배포 저장소 분리](202609202255-private-source-public-distribution.md)

## Context

GitHub Free 조직은 private repository를 제공하지만 private branch ruleset과 environment
secret 같은 유료 보호 기능은 제공하지 않는다. SIDEY backend도 별도 ruleset과 deployment
environment 없이 private repository로 운영한다. 현재 source를 비공개로 전환하는 데 유료
GitHub Team plan 자체는 필요하지 않다.

## Decision

`sidey-app/SIDEY-source`는 GitHub Free 조직의 private repository로 운영한다. Private
ruleset이나 Actions environment에 의존하지 않고, repository-level Actions variable과
secret에 최소 권한 GitHub App 자격 증명을 저장한다. Website와 Windows release workflow는
그 App으로 공개 `sidey-app/SIDEY`의 contents만 쓸 수 있다. App 설치 범위는 그 공개
저장소 하나로 제한하고, repository 권한은 `Contents: read/write`, `Metadata: read`만
허용한다.

공개 배포 저장소의 `main`과 Pages branch에는 GitHub Free에서 제공하는 public repository
ruleset을 설정하고 유지한다. Private source에서는 task-owned branch, 필수 CI, exact-head 확인과
`scripts/skills/workflow.py` 절차가 통합 경계를 담당한다. 관리자 권한으로 우회할 수 있는
절차적 보호라는 한계를 받아들이며, 검증되지 않은 direct push를 허용한다는 뜻은 아니다.

## Consequences

GitHub Team 좌석 비용은 발생하지 않는다. Source workflow는 environment approval이나
environment secret을 사용할 수 없고, repository-level secret·variable의 접근 범위를
정기적으로 확인해야 한다. GitHub App private key는 source repository secret으로만 보관하고
공개 저장소나 build artifact, log에 복사하지 않는다. Private source workflow가 repository
secret을 읽을 수 있다는 위험은 App의 단일 공개 저장소 설치 범위와 최소 권한으로 제한한다.
