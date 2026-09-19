# 메시징

## 영구 데이터와 실시간 신호

Postgres가 메시지의 source of truth다. 클라이언트는 UUID로 메시지를 낙관적으로
표시하되 저장 결과와 Realtime 알림을 같은 UUID로 조정한다. 확정 여부가 불분명한
실패도 같은 UUID로 확인하고 재시도해 중복 발송을 만들지 않는다. 메시지는 서버
보관 정책에 따라 생성 후 사흘이 지나면 삭제된다.

Presence는 연결·online·away 상태에 사용한다. Broadcast는 SIDEY 입력창의 typing,
캐릭터 pulse와 projectile 같은 저장하지 않는 event에만 사용한다. DB 변경 알림은
식별자만 전달하고 client가 RLS를 거쳐 row를 다시 읽는다. 연결이 복구되면 membership,
presence와 최근 메시지를 다시 맞춘 뒤 online으로 전환한다.

## 작성과 표시

메시지 입력은 최대 200자·3줄을 허용한다. Enter는 전송,
Shift+Enter는 줄바꿈이다. Typing은 SIDEY 입력창의 lease 동안만 표시하고 실제 메시지
말풍선이 있으면 본문을 우선한다.

Windows typing lease는 실제 입력 내용 수정으로 시작하고 갱신한다. 입력창을 열거나
보관한 draft를 복원하는 것만으로 typing을 보내지 않으며, 입력을 멈추면 만료한다.
로컬 표시는 즉시 반영하고 원격 시작·갱신은 지연·간격 제한으로 묶어 전송한다. 추가
편집 없이 주기적으로 갱신하거나 실패한 typing을 자동 재시도하지 않는다. 전송, 입력창
닫기와 방 전환은 lease를 끝내며, 시작·종료 신호는 같은 순서 보장 경로로 전송한다.

Overlay는 발신자별 최신 메시지를 최대 두 개 표시하고 각각 일정 시간이 지나면
없앤다. 과거 기록 조회나 reconnect snapshot은 지나간 말풍선을 다시 재생하지 않는다.
조용히 모드는 새 메시지 본문 말풍선을 숨기지만 typing과 그룹별 미확인 수는 유지한다.

최근 기록은 server retention 범위에서 페이지로 읽는다. Pending과 failed 전송은 원래
방의 outbox에 남으며 다른 방의 draft를 바꾸지 않는다.

## 보안 경계

Room membership, message rate와 transient event 권한은 서버가 확인한다. 로그에는
message body, token, 평문 invite code와 사용자·방·메시지 식별자 원문을 남기지 않는다.

## 실제 편집 기반 타이핑

Windows와 macOS App Store판은 실제 텍스트 편집(IME 조합·삭제·붙여넣기 포함)에
본인 typing을 즉시 표시하고 첫 원격 start를 첫 편집 500ms 뒤에 예약한다. 후속 편집은
최초 예약을 미루지 않는다. 전송·취소·전체 삭제·입력창 닫기·방 전환·탈퇴는 예약을
취소하고 해당 방의 상태를 종료한다. 시작을 발행하지 않은 짧은 입력은 stop도 발행하지 않는다.

갱신은 마지막 발행 이후 실제 편집이 있을 때만 최소 2초 간격으로 보낸다. 마지막 실제
편집 5초 뒤 종료하며 포커스·커서 이동, draft 복원, 타이머와 네트워크 완료는 편집이 아니다.
전송은 직렬화하고 내부 작업 세대로 오래된 예약을 취소한다. 실패한 일시 이벤트는 자동
재시도하거나 누적하지 않으며 다음 실제 편집에서 다시 시도할 수 있다. typing 실패만으로
방의 연결 상태를 바꾸지 않는다. 메시지 저장·재전송·복구 계약은 유지한다.

Supabase RPC와 typing_start/typing_stop, 방 realtime epoch는 유지한다. typing용 wire
revision을 추가하지 않는다. 정상 stop과 별도로 수신 6초 TTL이 유실된 상태를 정리한다.
기존 4초 TTL 수신자는 업데이트 전까지 약 0.5초 일찍 typing을 숨길 수 있다. 종료 시
타이머와 비동기 작업을 정리하며 전송할 수 없는 stop은 수신 TTL로 만료된다.
