# 공통 Product Version과 플랫폼별 카운터

Status: Accepted
Decided: 2026-09-24
Supersedes: [Platform별 독립 versioning](202609070106-independent-platform-versioning.md)

## Context

플랫폼마다 사용자가 보는 제품 버전을 따로 관리하면 같은 SIDEY 기능 세대가 서로 다른
버전으로 표시되고, 네이티브 프로젝트와 배포 메타데이터에 같은 값을 반복해서 적어야 했다.
Windows는 같은 제품 버전 안에서도 독립적인 수정 배포를 구분할 수 있어야 하고, macOS는
App Store에 이미 올린 빌드 번호를 다시 사용할 수 없다.

## Decision

macOS와 Windows는 하나의 Product Version을 공유한다. `release/version.json`이 Product
Version, Windows revision과 macOS build number를 소유하며 플랫폼별 네이티브 설정과
release manifest는 여기서 생성한다. Windows 전용 수정 배포는 Product Version을 바꾸지
않고 Windows revision을 올리며, macOS 새 업로드는 macOS build number를 올린다.

## Consequences

Product Version을 바꾸면 두 플랫폼의 다음 빌드가 같은 사용자 표시 버전을 사용하고
Windows revision은 0으로 돌아간다. 한 플랫폼만 다시 배포할 때는 해당 플랫폼 카운터만
올릴 수 있으므로 다른 플랫폼 artifact를 만들거나 게시할 필요는 없다. 버전 원본 변경과
플랫폼별 generated mirror 연결은 경로 소유권에 맞는 별도 변경으로 검증해 순서대로 합친다.
