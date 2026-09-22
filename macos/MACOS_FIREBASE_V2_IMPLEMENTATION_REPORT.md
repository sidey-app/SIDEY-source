# macOS Firebase v2 구현 보고서

상태: **production selector/factory 연결 완료 — Xcode 검증 후보**  
기준일: 2026-09-22

## 기준과 배포 상태

- source branch: `macos/firebase-v2-client`
- source integration anchor: 최종 backend contract 고정 후 최신 `main`에 workflow로 동기화 예정
- Gate 1 deployed fixture SHA-256:
  `4785705721e971ae463a5692bc80cadc7ff49ed0e20aab495dc1b0d6be0619d0`
- frozen client/backend fixture SHA-256:
  `3c836b40cfc44437e9d069b84787cd3d8793026ce40de46d82b9ece79127b7e5`
- Firebase Gate 1: production Functions/Rules 배포 및 read-back 완료
- Supabase production selector: authenticated `register_realtime_capability_v2`
- macOS feature gate: server cohort/kill-switch 응답과 frozen contract hash로 결정
- commit/push/merge/sign/notarize/App Store upload/release: 이 보고서 snapshot에서는 수행하지 않음

클라이언트가 요구하는 frozen contract hash는
`3c836b40cfc44437e9d069b84787cd3d8793026ce40de46d82b9ece79127b7e5`이며, selector 등록 시 protocol 2와 함께
서버에 제출한다. App Store 업로드와 release는 이 소스 변경과 별도 작업이다.

## M1 현재 동작 inventory

| 동작 | 현재 ownership | 대표 검증 |
| --- | --- | --- |
| Supabase Auth/session | `SideyBackend.swift`, Keychain-backed Supabase storage | `KeychainStoreTests`, `BackendIntegrationTests` |
| legacy room realtime | `SideyBackend.swift`의 room channel pair와 recovery generation | `BackendEventLifecycleTests`, `BackendIntegrationTests` |
| Presence/UI | `SideyBackend.swift`, `PresencePublicationQueue`, `AppModel` | `PresenceAndRealtimeTests` |
| typing | `TypingActivityController.swift` | `TypingActivityTests` |
| pulse/throw | `AppCoordinator+Backend.swift`, `SideyBackend.swift` | `PixelWorldTests`, `CharacterStunTests` |
| chat outbox | `AppCoordinator+Backend.swift`, `MessageLedger` | `MessageLedgerTests`, `HistoryInteractionTests` |
| room switch | `RoomSwitchPipeline`, `AppPreferences` | `RoomManagementTests`, `PresenceAndRealtimeTests` |
| commerce/equip | `AppCoordinator+Commerce.swift`, `SideyBackend.swift` | `CommerceModelTests`, `StoreCatalogCompatibilityTests` |

sleep/wake 전용 통합 검증과 Firebase production 계정 smoke는 아직 없으므로 완료로 간주하지 않는다.

## 구현 완료 범위

### M2 — dual transport 경계

- protocol-neutral `RoomMessagingTransport`와 실행 중 kill-switch 전환이 가능한 mutable router를 추가했다.
- 선택된 adapter 하나만 생성·publish하며 permission failure를 legacy로 재전송하지 않는다.
- factory 자체가 던진 초기화 오류를 `try?`로 숨기지 않고 startup error로 노출한다.
- chat 결과를 `confirmed`, `definitelyRejected`, `reconciliationPending`으로 분리했다.
- commit 여부가 모호하면 동일 UUID outbox를 pending으로 유지하고 자동 재전송하지 않는다.

### M3 — bootstrap/Auth 계약

- canonical `bootstrapRealtime` POST endpoint, Supabase Bearer token, exact request/response DTO와 HTTP 오류 분류를
  구현했다.
- `accessRevision`, room UUID, wire code와 exact 11-key 응답을 strict decode한다. `refreshAfter`와
  `rolloutLeaseExpiresAt`은 epoch milliseconds이며 최대 5분 lease, 30초 refresh lead와 HTTP `Date`
  기준 clock-skew 보정을 검증한 뒤 monotonic deadline으로 고정한다.
- Supabase JWT의 `sub`/`session_id`를 현재 계정과 대조하는 redacted bootstrap session decoder를 추가했다.
- Firebase custom-token 교환 뒤 Firebase UID와 `sideySessionId` claim을 모두 검사한다.
- Firebase ID token 변경 listener를 유지하고 SDK refresh 뒤마다 동일 claim을 다시 검사한다. mismatch나
  예상 밖 sign-out은 Firebase credential을 제거하고 상위 lifecycle 폐기 callback으로 전달한다.
- claim mismatch 시 Firebase Auth를 즉시 sign-out한다. Firebase ID/refresh token은 SDK가 소유하고 SIDEY
  Keychain에 복제하지 않는다.
- account/session/generation lifecycle state machine으로 logout과 동일 UID A/B session의 늦은 completion을
  차단한다.
- Firebase ID token의 `sideyRolloutUntil` claim이 bootstrap lease와 정확히 일치하고 아직 유효한지
  검사한다. Claim 누락·형식 오류·불일치·만료는 모두 fail-closed다.

