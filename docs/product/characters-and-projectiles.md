# 캐릭터와 투척물

## Asset 계약

승인된 캐릭터, 말풍선과 투척물의 정확한 목록·frame 구조·fallback·platform support와
SHA-256은 [`assets/v1/manifest.json`](../../assets/v1/manifest.json)이 소유한다. 판매
metadata와 캐릭터–애착 물건 관계는
[`assets/v1/commerce-catalog.json`](../../assets/v1/commerce-catalog.json)이 소유한다.
이 문서는 ID 목록, 개수 또는 hash를 복제하지 않는다.

캐릭터 원본은 작은 logical pixel grid와 결정적인 animation frame을 사용한다. 각
platform은 integer nearest-neighbor 확대, 투명 배경, 고정 frame rate와 실시간 그림자
없는 renderer를 유지한다. Platform bundle mirror는 manifest에서 지원을 선언한 asset만
생성한다. 알 수 없는 character나 projectile은 manifest의 fallback을 사용한다.

## Pixel world

활성 group의 member는 선택한 monitor 가장자리의 1차원 track을 걷거나 idle 상태를
보인다. Online, away, offline과 reconnect 상태는 동작과 상태 점으로 구분하며 typing은
캐릭터 motion을 바꾸지 않는다. 좌표와 animation frame은 network로 보내지 않고 각
client가 동일한 product rule로 계산한다.

macOS에서 캐릭터가 monitor의 좌측 또는 우측 가장자리에 붙어도 메시지와 typing
말풍선은 화면 기준 가로 방향을 유지한다. 말풍선 본체·장식·글자는 회전하지 않고,
꼬리만 해당 캐릭터 쪽을 향한다. 캐릭터 자체는 발이 선택한 가장자리를 향하도록 기존처럼
회전한다.

Overlay surface는 기본적으로 pointer input을 통과시킨다. 캐릭터 상호작용을 위한 별도
hotspot만 입력을 받고 나머지 surface는 통과한다. 자신의 캐릭터 pulse와 친구에게 던지는
projectile은 transient event로 공유하지만 trajectory는 각 client가 현재 위치에서
계산한다.

Equipped projectile이 없거나 알 수 없으면 manifest의 기본 projectile을 사용한다.
캐릭터와 애착 물건의 상품 소유권은 서로 독립적이다. 반복 충돌은 일시적인 stun을
만들 수 있지만 메시지와 이미 발사된 projectile은 유지한다. 정확한 timing과 threshold는
native source와 tests가 소유한다.

## 검토 자료

`docs/reviews/`와 asset candidate directory는 승인 과정이나 재현 evidence가 현재 asset
검증에 직접 필요할 때만 유지한다. 현재 shipped asset의 권위는 review prose가 아니라
manifest, source pin과 실제 bundle이다.
