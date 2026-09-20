# 비공개 source와 공개 배포 저장소 분리

Status: Accepted
Decided: 2026-09-20 22:55 KST
Supersedes: [코드 공개 라이선스와 에셋 기여 경계](202609171825-source-license-and-asset-boundary.md)

## Context

SIDEY의 현재 application·website source와 개발 이력은 비공개로 운영하되, 기존 website,
Windows update와 release download URL은 설치된 client와 사용자에게 계속 제공해야 한다.
기존 AGPL revision에 이미 부여한 권리는 source 저장소의 visibility나 이후 license를
바꾼다고 소급해서 철회할 수 없다.

## Decision

현재 source와 전체 개발 이력은 비공개 `sidey-app/SIDEY-source`가 소유한다. 공개
`sidey-app/SIDEY` 이름은 기존 URL 호환을 위해 유지하고, 검증된 정적 website output,
공개 정책 문서, release metadata와 설치 binary를 제공한다. 계속 배포하는 과거 AGPL
binary에는 그 binary를 만든 정확한 Corresponding Source archive와 license notice도
release별로 제공한다. 공개 배포 저장소는 현재 제품 source의 원본이 아니다.

현재 [`LICENSE`](../../LICENSE) 고지를 처음 포함한 Git revision과 그 이후의 SIDEY
source는 별도 표시가 없는 한 독점 software로 관리한다. 그보다 앞서 AGPL-3.0-only로
공개된 revision의 license와 이미 부여된 권리는 유지한다. 제3자 component, 기존
기여자 저작권·표시, asset의 별도 license와 계약도 그대로 보존한다.

외부 code, test, 문서, 번역과 asset contribution은 받지 않는다. 공개 저장소의 Issues는
재현 가능한 제품 bug 신고에만 사용하고 기능 제안과 Pull Request는 받지 않는다.

## Consequences

Private source workflow가 website와 Windows release artifact를 만들고 검증한 뒤 공개
저장소에 최소 권한으로 게시한다. Public repository에서 current source를 복원하거나 생성 결과를
원본으로 편집하지 않는다. Browser에 전달되는 HTML, CSS와 JavaScript 및 공개 binary는
배포 특성상 내려받을 수 있지만, 그 사실만으로 현재 private source의 license가 부여되지
않는다.

기존 공개 fork와 clone은 회수할 수 없고, 과거 revision의 AGPL 권리는 계속 유효하다.
Repository 이름 전환과 public artifact migration은 website, update manifest, release URL이
검증된 뒤에만 private visibility 전환을 완료한다.
