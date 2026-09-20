# SIDEY 픽셀 에셋 라이브러리

이 폴더는 SIDEY에서 사용하는 승인된 픽셀 에셋의 원본입니다. 기준 규격은
[`v1/manifest.json`](v1/manifest.json)과 캐릭터별 `base.png`, `throw_hit.png`,
말풍선별 `decoration.png`·`preview.png`, 투척물별 `sprite.png` 및 필요한
별도 emitter·preview입니다.

앱과 웹 폴더에 있는 같은 PNG 및 Windows BGRA 파일은 배포용 복사본입니다.
해당 파일은 직접 편집하지 않고 이 폴더의 원본에서 갱신합니다.

에셋 검토 도구는 비공개 source 저장소의 로컬 개발 환경에서만 사용합니다. 외부 에셋
기여는 받지 않습니다.

![햄스터 기본·throw/hit·패치 말랑공 공식 8배 참고 이미지](v1/reference/pixel_hamster_reference.png)

## 라이선스

`v1/manifest.json`의 `licensing`에 등록된 유료 캐릭터·말풍선·투척물은
[SIDEY Paid Asset License 1.0](PAID_ASSET_LICENSE.md)이 적용되는 독점 에셋입니다.
비공개 source 저장소에서 관리하며 오픈소스 에셋이 아닙니다.

공식 SIDEY 앱이 계정의 사용 권한에 따라 표시하거나, SIDEY 개발·검토를 위해
로컬에서 확인하는 범위만 허용합니다. 다른 앱이나 상품에서 복제·수정·재배포·판매할
수 없으며, 앱·웹·Windows BGRA mirror에도 같은 조건이 적용됩니다.

이 라이선스는 manifest에 유료로 지정되지 않은 에셋이나 소프트웨어 코드에는
적용되지 않습니다. 다른 에셋은 별도 라이선스가 명시되지 않았다면 기본 저작권
조건을 따릅니다. 과거 공개 revision의 AGPLv3 적용 범위와 현재 독점 source,
제3자 자료의 구분은
[라이선스 안내](../LICENSING.md)를 확인해 주세요.

## 프레임 계약

### 기본 캐릭터 `base.png`

- `240×24` px, `24×24` px 셀 10개
- 0–1: idle 기본/호흡
- 2–5: 네 단계 보행
- 6–7: 서서 졸기/고개 끄덕임
- 8–9: 웅크린 offline 수면/호흡

### 캐릭터 동작 `throw_hit.png`

- `192×24` px, `24×24` px 셀 8개
- 0–3: 준비 → 힘주기 → 놓기 → 팔로스루
- 4–7: 접촉 → 눌림 → 튕김 → 복귀

### 투척물 `sprite.png`

- `192×16` px, `16×16` px 셀 12개
- 0–7: 프레임 사이에서 중심이 움직이지 않는 회전
- 8–11: 접촉 → 눌림 → 튕김 → 복귀

### 말풍선

- `decoration.png`: `16×16` px RGBA 좌상단 장식
- `preview.png`: `128×48` px, 실제 글꼴·글자색을 포함한 전체 말풍선
- 핑크 토끼·버터 병아리의 글자는 `#1C1F29`, 별밤 고양이는 `#FFF7E8`

### 미니 대포

- `emitter.png`: `96×24` px, `24×24` px 셀 4개(등장·준비·발사·반동)
- `sprite.png`: `192×16` px, 심지탄 비행 8프레임과 폭발 4프레임
- emitter는 캐릭터 앞 몸통에 겹치고 폭발은 피격자 몸통 높이에 표시

## 공통 제작 규칙

- sRGB, 8-bit RGBA, hard alpha(`0` 또는 `255`), 투명 배경
- 캐릭터 모든 프레임의 가장 낮은 불투명 픽셀은 바닥에서 3px 위의 같은 발 기준선
- 투척물 0–7 프레임의 회전 중심은 `7.5, 7.5`에 고정
- 안티앨리어싱과 실시간 그림자 금지
- 화면 확대는 `2×`, `3×`, `4×` 같은 정수 nearest-neighbor만 사용
- 픽셀을 흐리게 만드는 비정수 크기, 선형 보간, 반투명 가장자리 금지

