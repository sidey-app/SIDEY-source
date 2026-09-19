# Mac App Store 후보 점검 — 2026-09-12

> 아래 내용은 당시 후보와 검증 기록이에요. 현재 macOS는 App Store만 유지하며 Direct·Sidey-dev·DMG 배포 경로는 종료했어요. 과거 설치 경로·직배포 지침은 현재 작업 절차로 사용하지 마세요. 현재 빌드와 테스트는 [macOS 지침](../AGENTS.md)을 따라주세요.

현재 App Store 후보: `macos/appstore-latest`, 마케팅 버전 1.2.1, build 31.
원숭이 현재 판매 ID는 `character_monkey_solo_4`다. Xcode 기록의 App Store 성공 업로드 27과 공개 직배포 29를 확인해 후보 번호 30을 배정했다. 아래 build 27/28 기록은 이전 시점의 검증이다.
이 문서는 로컬 구현·검증 상태다. 원격 상품 등록·서버 배포·심사 제출 완료를 뜻하지 않는다.

## 구현 완료

- 상세창은 실제 내용 높이에 맞추고 긴 내용만 스크롤한다. 애착 물건 카드는 사용 범위 안내 대신 짧은 농담이 담긴 소개를 표시한다.
- A안 상세 화면: 한 미리보기 무대 아래 캐릭터와 **애착 물건** 구매 카드를 나란히 표시한다. 두 상품의 가격·보유·처리 상태를 각각 보여주고 애착 물건 카드에 별도 판매를 안내한다. 음소거 버튼은 무대 안 우상단에 두고 나무 우클릭 정지·걷기 안내는 무대 위에 표시한다.
- 캐릭터 7종의 애착 물건을 독립 비소모성 상품으로 분리했다. 투척물 탭과 캐릭터 상세가 같은 상품 상태를 사용한다. 모든 캐릭터에서 사용할 수 있다.
- 기본 투척물은 공통 말랑공이다. 캐릭터 미리보기에서 상대 캐릭터를 클릭하면 해당 애착 물건을 던진다. 별도 체험 버튼과 체험 배지는 제거했다. 서버 호출·장착 변경 없이 승인 효과음을 재생한다.
- 상품 카탈로그 24종을 공통 JSON으로 정의하고 macOS 두 타깃에 같은 자원을 포함한다. 기존 캐릭터 4종은 `_solo` 신규 SKU를 조회하며 기존 SKU도 복원·검증한다. StoreKit 설정과 서버 allowlist는 총 28개다.
- 기존 포함 물건은 부모 지급 출처에 연결한 별도 권리로 보전한다. 환불·회수·계정 연결 해제·지급 삭제는 해당 출처만 제거하고 독립 구매 권리는 유지한다. 전환 전 주문도 기존 구매 내용을 보존한다.
- DB 카탈로그에 관련 캐릭터·렌더링 ID를 추가하고 StoreKit 판매 ID와 논리 상품 ID를 분리했다. 원격 migration 적용 여부는 아래 시점별 기록과 별도로 확인한다.
- 승인된 수달·돼지·나무, 두쫀쿠 늘어남·왁뿌볼 파편, 왁뿌볼 A·돼지고기 촵 등 기존 승인 이미지·음원을 유지한다.

## 로컬 검증

