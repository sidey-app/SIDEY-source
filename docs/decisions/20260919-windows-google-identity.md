# Windows 계정을 Google 로그인으로 통일

- Status: Accepted
- Decided: 2026-09-19

## 결정

Windows는 Google 로그인을 필수로 하고 익명 사용을 종료한다. 기존 익명 사용자는
저장된 Supabase session을 복구한 뒤 같은 auth 사용자 UUID에 Google identity를
연결한다. 기존 방·메시지·구매 권한을 새 UUID로 복사하거나 자동 병합하지 않는다.
저장된 session이 없는 설치는 일반 Google 로그인으로 가입하거나 기존 계정을 복구한다.

## 이유와 경계

설치에만 묶인 익명 계정으로는 재설치와 다른 PC에서 방과 구매 권한을 복구하기 어렵다.
Google을 로그인 수단으로 사용하면서 Supabase 사용자 UUID를 방·메시지·결제의 소유권
기준으로 유지한다. 연결 실패나 취소를 새 계정 생성이나 기존 데이터 삭제로 처리하지 않는다.

Windows 전환은 Mac App Store의 Apple 로그인 경계나 플랫폼 간 계정 병합 정책을
바꾸지 않는다. 구현·운영 계약은 [계정과 그룹](../product/identity-and-groups.md),
[commerce](../product/commerce.md)를 따른다.