별빛 우파루파처럼 idle 상태에서 후광처럼 보이는 ambient sparkle과 더블클릭
particle burst 효과를 제안할 수 있습니다. 이러한 효과는 PNG 프레임이 아니라
별도의 렌더러 기능입니다. 성능·색상·밀도·지속 시간 검토와 macOS·Windows별
구현이 필요하며, 에셋 파일만으로 제품에서 자동 활성화되지는 않습니다.

## 유지관리자의 에셋 검증

기존 에셋을 유지보수할 때는 manifest의 경로·SHA-256·플랫폼 지원 정보와 캐릭터별
투척물 매핑을 함께 확인합니다. 공용 원본은
`python3 scripts/validate_pixel_assets.py --canonical-only`, 플랫폼 mirror까지 포함한
검증은 옵션 없이 실행합니다. 변경 이유와 검증 결과는
[일반 PR 양식](../.github/PULL_REQUEST_TEMPLATE/general.md)에 기록합니다.
공용 변경과 각 플랫폼의 배포 복사본 갱신은 별도 PR로 순차 진행합니다.

검사 통과를 위해 규격을 억지로 재인코딩하지 말고 원본 제작 파일에서 문제를
바로잡아 주세요. 승인된 `v1` 파일을 변경해야 한다면 기존 hash를 조용히 덮지
말고 변경 이유와 호환 영향을 함께 리뷰해야 합니다.

## 상품 수정

자산 규격은 `manifest.json`, 상품 ID·가격·권리·현재/과거 Apple ID와 애착 물건 연결은
[`v1/commerce-catalog.json`](v1/commerce-catalog.json)이 원본입니다.

1. `shared/*` 작업에서 상품 원본과 필요한 승인 자산을 수정합니다.
2. `python3 scripts/commerce_catalog.py --target shared --write`로 상점·checkout 공통 상품 표현을 생성합니다.
   서버용 verifier 매핑과 Edge Function 허용 목록은 비공개 backend 저장소에서 생성합니다.
3. `--target shared --check`는 바이트 차이·중복 ID·권리·자산 참조를 검사합니다.
4. 공통 PR 통합 뒤 별도 `macos/*` 작업에서 `--target macos --write --source-commit <검토된-전체-SHA>`로 번들 사본을 갱신합니다.
   `catalog-source.json`은 원본 커밋과 상품·manifest SHA-256을 기록합니다.
   검사는 해당 Git 원본과 번들을 대조하므로 CI와 로컬에 원본 커밋 이력이 필요합니다.
   공용 변경과 플랫폼 소비는 순차 통합하며, 아직 갱신하지 않은 플랫폼은 기록된 원본으로 검사합니다.
   `--target macos --check`는 번들 사본과 현재 StoreKit 상품 ID·비소모성 유형·가격을 검사합니다.
   StoreKit 등록·지역·심사 설정 전체를 생성기로 덮어쓰지 않습니다.
5. 서버 반영이 필요한 상품 변경은 [비공개 backend 저장소](https://github.com/sidey-app/sidey-backend)의
   현재 clone에서 진행합니다. 검토한 비공개 source 커밋의 상품·manifest snapshot과 출처를 기록하고 서버용 매핑을
   생성·검증합니다. DB migration·verifier 검사·배포도 해당 저장소의 절차를 따릅니다.
   source 원본 변경만으로 운영 상품이나 결제 서버에 반영되지는 않습니다. 자세한 경계는
   [백엔드 개발 안내](../docs/BACKEND.md)를 참고합니다.
6. 영어·일본어 유료 상품 소개는 `website/src/data/store-translations.ts`에서 관리합니다.
   번역 누락은 웹 빌드를 실패시킵니다. 기본 제공 7종은 상점의 명시 목록으로 유지합니다.

생성에는 하나의 대상을 반드시 지정합니다. `all` 쓰기 옵션은 제공하지 않으며 반대 플랫폼을
수정하지 않습니다. 원격 상품 등록·판매 활성화·가격 및 서버 배포는 별도 작업입니다.

웹 배포 사본의 경로는 manifest의 `web_directory`를 따른다. 상품 캐릭터·투척물은 `assets/store`, 기본 캐릭터는 `assets/characters`, 기본 공은 `assets/previewer`를 사용한다. checkout도 같은 스프라이트를 사용한다. 별도로 쓰이는 랜딩 이미지 사본은 `additional_base_mirrors`로 명시하며, 사용이 끝난 웹 중간 사본을 지울 때는 이 경로 계약도 함께 갱신한다.
