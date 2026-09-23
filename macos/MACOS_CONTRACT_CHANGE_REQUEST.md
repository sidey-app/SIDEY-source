# macOS Firebase v2 contract change request

상태: **client candidate 반영 완료 — backend production 배포/read-back 대기**
기준일: 2026-09-23

## 해결된 항목

- App Store Firebase app 등록
  - bundle ID: `app.sidey.desktop.appstore`
  - Firebase app ID: `1:985965733256:ios:62d9e218a8171e54b4063d`
  - project ID: `sidey-realtime`
- active RTDB URL `https://sidey.asia-southeast1.firebasedatabase.app` 고정
- bootstrap `minimumAccessRevision`, 응답 `accessRevision`/`wireItems`, epoch-ms
  `refreshAfter`/`rolloutLeaseExpiresAt`
- Firebase Auth SDK refresh ownership과 `sideySessionId` claim 검증
- Firebase v2 선택 시 typing/pulse/throw를 compact RTDB `t/c/x`에 단일 발행·수신
- Supabase transient는 구버전 호환 bridge가 처리하며 Firebase v2 client는 중복 소비하지 않음
- Presence와 authoritative reconciliation은 계속 Supabase 사용
- pulse/throw 최초 snapshot baseline, per-slot high-water, 5초 freshness
- `get_store_state_v2.wireCode`, built-in code `0`, unknown code drop
- callable chat non-commit/ambiguous 오류 분류
- inbox access/room revision과 chat sequence hint semantics
- create/join/equip v2 RPC와 post-commit revision RPC

위 항목과 rollout selector를 포함한 frozen fixture SHA-256은
`0f2845d033df248b1745c6526c8c7100b8d8fa6839b45f28c73b1023053fce2e`다.

## production 합의/증거

### 1. 최종 client handoff

Supabase production M0 적용과 remote read-back 뒤 다음을 포함한 `CLIENT_BACKEND_HANDOFF.md`가 필요하다.

- production migration version/적용 시각
- deployed Firebase source revision과 Functions generation
- Rules canonical hash
- frozen fixture SHA-256
- production wire-code read-back
- production Presence/RLS/RPC signature read-back
- T0 미시작 또는 정확한 T0 시각

backend의 최종 `CLIENT_BACKEND_HANDOFF.md`와 production read-back을 연결 승인 근거로 사용한다.

### 2. remote rollout/kill switch — 해결

- authenticated RPC: `register_realtime_capability_v2(p_platform, p_app_version, p_protocol_version, p_contract_hash)`
- exact response: `enabled`, `protocolVersion`, `transport`, `contractHash`, `killSwitch`, `cacheTtlSeconds`, `failureMode`
- candidate contract hash: `0f2845d033df248b1745c6526c8c7100b8d8fa6839b45f28c73b1023053fce2e`
- App Store app version은 `release/version.json`에서 생성한 marketing/build를 합친 형식
- explicit disabled/kill-switch만 legacy 허용; prior enabled에서 fetch/cache 실패는 fail-closed
- 최대 300초 rollout lease, 30초 refresh lead와 실행 중 sync-before-commit legacy 전환
- server-only Firebase 전역 emergency gate는 남은 lease와 무관하게 RTDB read/callable write를 즉시 차단
- App Store 환경 변수와 bundled `SIDEYRealtimeTransport`는 선택권 없음

현재 production rollout은 fail-closed OFF 상태다. production 전환은 이 상태에서
migration/Functions/Rules 배포, read-back, 새 hash 활성화 순서로 진행해야 한다.

### 3. production promotion 조건

1. production-shaped migration rehearsal와 online backfill 검증
2. production M0 적용 및 read-back
3. changed Firebase Functions staging/production 배포와 read-back
4. old client + v2 backend smoke 및 cleanup residual 0
5. macOS/Windows가 같은 frozen fixture hash로 contract test 통과
6. internal account smoke와 revocation/kick/refund/session A-B 검증
7. canary rollback drill

macOS에는 hardcoded `firebaseV2Allowed`가 없다. 위 RPC가 exact protocol/hash로 enabled를 반환한 인증 세션만
Firebase v2를 선택한다.
