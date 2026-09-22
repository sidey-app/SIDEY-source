# macOS Firebase v2 contract change request

상태: **client contract 및 production read-back 반영 완료**
기준일: 2026-09-22

## 해결된 항목

- App Store Firebase app 등록
  - bundle ID: `app.sidey.desktop.appstore`
  - Firebase app ID: `1:985965733256:ios:62d9e218a8171e54b4063d`
  - project ID: `sidey-realtime`
- active RTDB URL `https://sidey.asia-southeast1.firebasedatabase.app` 고정
- bootstrap `minimumAccessRevision`, 응답 `accessRevision`/`wireItems`, epoch-ms
  `refreshAfter`/`rolloutLeaseExpiresAt`
- Firebase Auth SDK refresh ownership과 `sideySessionId` claim 검증
- pulse/throw 최초 snapshot baseline, per-slot high-water, 5초 freshness
- `get_store_state_v2.wireCode`, built-in code `0`, unknown code drop
- callable chat non-commit/ambiguous 오류 분류
- inbox access/room revision과 chat sequence hint semantics
- create/join/equip v2 RPC와 post-commit revision RPC

위 항목과 rollout selector를 포함한 frozen fixture SHA-256은
`3c836b40cfc44437e9d069b84787cd3d8793026ce40de46d82b9ece79127b7e5`다.

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
- contract hash: `3c836b40cfc44437e9d069b84787cd3d8793026ce40de46d82b9ece79127b7e5`
- App Store app version은 marketing/build를 합친 `1.3.0+32` 형식
- explicit disabled/kill-switch만 legacy 허용; prior enabled에서 fetch/cache 실패는 fail-closed
- 최대 300초 rollout lease, 30초 refresh lead와 실행 중 sync-before-commit legacy 전환
- server-only Firebase 전역 emergency gate는 남은 lease와 무관하게 RTDB read/callable write를 즉시 차단
- App Store 환경 변수와 bundled `SIDEYRealtimeTransport`는 선택권 없음

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