- macOS 전체 테스트 **285개 실행, 284개 통과, 외부 연동 1개 제외, 실패 0개**. 추가 테스트에서 7종 독립 소유권·공통 기본 공·구매 카드 4가지 보유 상태·일회성 체험·동작 줄이기·종료 정리를 확인했다.
- 마지막 구매 카드 정렬·단독 상세창 높이 수정 후 관련 테스트 **21개 추가 통과**.
- 음원 해시 검증 fixture를 테스트 번들로 옮겨 Documents 접근 권한 없이 승인 음원을 확인한다.
- verifier 테스트 **7개 통과**. PGlite PostgreSQL에서 실제 migration과 주요 원본 제약을 실행했다. 기존 선물·지연 복원·전환 전/후 주문·독립 구매·환불·stale callback·잘못된 ID·권한 거부·최종 출처 삭제, 기본 공·소유 물건의 실제 Broadcast payload와 미소유 장착 거부를 검증했다. 전체 Supabase RLS/Realtime 통합 검증을 대신하지 않는다.
- App Store Release Archive 생성·서명·bundle ID·verifier URL·dSYM 일치·Sparkle 미포함 검사 통과.
- Sidey-dev의 승인 이미지 13개·음원 7개 해시와 코드 서명을 검증하고 로컬 검토 모드로 설치·실행했다. 로그인·프로필 데이터는 초기화하지 않았다.
- 검토 캡처 도구의 배경·SpriteKit 좌표 수정은 별도 개발 빌드로 확인했다. 이 Debug 도구는 App Store Release에 포함되지 않는다.

## 앱에서 확인

Xcode 프로젝트: `_workspace/direct-name-release/macos/SIDEY.xcodeproj`

- `SIDEYStoreReview` scheme → 실행: 로그인 없이 실제 상세 화면의 상품·보유 상태·가격 표시를 검토한다. 실제 결제는 진행하지 않는다.
- 설치된 `/Applications/Sidey-dev.app`도 `--store-review`로 실행 중이다.
- 실제 App Store 경로는 `SIDEYAppStore` scheme이다. 로컬 StoreKit 거래를 운영 계정 권리로 지급하지 않는다.
- `/Applications/SIDEYAppStore.app`에 있던 예전 설치본은 이번 결과물이 아니다. 수정 프로젝트 또는 아래 Archive를 사용한다.

## App Store Connect 및 배포 후속

1. [등록 안내](KEEPSAKE_APP_STORE_REGISTRATION.md)의 추가 11종(애착 물건 7 + 단품 캐릭터 4)을 등록한다. [CSV](keepsake-iap-products.csv)는 한국어 입력용이다.
2. 이전 신규 7종은 사용자가 초안 등록을 보고했다. 돼지의 올바른 ID `character_pig` 재등록 여부, 가격·지역·계약·현지화·심사 정보는 아직 원격 확인하지 않았다.
3. 기존 4개 SKU는 복원용으로 보존한다. 새 단품 출시 준비가 끝나기 전에 기존 SKU를 삭제하거나 판매를 중단하지 않는다.
4. 공통 migration과 verifier·Edge Function allowlist를 staging에 적용하고 Apple Sandbox 구매→서버 승인→장착→재실행/복원→환불, 계정 삭제·연결 해제·복수 지급을 실제 환경에서 검증한다. production 판매 잠금은 유지한다.
5. App Store의 실제 가격 조회와 심사 화면을 확인하고 업로드 이력에 맞는 build 번호를 확정한다. 최종 Apple Distribution export/validation을 수행한다. 현재 Archive는 Apple Development 서명이다.
6. Windows와 공개 웹의 카탈로그·안내 업데이트는 플랫폼별 후속 작업이다. 이번 macOS 분리 판매 서버 계약의 운영 전환은 구버전·다른 플랫폼 호환 검증 후 진행한다.

이하 01:51까지의 기록은 당시 로컬 검증 상태다. 이후 사용자가 build 27 업로드를 완료했고, 직배포 이름 변경·main 병합·macOS 릴리스를 승인했다. 심사 승인과 실제 구매 검증 완료를 뜻하지 않는다.

## 로컬 파일

- Archive: `/private/tmp/sidey-keepsakes-appstore/SIDEYAppStore.xcarchive`
- 전체 테스트 로그: `/private/tmp/sidey-keepsakes-tests.log`
- Archive 검증 로그: `/private/tmp/sidey-keepsakes-appstore-archive.log`
- 캡처와 등록 자료: `~/Downloads/SIDEY-store-refactor/`

[Apple 입력 항목 안내](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) · [Sandbox 테스트 개요](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox)

## 2026-09-12 01:32 실환경 재확인

