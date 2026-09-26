# macOS 다국어와 App Store storefront 계약

- Status: Accepted
- Decided: 2026-09-21 (Asia/Seoul)

## Context

macOS 앱과 공개 웹은 한국어 중심으로 만들어졌고 상품 이름과 설명도 commerce catalog의
한국어 필드에 묶여 있었다. 영어·일본어·번체 중국어 사용자가 가입부터 구매·복원·탈퇴까지
일관된 언어로 이용하려면 앱 문자열, 상품 metadata, 공개 정책과 App Store listing이 같은
source와 release 경계를 가져야 한다.

App Store가 반환하는 상품 metadata와 가격, bundle fallback, backend의 entitlement 상태를
한 모델에서 구분하지 않으면 서버의 한국어 문구가 StoreKit 결과를 덮거나 상품 조회 실패
상태에서도 구매가 열릴 수 있다. Storefront 확대 과정에서 기존 국가를 실수로 제거하는
위험도 별도 제어가 필요하다.

## Decision

macOS 앱은 `ko`, `en`, `ja`, `zh-Hant`를 제공하고 시스템의 앱 언어를 따른다. 미지원
언어 fallback은 영어이며 앱 내부 언어 선택기는 만들지 않는다. 번체 중국어는 대만식
표현을 기준으로 하되 홍콩·마카오에서도 이해할 수 있는 중립 표현을 사용한다.

UI는 semantic localization key를 사용하고 날짜·수량·기간·가격은 locale-aware format을
사용한다. 닉네임, 그룹명과 메시지 본문은 번역하지 않는다. 알려진 서버 오류 code는 bundle
문구로 바꾸며 알 수 없는 원격 문장은 사용자에게 그대로 보여 주지 않고 redacted 진단에만
남긴다.

Commerce identity, 가격, entitlement와 정렬은 기존
`assets/v1/commerce-catalog.json`을 유지한다. 네 언어의 상품 표시명, App Store IAP 설명과
상세 설명은 별도 `assets/v1/locale/commerce/{locale}.json`을 원본으로 두고 앱, 웹, local
StoreKit과 App Store Connect 입력을 생성한다. StoreKit metadata를 우선하며 조회하지 못한
상품은 bundle 번역을 표시하더라도 구매할 수 없다. Backend는 entitlement와 판매 상태만
갱신하고 현지화 문구를 소유하지 않는다.

App Store primary language는 한국어로 유지한다. 기존 storefront availability는 줄이지
않고 승인된 시장의 누락만 보완한다. App Store Connect 도구는 기본 read-only diff이며
명시적인 apply와 별도 release 승인이 모두 있을 때만 원격 상태를 바꾼다. 중국 본토와 EU
확장은 각각 규제·결제 감사와 DSA 준비를 마친 별도 결정으로 다룬다.

## Consequences

- 앱, 웹, 상품과 store listing의 네 언어 완전성을 deterministic validator로 검사한다.
- 번역 초안과 독립 검수는 분리해 기록하되 사람 원어민 또는 법률 검수를 받았다고 주장하지
  않는다.
- 영어나 CJK 문자열 길이, VoiceOver, IME와 실제 StoreKit 가격은 source test만으로 완전히
  증명할 수 없으므로 release candidate의 runtime 및 Sandbox 검증이 계속 필요하다.
- Metadata 동기화 구현은 upload, review submission, publication 또는 backend deployment를
  승인하지 않는다.
