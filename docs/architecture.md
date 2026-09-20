# SIDEY 아키텍처

이 문서는 SIDEY 저장소와 실행 시스템의 현재 책임 경계를 설명한다. 제품 동작은
[`product/`](product/overview.md), 선택 이유는 [`decisions/`](decisions/README.md),
반복 가능한 릴리스 절차는 [`operations/`](operations/release.md)에서 다룬다.

## 시스템 구성

- macOS 클라이언트는 SwiftUI·AppKit·SpriteKit으로 만든 Mac App Store 네이티브 앱이다.
  Sign in with Apple, 전용 Keychain, sandbox와 StoreKit 경계를 유지한다. 직접 배포판의
  개발·지원은 종료하며 과거 계정·구매 원본을 자동 병합하거나 삭제하지 않는다.
- Windows 클라이언트는 C#/.NET·WinUI 3·Win32로 만든 네이티브 앱이다. 일반 UI와
  투명 overlay surface를 분리하고, Core·Presentation·Infrastructure·Overlay·Platform
  계층의 의존 방향은 [Windows 아키텍처 문서](../windows/docs/architecture.md)가 설명한다.
- 공개 웹사이트는 제품·다운로드·정책·상점 정보를 제공하는 Astro 정적 사이트다.
  메시징 웹 클라이언트가 아니다.
- 이 공개 저장소는 네이티브 클라이언트, 공개 웹, client-facing contract, 승인된
  asset 원본과 commerce catalog를 소유한다.
- Supabase schema·migration·RLS·Edge Functions, App Store 거래 검증, 서버 운영 도구는
  비공개 [`sidey-app/sidey-backend`](https://github.com/sidey-app/sidey-backend)가
  소유한다. 공개/비공개 저장소의 작업 경계와 catalog handoff는
  [`BACKEND.md`](BACKEND.md)를 따른다.
- 독립 로컬 운영 도구는 `sidey-admin` 저장소가 소유하고, 그 도구가 사용하는 서버
  조회·집계 계약은 backend 저장소가 소유한다.

## 소스 코드와 콘텐츠 권리

이 저장소의 SIDEY 소스 코드는 [GNU AGPLv3](../LICENSE)의 version 3 only 조건을
따른다. 적용 범위, 제3자 구성요소, 브랜드와 비공개 저장소의 경계는
[라이선스 안내](../LICENSING.md)가 설명한다. 유료 에셋의 기존 이용 조건은 코드
라이선스와 별개이며, 외부 에셋 기여는 받지 않는다. 기존 승인 에셋의 유지보수와
플랫폼 mirror 갱신은 계속 저장소의 검증·배포 절차를 따른다.

## 데이터와 실시간 경계

Postgres가 영구 메시지와 계정·방 상태의 원본이다. Presence는 연결 및 활동 상태,
Broadcast는 SIDEY 입력창의 typing과 캐릭터 상호작용 같은 일시 이벤트에만 사용한다.
클라이언트는 서버가 확인한 membership, rate limit, entitlement 및 equipped state를
표현하며 이를 로컬 상태만으로 부여하지 않는다.

클라이언트와 공개 웹에 필요한 계약만 이 저장소에 둔다. 비공개 schema, secret,
운영 데이터 또는 backend 배포 절차를 공개 문서에 복제하지 않는다.

## 콘텐츠와 commerce 흐름

승인된 asset 구조와 플랫폼 지원 범위는
[`assets/v1/manifest.json`](../assets/v1/manifest.json), 판매 상품 metadata와 플랫폼
식별자는 [`assets/v1/commerce-catalog.json`](../assets/v1/commerce-catalog.json)이
소유한다. 생성 스크립트가 이 원본에서 웹과 네이티브 mirror를 만들고 검증한다.
backend가 상품 변경을 필요로 하면 검토된 공개 commit의 snapshot과 provenance를
별도로 받아 서버용 매핑을 생성한다. 공개 catalog 변경만으로 backend가 배포되지는
않는다.

## 배포 산출물

Mac App Store target version/build는 [`release/macos.json`](../release/macos.json)과
[`macos/SIDEY.xcodeproj/project.pbxproj`](../macos/SIDEY.xcodeproj/project.pbxproj)가
일치해야 한다. 이 계약은 App Store 게시 완료를 증명하지 않으며, 웹 다운로드는
App Store 제품 페이지로 연결한다.

Windows 공개 version은 [`release/windows.json`](../release/windows.json)이 소유한다.
네이티브 project 설정, Windows update manifest와 웹 download metadata는 검증되는
mirror다. 과거 macOS 직접 배포 release와 feed는 기록으로 보존하고 새로 갱신하지 않는다.

## 권위 순서

1. source code, project settings, manifest와 catalog 같은 machine-readable source
2. 현재 제품 및 아키텍처 문서
3. 장기 decision 문서의 선택 이유
4. 일반 구현 이력을 보존하는 Git commit과 pull request

Decision 문서는 현재 구현이나 현재 제품 명세를 덮어쓰지 않는다. 서로 충돌하면
machine-readable source를 먼저 확인하고 현재 문서를 고친다.
