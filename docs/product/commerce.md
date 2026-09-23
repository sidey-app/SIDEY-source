# Commerce

## 권위 있는 데이터

현재 상품명, 가격, 내부·판매·복원 ID, 정렬과 asset 연결은
[`assets/v1/commerce-catalog.json`](../../assets/v1/commerce-catalog.json)이 소유한다.
상품별 한국어·영어·일본어·번체 중국어 표시명과 App Store 설명, 앱·웹 상세 설명은
[`assets/v1/commerce-localizations.json`](../../assets/v1/commerce-localizations.json)이
소유한다. 기존 catalog의 한국어 이름과 설명은 호환용 mirror이며 localization source와
일치해야 한다. 과거 Apple product ID는 restore mapping으로만 유지하고 신규 판매
metadata 대상으로 다시 만들지 않는다.
이 문서는 그 값을 표로 복제하지 않는다. Asset 형식과 플랫폼 지원 범위는
[`assets/v1/manifest.json`](../../assets/v1/manifest.json)이 소유한다. 공개 웹과
네이티브 bundle의 catalog는 이 두 source에서 생성되고 일치 여부를 검사한다.

## 소유권과 장착

Entitlement는 account가 상품을 사용할 수 있는 권리이고 equipped state는 현재
보여 줄 선택이다. 둘은 별도다. 서버는 활성 entitlement를 확인한 뒤 장착을 승인한다.
캐릭터와 관련 애착 물건도 독립 상품이며, 현재 단품 캐릭터를 보유했다는 이유만으로
물건 권리를 추론하지 않는다. 과거 포함 구매나 complimentary grant는 지급 source별로
보존하므로 한 source의 refund가 다른 유효한 권리까지 회수하지 않는다.

구매가 승인된 새 cosmetic은 해당 종류에 장착할 수 있다. 시작 재검증과 restore는
소유권을 동기화하되 사용자의 현재 equipped state를 덮어쓰지 않는다. 기본 말풍선과
기본 투척물은 구매 없이 사용할 수 있다.

## 서버와 플랫폼 책임

클라이언트 redirect나 local receipt만으로 entitlement를 부여하지 않는다. Backend가
결제 provider 또는 Apple transaction을 검증하고 account snapshot에 반영한 뒤 client가
사용한다. Catalog 응답이 client보다 적은 정상적인 부분 응답이면 등록되지 않은 상품만
구매 불가로 처리하고 기존 entitlement나 장착을 회수하지 않는다. 알려진 상품의 중복
ID 또는 metadata 불일치는 오류다.

- Mac App Store판은 StoreKit의 비소모성 상품과 Apple이 반환한 localized price를
  사용한다. StoreKit이 반환한 상품명·설명·localized price를 논리 상품 ID에 매핑하고,
  상품명과 설명을 받지 못한 경우에는 bundle localization을 표시할 수 있지만 해당
  상품의 구매는 막는다. Apple에서 가격을 받지 못하면 다른 채널의 가격을 대신 표시하지
  않는다. Backend catalog는 권리와 판매 상태만 갱신하며 사용자에게 보이는 현지화 문구를
  덮어쓰지 않는다.
- macOS 직접 배포판의 신규 개발·배포는 종료한다. 기존 구매 원본과 지급 권리는
  보존하며, App Store 전환을 이유로 기존 entitlement를 회수하지 않는다.
- Windows는 고정된 운영 backend에서 production checkout을 지원한다. 개발 전용 staging
  구매 흐름은 별도의 build 지원과 명시적인 opt-in이 모두 필요하다. 판매 가능 여부는
  서버 상태와 상품별 구매 조건으로 확인하며, 상점이 활성화되면 일괄적인 구매 준비 중
  안내 대신 소유 여부와 실제 구매·처리 상태를 표시한다. 주문과 구매 권한은 Google이
  연결된 SIDEY 사용자 UUID에 저장한다. Google 이메일을 소유권 키로 사용하지 않으며
  기존 익명 UUID에 Google을 연결해도 구매 ledger는 유지된다.
- 공개 웹은 catalog를 소개하지만 entitlement를 직접 발급하지 않는다.
  결제·결제 결과 페이지는 고정된 SIDEY 운영 결제 API만 호출하며 URL로 전달된
  API 주소는 사용하지 않는다. 실제 구매 가능 여부와 결제 승인은 서버가 확인한다.
  직접 결제는 서버가 지정한 채널의 카드 결제창을 사용한다. 별도 계약이 확인되지
  않은 간편결제사를 임의로 선택해 호출하지 않는다.
  결제창 호출 실패와 서버의 승인 확인 실패는 구분하여 안내하며, 승인
  확인이 끝나지 않은 요청은 같은 페이지에서 중복 실행하지 않는다.

Account 삭제는 자동 환불이 아니다. 환불·회수·복원은 원래 payment source와 서버
ledger를 기준으로 처리한다. 실제 settlement와 회계는 payment provider의 보고서를
기준으로 한다.
