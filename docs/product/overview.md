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

## macOS 조작

최초 온보딩 중이거나 설정 창이 열려 있는 동안에는 Dock에 일반 app으로 표시한다. 그
밖에는 로그인 항목을 통한 자동 실행과 사용자의 수동 실행 모두 메뉴바 accessory app으로
동작한다. 설정 창을 닫으면 accessory app으로 복귀하고, 최근 기록 창만 열려 있을 때는
Dock icon을 표시하지 않는다. 메뉴바 메뉴에서 설정, 최근 기록과 종료에 접근한다.

설정 창은 어느 Space에서 열든 현재 활성 Space로 옮겨 표시하며, 이전에 설정 창이 있던
Space로 사용자를 전환하지 않는다.

캐릭터를 한 번 클릭하면 시스템 double-click 판정 시간이 지난 뒤 입력창을 토글한다.
두 번 클릭하면 대기 중인 단일 클릭을 취소하고 기존 리액션만 실행하며, 이미 열린
입력창도 변경하지 않는다.

입력창에는 명시적인 X 닫기 버튼이 없다. 입력창 바깥 클릭, Escape 또는 전역 입력창
토글로 닫는다.

전역 단축키는 `Ctrl+Option+Command+M`으로 조용히 모드,
`Ctrl+Option+Command+I`로 입력창 토글, `Ctrl+Option+Command+R`로 최근 기록 열기를
실행하고 `Ctrl+Option+Command+H`로 오버레이 표시를 토글한다. 메뉴바 메뉴와 설정에는
현재 적용된 단축키를 표시한다. 설정에서 이 네 전역 단축키의 영문·숫자 키와
수정 키 조합을 각각 바꿀 수 있다. 등록에 성공한 변경은 즉시 적용하고 로컬에 저장해
다음 실행에도 복원한다. 같은 앱 안에서 단축키가 중복되거나 macOS에 새 조합을 등록하지
못하면 해당 항목에 원인을 안내하고 마지막으로 등록된 유효한 조합을 계속 사용한다.
키를 누른 채 유지해도 반복 실행하지 않는다.

입력창 왼쪽의 전용 손잡이로 창 크기를 유지한 채 다른 모니터까지 옮길 수 있다.
모니터 식별자와 화면 내 상대 위치를 로컬에 저장하고 캐릭터 모니터 설정과 독립적으로
복원한다. 저장한 모니터가 사라지거나 해상도가 바뀌면 현재 화면 안으로 위치를 보정한다.
캐릭터의 입력창 회피 영역은 실제 입력창 위치를 따른다.

## 문서 경계

이 디렉터리는 현재 제품 동작만 설명한다. 가격, 상품 ID, asset hash, version과 build
같은 실제 값은 [아키텍처의 source 안내](../architecture.md#배포-산출물)와 각
machine-readable source를 직접 확인한다. 과거 작업 과정은 Git/PR, 장기 선택 이유는
[`docs/decisions/`](../decisions/README.md)를 사용한다.