- 직배포 전용 조건부 컴파일 때문에 App Store 프로필의 말풍선·투척물 선택이 파란색으로 남아 있었다. 양쪽 프로필이 공통 보라색 선택 스타일을 사용하고 상점 hover/focus·사용 중 표시도 같은 색을 사용하도록 수정했다.
- 프로필·상점 관련 테스트 36개 통과. App Store Debug 빌드·코드 서명·app-sandbox/network.client/Apple 로그인 entitlement를 확인했다. SIDEYAppStore scheme은 StoreKit 로컬 설정 파일을 지정하지 않으며 Debug 앱은 sandbox verifier URL을 사용한다.
- Debug·Release verifier의 /health는 모두 HTTP 200이다. 서버 생존 확인이며 새 상품 구매 검증 완료를 뜻하지 않는다.
- 실제 실행 로그: `Store catalog count mismatch: server 10, app 24`. 새 서버 카탈로그 미반영으로 상점 상태 조회가 실패한다. 소유권 검증을 우회하거나 누락 상품을 구매 가능으로 표시하지 않았다.
- 실제 StoreKit 조회는 24종 중 12종만 반환했다. 미조회 ID: character_chinchilla_solo, character_guinea_pig_solo, character_monkey_solo, character_starlight_upalupa_solo, character_tree, throwable_banana, throwable_clam, throwable_mini_paprika, throwable_pork, throwable_snowflake, throwable_starlight_orb, throwable_timber.
- 상품 등록 정보 전파 및 App Store Connect 가격·지역·계약 확인, 서버 migration/verifier 반영, Sandbox 신규 구매·복원 검증이 필요하다. 이번 재확인에서 원격 배포·구매·심사 제출·업로드는 실행하지 않았다.

## 2026-09-12 01:51 가격 미조회 재확인

- 새 실행에서 이전 server 10/app 24 카탈로그 불일치 로그는 관찰되지 않았다. 사용자는 앞서 Cloud Run Sandbox revision 00006-8w9 배포 성공을 보고했다.
- 실제 Apple 상품 조회는 24개 중 15개이며 미조회 9개는 character_chinchilla_solo, character_guinea_pig_solo, character_monkey_solo, character_starlight_upalupa_solo, character_tree, throwable_banana, throwable_clam, throwable_pork, throwable_snowflake다.
- App Store 가격이 없을 때 서버의 직배포 가격을 대신 표시하던 목록을 수정했다. 조회 중·조회 불가·실패를 구분하고 상세의 가격 다시 확인과 상점 재진입/상태 갱신에서 Apple 가격을 다시 조회한다. 미조회 상품의 구매 차단과 보유 권리 유지 정책은 유지한다.
- 가격 일부 누락·실패·재조회 복구·직배포 표시를 포함한 상점 관련 테스트 45개 통과. 수정된 App Store Debug 빌드를 실행해 실제 재조회 로그를 확인했다. Apple에서 아직 반환하지 않는 상품의 등록/가격/판매 지역/전파 상태 확인과 Sandbox 신규 구매·복원 실검증은 남아 있다.

## 2026-09-12 배포 이름 및 build 28

- 직배포 Release의 CFBundleDisplayName·CFBundleName과 실행 메뉴·창 제목은 `SIDEY-DIRECT`, App Store판은 `SIDEY`, 개발판은 `Sidey-dev`다.
- 직배포 내부 `SIDEY.app`·실행 파일·bundle ID·로그인 helper ID·Keychain·설정·Sparkle feed는 유지해 기존 설치를 교체한다.
- 사용자가 신규 18종의 제출 준비 중 화면과 build 27 업로드 완료를 확인했다. 새 build 28 Archive는 다시 업로드할 수 있는 별도 빌드이며 이 문서만으로 업로드·심사 제출 완료를 주장하지 않는다.

## build 28 검증 결과