### M4 — RTDB listener/state

- canonical path builder와 실제 Firebase `.value` stream adapter를 구현했다.
- 정상 resource plan은 inbox `/v2/n/{uid}` 한 개와 active live `/v2/l/{roomId}` 한 개만 허용한다.
- account/session/generation이 바뀌거나 rollout lease가 갱신되면 inbox/live listener를 새 generation으로
  모두 교체하고 이전 generation callback을 폐기한다.
- inbox `a`, room `v`, chat `n`을 strict typed hint로 파싱하고 최초 snapshot은 baseline으로만 저장한다.
- revision 증가, chat sequence 증가와 gap을 구분하며 duplicate/reordered hint는 무시한다.
- live typing connection-slot timestamp를 보존하고, 6초 수신 TTL이 지나면 removal snapshot이 없어도
  orphan typing을 stop한다. pulse/throw/chat 최초 persistent snapshot은 재생하지 않는다.
- pulse/throw는 slot별 high-water보다 새롭고 수신 시점 기준 5초 이내인 값만 action으로 만든다.
- JavaScript safe integer를 넘는 sequence/timestamp와 잘못된 20자리 revision을 거부한다.

### M5 — Presence 상태기

- `(roomId, realtimeEpoch, snapshotRevision, memberSet)` generation을 구현했다.
- 모든 member target topic의 첫 sync와 self-track 성공 뒤에만 commit한다.
- empty first sync는 offline으로 처리하며 stale callback, member purge, epoch rotation, deadline fail-close를
  검증한다.

현재 released `SideyBackend` channel 구조를 새 Presence topic-set으로 바꾸는 live I/O 연결은 하지 않았다.
호환 기간의 composite는 기존 `SideyBackend` socket과 transient stream을 재사용해야 하며, 별도 legacy
channel 인스턴스를 하나 더 만들면 같은 이벤트가 중복 수신되므로 금지한다.

### M6 — typing/pulse/throw

- Firebase Database write adapter와 exact compact path/payload를 구현했다.
- typing stop은 현재 Supabase session slot 하나만 delete한다.
- active room이 아니면 write하지 않는다.
- throw는 `catalogItemID -> wireCode` mapping과 bootstrap authorized wire set을 모두 만족해야 한다.
- transient write는 한 번만 실행하며 모호한 응답을 자동 재시도하지 않는다.
- 다만 혼합 버전 호환 기간의 composite 송신 경로는 RTDB를 직접 쓰지 않는다. 기존 `SideyBackend`의
  membership·room epoch 검증 Supabase RPC와 Broadcast를 transient 송수신의 단일 plane으로 사용한다.
  호환 기간에는 typing·pulse·throw를 RTDB에 쓰거나 이중 fan-out하지 않는다. stale 또는 주입된 RTDB transient
  action이 보여도 composite는 이를 버린다. Firebase compact listener는 chat/access hint와 이후 authoritative
  reconciliation을 위해 계속 유지한다. RTDB transient 전환은 별도 capability gate를 통과한 뒤 명시적으로
  구현해야 한다.

### M7 — chat

- named Firebase app/region의 `sendRealtimeChat` callable adapter를 구현했다.
- request `{b,i,r}`와 response `{b,i,k?,n,t}`를 strict typed DTO로 고정했다.
- response UUID/body mismatch와 unknown bubble wire code는 성공으로 확정하지 않고 reconciliation pending으로
  남긴다.
- `unauthenticated`, `permission-denied`, `resource-exhausted`, `failed-precondition`, `invalid-argument`만
  frozen contract의 non-commit 보장에 따라 terminal reject로 분류한다.
- deadline/internal/unavailable/transport 및 알 수 없는 오류는 commit-ambiguous로 유지한다.
- commit-ambiguous 결과는 callable을 재전송하지 않고 동일 `client_message_id`로 bounded Supabase lookup을
  수행한다. 일치하는 durable row가 확인되면 confirmed, 확인되지 않으면 기존 UUID를 pending으로 유지한다.
- upstream 오류 body나 message body를 사용자 오류/로그에 반사하지 않는다.

### M8 — grant contract

- `create_room_v2`, `join_room_v2`, `set_equipped_cosmetic_v2`,
  `current_firebase_access_revision`, `get_store_state_v2` client DTO/RPC를 추가했다.
- access revision barrier는 requested revision 이상 ACK, membership/entitlement 유효성, revoke를 별도로
  추적한다.
- transport 선택이 Firebase v2일 때 room 생성·참여, cosmetic 장착과 구매 직후 자동 장착은 v2 RPC가 반환한
  exact access revision을 composite transport에 수렴시킨 뒤에만 새 room/장착 상태를 앱에 노출한다.
- 서버 mutation 성공 뒤 grant 수렴이 실패한 경우는 일반 mutation 실패와 분리해 `committedPendingGrant`로
  유지한다. composite는 pending exact revision을 보존하고 다음 정상 synchronize에서 grant 수렴만 재시도한다.
  이미 커밋된 create/join/equip을 자동 재호출하지 않는다.
