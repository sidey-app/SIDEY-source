# 제품 개요

`SIDEY`는 최대 열두 명의 가까운 친구가 2D 픽셀 동물로 화면 가장자리에 머물며
presence, typing과 짧은 메시지를 보여 주는 초대 전용 desktop ambient messenger다.
각 캐릭터는 실제 친구 한 명을 나타내며 공개 커뮤니티, AI 동료 또는 가상 반려동물
서비스가 아니다.

## 현재 제품 경계

- macOS는 Mac App Store판만 지원하고 Windows 네이티브 클라이언트를 유지한다.
  배포 채널과 지원 환경은
  [배포 문서](distribution.md)가 가리키는 machine-readable source에서 확인한다.
- 한 번에 한 private group의 친구를 overlay에 표시한다. 계정과 그룹 계약은
  [identity-and-groups.md](identity-and-groups.md)를 따른다.
- 메시지는 Postgres에 저장하고 presence와 transient event를 분리한다. 자세한 동작은
  [messaging.md](messaging.md)를 따른다.
- 캐릭터, 말풍선과 투척물은 승인 asset 및 commerce catalog에서 파생한다. 자세한
  동작은 [characters-and-projectiles.md](characters-and-projectiles.md)를 따른다.
- 공개 웹사이트는 소개·다운로드·정책·상점 정보를 제공하지만 메시징 client는 아니다.

모바일 client, 공개 검색·발견, 열두 명을 넘는 group, 이미지·파일 전송, 음성·영상
통화, 사용자 업로드 avatar와 AI 동료는 현재 범위가 아니다.

## Overlay와 개인정보

기본 overlay surface는 뒤 application으로 pointer input을 통과시킨다. 메시지 입력이나
캐릭터 상호작용처럼 명시적인 surface만 입력을 받는다. 보안 화면, DRM application,
권한이 더 높은 application 또는 모든 exclusive-fullscreen game 위 표시를 보장하지
않는다.

전역 활동 판정에는 마지막 system input 후 경과 시간과 화면 잠금 상태만 사용한다.
화면 내용, 활성 application 목록, 다른 application의 key input, 전역 mouse 좌표,
파일 내용, microphone audio 또는 camera video를 수집하지 않는다. Typing 상태는 SIDEY
입력창에서만 발생한다. E2EE는 설계·구현·검증되지 않았으므로 제공한다고 표현하지
않는다.

## 문서 경계

이 디렉터리는 현재 제품 동작만 설명한다. 가격, 상품 ID, asset hash, version과 build
같은 실제 값은 [아키텍처의 source 안내](../architecture.md#배포-산출물)와 각
machine-readable source를 직접 확인한다. 과거 작업 과정은 Git/PR, 장기 선택 이유는
[`docs/decisions/`](../decisions/README.md)를 사용한다.