- 전체 macOS 테스트 288개 실행: 287개 통과·외부 연동 1개 제외 후, 제외했던 실제 로컬 2클라이언트 통합 테스트도 별도로 통과했다.
- 별도 로컬 Supabase의 전체 pgTAP 266개와 5개 방·12명·초대 제한 동시성 검증이 통과했다. 상품 verifier 테스트 7개, 웹사이트 47페이지 빌드도 통과했다.
- 운영 Supabase migration 이력을 읽기 전용으로 조회해 신규 3개(20260911000000·20260912000000·20260912010000)의 적용을 확인했다.
- App Store build 28 Archive 생성과 dSYM·서명·bundle ID·verifier URL·Sparkle 미포함 검증이 통과했다. CFBundleDisplayName과 CFBundleName은 모두 SIDEY다.
- 최신 Archive: `/private/tmp/sidey-release28-appstore/SIDEYAppStore.xcarchive`. 기존 build 27 Archive와 구분한다.
- 직배포 build 28은 Developer ID 서명·Apple 공증·staple를 통과했고 실행 표시 이름과 bundle name을 SIDEY-DIRECT로 확인했다.
- 사용자가 보고한 build 27 업로드 이후 build 28의 Connect 업로드·심사 제출과 실제 신규 Sandbox 구매/복원은 이 검증에서 실행하지 않았다. 운영 App Store verifier 신규 allowlist 배포 완료도 아직 확인하지 않았다.

## 2026-09-12 나무 대체 상품 조회 후보

- 나무 현재 Apple 상품 ID를 `character_tree_2`로 변경하고 기존 `character_tree`는 복원 ID로 유지한다. 내부 상품·권리·가격(한국 2,200원)과 다른 상품은 그대로다.
- Connect에 비소모품 `character_tree_2`를 등록하고 한국 가격·판매 지역·한국어 이름/설명을 설정한 뒤 실제 Apple 조회를 검증해야 한다. 로컬 StoreKit 파일은 원격 등록을 대신하지 않는다.
- 서버에는 `20260912020000_tree_app_store_offer.sql` migration과 verifier allowlist 변경이 필요하다. 원격 적용·신규 상품 등록·실제 거래·업로드는 이 소스 변경에서 완료된 것으로 간주하지 않는다.
- 기존 build 27/28은 새 ID를 요청하지 않는다. 이번 로컬 검증은 버전 번호를 소비하지 않으며 향후 업로드 전에 양쪽 배포의 최대 사용 build를 다시 확인해 새 번호를 배정한다.
- 로컬 검증: verifier 테스트 7개 통과(실제 SQL migration 재적용, 구·신 나무 거래·환불·복원 포함), App Store Debug 컴파일 성공(`CODE_SIGNING_ALLOWED=NO`), Swift 상품/복원 매핑 XCTest 1개 통과. 빌드된 앱의 나무 ID가 `character_tree_2`이고 기존 ID가 복원 목록에 포함된 것을 검사했다. 실제 Apple 조회나 서명·업로드 검증을 대신하지 않는다.

## 2026-09-12 원숭이·조개·돼지고기 재등록 후보

- 사용자가 나무 `character_tree_2`의 한국 가격 2,200원 표시를 확인했다. 나무의 실구매·복원 성공을 뜻하지 않는다.
- 새 판매 ID는 `character_monkey_solo_2`, `throwable_clam_2`, `throwable_pork_2`다. 돼지 캐릭터 `character_pig`는 그대로다. 24개 상품과 과거 ID를 포함한 32개 Apple ID를 매핑한다.
- 원격 적용이 필요한 추가 migration은 `20260912030000_remaining_app_store_offers.sql`이며 나무의 `20260912020000_tree_app_store_offer.sql`도 선행해야 한다. verifier도 같은 커밋의 allowlist를 배포해야 한다.
- 신규 상품 등록·가격·지역·현지화와 실제 조회/구매/복원은 별도 검증 대상이다. 등록 값은 [재등록 입력표](REPLACEMENT_APP_STORE_REGISTRATION.md)를 따른다.
- 로컬 검증: verifier 테스트 7개, Swift 상품/복원 매핑 테스트 1개 통과. App Store Debug 빌드 성공. 빌드된 앱의 나무·원숭이·조개·돼지고기 현재 ID와 총 32개 StoreKit ID/가격 일치를 확인했다. 원격 DB·Cloud Run 반영과 Connect 업로드는 이번 변경에서 실행하지 않았다.

