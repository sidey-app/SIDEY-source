# Server-enforced room security

Status: Accepted
Decided: 2026-09-01 12:57 KST
Evidence: [commit 12dff17](https://github.com/sidey-app/SIDEY-source/commit/12dff170b4f664ee942c0257ca369c8a1f742363)

## Context

짧은 invite code의 hash를 public room row나 Realtime payload에 노출하면 database를
읽을 수 있는 주체가 offline 대입으로 code를 복원할 수 있었다. Client-side 확인만으로는
room membership과 시도 제한을 보호할 수 없었다.

## Decision

Postgres message를 원본으로 두고 room membership, 정원, 사용자별 room 수, event rate와
Realtime channel 권한을 server가 확인한다. Membership 변경은 epoch로 기존 channel을
격리한다. Invite code는 충분한 난수로 만들고 API에 노출되지 않는 private server
영역에 pepper를 사용한 HMAC만 저장한다. 과거의 짧은 code는 비활성화한다.

## Consequences

Client는 DB 알림을 최종 message로 신뢰하지 않고 RLS를 거쳐 다시 읽으며, transient
event도 server가 확인한 channel만 사용한다. Public schema는 invite secret이나 검증
hash를 알 수 없다. 세부 schema와 migration은 비공개 backend가 소유한다.