- legacy transport 선택은 기존 RPC를 그대로 호출하며 v2 RPC나 grant barrier를 거치지 않는다.

Firebase v2 선택 시에만 v2 mutation/grant RPC를 호출하며, selector가 legacy를 반환한 세션은 기존 RPC를 유지한다.

## 남은 release 운영

1. backend production migration/Functions/Rules 최종 read-back과 `CLIENT_BACKEND_HANDOFF.md` 보존
2. production internal 계정 smoke 및 cleanup residual 0 증거 보존
3. internal → canary → staged rollout 후 backend가 기록한 T0부터 legacy compatibility를 최소 7일 관찰

`AppCoordinator`는 Supabase boot/auth가 완료된 다음에만 selector와 concrete Firebase runtime을 비동기로 만든다.
선택이 Firebase인 동안 같은 `SideyBackend` socket을 Presence/Broadcast/authoritative reconciliation에 재사용한다.
remote selector는 lease refresh 시점마다 다시 등록하고 bootstrap, Firebase Auth, listener generation을
순서대로 교체한다. 개별 session/cohort의 explicit legacy 응답은 Firebase listener/Auth를 폐기한 뒤 새
legacy event subscription으로 동기화한다. 전역 emergency kill과 `realtime_rollout_disabled`, lease hard
expiry는 즉시 fail-closed하며, selector/bootstrap의 일시 장애는 legacy로 downgrade하지 않고 기존 lease
안에서만 재시도한다. legacy synchronize가 성공하기 전에는 selection을 커밋하지 않고 모든 publish/send를
차단한다.

7일은 자동 종료 시점이 아니라 최소 관찰 기간이다. 기간이 지났다는 이유만으로 legacy 지원을 끄지 않는다.
backend에서 측정한 활성 client protocol 채택률이 종료 기준을 만족하거나, 최소 지원 버전을 강제해 구버전
접속을 안전하게 차단한 상태여야 한다. 여기에 구버전↔신버전 혼합 matrix의 typing·pulse·throw·Presence·chat과
membership/revoke 검증이 모두 통과해야만 legacy 비활성화를 검토할 수 있다.

App Store의 environment/plist transport preference는 무시한다. production transport 선택권은 authenticated
selector 하나만 가지며, 마지막 enabled 결정 뒤 selector fetch/cache가 실패하면 legacy로 downgrade하지 않는다.

## 테스트와 검증

추가/변경 unit test는 다음을 포함한다.

- runtime config와 App Store Firebase identity/default RTDB 거부
- router 단일 선택, factory failure, permission 무-downgrade
- bootstrap DTO/HTTP 분류/Auth claim/A-B session isolation
- listener identity/resource count, latest-wins room operation
- Presence first sync/self-track/member purge/deadline
- inbox/live snapshot baseline, revision/sequence gap, transient freshness, orphan typing 6초 TTL
- exact transient write와 wire-code fail-close
- 혼합 버전 composite의 transient Supabase RPC 위임, Firebase 직접 write 부재, Supabase transient 수신 및 stale/injected RTDB transient drop
- callable chat compact DTO, error commit 분류, UUID/body/wire-code 검증, ambiguous 동일 UUID lookup/no-resend
- v2 grant RPC DTO와 revision barrier
- create/join/equip·구매 직후 자동 장착의 exact revision 수렴, legacy RPC 유지, grant 실패 시 committed/pending 분리
- strict 7-key selector와 11-key bootstrap decode, marketing+build app version, TTL/lease cache와
  prior-enabled fail-close
- server `Date` clock-skew 보정, `sideyRolloutUntil` exact claim, 최대 5분 lease와 hard expiry
- selector 재등록 → bootstrap → Auth → inbox/live listener generation 교체 및 일시 장애 retry
- 실행 중 kill-switch의 fresh legacy subscription, Firebase retire, sync-before-commit, 실패 중 operation 차단

검증 결과는 다음과 같다.

- Firebase v2 focused 7-suite 검증: 실패 0개
- `scripts/macos/tests/test_native.sh`: SIDEY XCTest 497개 실행, 실패 0개, backend integration 1개
  환경 미설정으로 skip
- 같은 명령의 recording suite: 10개 통과, 실패 0개
- macOS asset 검증: 57개 일치
- macOS Python 검증: 7개 통과

최종 backend fixture hash를 반영했다. 최신 `main` 동기화 뒤 같은 canonical suite와 workflow check를 다시
실행해야 한다. 위 결과는 lease renewal 구현까지 포함한 현재 client snapshot의 검증 기록이다.

## rollback과 release

- runtime permission failure 자동 legacy downgrade: 없음
- production feature flag: authenticated selector의 cohort basis points + server-only Firebase emergency gate
- cohort/session rollback: 최대 300초 lease 안에 explicit legacy 응답을 확인하고 안전한 Supabase 전환 수행
- global emergency rollback: 남은 lease와 무관하게 RTDB read/callable write를 즉시 fail-closed
- 임시 계정/데이터: 생성하지 않음
- production release: 수행하지 않음