## 2026-09-12 원숭이만 재등록 비교

- 현재 원숭이 ID는 `character_monkey_solo_3`, 한국 가격은 1,100원이다. `_solo_2`·`_solo`·`character_monkey`는 거래 복원용으로 보존한다. 조개·돼지고기는 `_2`, 나무는 `character_tree_2`를 유지한다. 판매 상품 24종, Apple 검증 ID 33개다.
- 이번 변경은 기존 `macos/tree-store-id`의 로컬 후보이며 Connect 신규 상품 생성·가격 조회 성공이나 서버 배포 완료를 뜻하지 않는다. 로컬 컴파일만으로 공개 버전/build를 올리지 않는다.

## 2026-09-12 원숭이 기존 단품 2 재연결

- 원숭이 현재 판매 ID를 `character_monkey_solo_2`로 되돌려 조회한다. `_solo_3`도 과거 거래 검증용으로 유지한다. 다른 상품 ID와 버전·build는 유지한다.
- 신규 DB migration `20260912123000_restore_monkey_second_app_store_offer.sql`로 서버 현재 판매 ID도 일치시킬 수 있다. 이번 작업은 로컬 변경이며 원격 배포·Connect 업로드·실제 가격 조회 성공을 뜻하지 않는다.

## 2026-09-12 원숭이 단품 4 비교

- 현재 원숭이 ID는 `character_monkey_solo_4`이며 앞선 `_solo_2` 재연결 후보를 대체한다. 기존 원숭이 ID는 모두 거래 검증용으로 보존한다. 판매 상품 24종·Apple 검증 ID 34개다. 다른 상품과 버전·build는 유지한다.
- 로컬 후보이며 Connect 신규 상품 등록, migration `20260912130000_monkey_fourth_app_store_offer.sql` 및 verifier의 원격 배포, 실제 가격 조회는 별도 확인한다.

## 2026-09-12 최신 main 통합 및 App Store build 30

- 사용자가 실행 중인 Xcode 앱과 번들에서 원숭이 `character_monkey_solo_4`를 확인했다. 제공한 로그는 `StoreKit returned 24 products; unavailable IDs:`이며 미조회 ID가 없어 24종 조회 완료 근거로 기록한다. 실제 구매·복원 성공을 뜻하지 않는다.
- App Store판만 1.2.1 build 30으로 준비하며 직배포 1.2.1 build 29와 공개 appcast는 유지한다. 판매 ID 24개·복원 포함 검증 ID 34개를 사용한다.
- Cloud Run verifier는 최신 main의 코드를 Sandbox·Production에 각각 배포해야 한다. 원숭이 `_4`를 포함한 DB migration은 사용자 적용 완료 보고와 실제 서버 확인을 구분한다. 이번 준비는 Connect 업로드 또는 심사 제출 완료를 뜻하지 않는다.

## 2026-09-12 업로드 오류 91109 수정

- build 30은 업로드 전송 후 Apple 처리 단계에서 `pixel_hamster.png`의 `com.apple.quarantine` 속성으로 실패했다. 업로드 아카이브에서 해당 속성 1건과 원본 이미지의 동일 SHA-256을 확인했다.
- App Store 타깃은 리소스 복사 뒤 코드 서명 전에 리소스 격리 속성만 제거한다. CLI archive 검사도 전체 앱에 격리 속성이 남으면 실패한다. 일반 Xcode Archive에도 제거 단계가 적용된다.
- 재업로드 후보는 같은 기능의 1.2.1 build 31이며 직배포 build 29는 유지한다. Apple 처리 성공·심사 제출은 새 업로드 후 별도 확인한다.
