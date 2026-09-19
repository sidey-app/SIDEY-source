import XCTest
@testable import SIDEYAppStore

final class MessageLedgerTests: XCTestCase {
    func testPostgresTimestampsDecodeFractionalAndWholeSecondsWithUTCOffsets() throws {
        let timestamps = [
            "2026-08-31T01:02:03.123Z",
            "2026-08-31T01:02:03.123456Z",
            "2026-08-31T01:02:03Z",
            "2026-08-31T01:02:03+00:00",
            "2026-08-31T10:02:03.123456+09:00"
        ]
        let decoded = try timestamps.map(PostgresTimestampDecoder.decode)

        XCTAssertEqual(decoded[1].timeIntervalSince(decoded[0]), 0.000456, accuracy: 0.000001)
        XCTAssertEqual(decoded[0].timeIntervalSince(decoded[2]), 0.123, accuracy: 0.000001)
        XCTAssertEqual(decoded[2], decoded[3])
        XCTAssertEqual(decoded[1], decoded[4])
    }

    func testInvalidPostgresTimestampFailsInsteadOfUsingCurrentTime() {
        for value in [
            "",
            "2026-08-31 01:02:03",
            "2026-08-31T25:02:03Z",
            "2026-08-31T01:02:03.1234567Z",
            "2026-08-31T01:02:03+24:00",
            "not-a-date"
        ] {
            XCTAssertThrowsError(try PostgresTimestampDecoder.decode(value)) { error in
                XCTAssertEqual(error as? SideyBackendError, .invalidTimestamp)
            }
        }
    }

    @MainActor
    func testDistinctServerTimestampsRemainDistinctAndOrderHistoryNewestFirst() throws {
        let roomID = UUID()
        let senderID = UUID()
        let older = try DatabaseMessage(
            id: UUID(), roomID: roomID, senderID: senderID, body: "이전",
            createdAt: "2026-08-31T01:02:03.123Z"
        ).domain
        let newer = try DatabaseMessage(
            id: UUID(), roomID: roomID, senderID: senderID, body: "최신",
            createdAt: "2026-08-31T01:02:04.456789+00:00"
        ).domain
        var ledger = MessageLedger()
        let now = newer.createdAt.addingTimeInterval(60)

        ledger.confirm(newer, now: now)
        ledger.confirm(older, now: now)

        XCTAssertNotEqual(older.createdAt, newer.createdAt)
        XCTAssertEqual(
            MessageHistoryMerge.entries(
                pagedMessages: [],
                ledger: ledger,
                outbox: MessageOutbox(),
                roomID: roomID,
                now: now
            ).map(\.body),
            ["최신", "이전"]
        )
    }

    func testOptimisticMessagePreservesSenderAndConfirmsWithoutDuplicate() {
        let id = UUID()
        let roomID = UUID()
        let senderID = UUID()
        let message = ChatMessage(
            id: id,
            roomID: roomID,
            senderID: senderID,
            body: "안녕",
            createdAt: .now
        )
        var ledger = MessageLedger()
        var outbox = MessageOutbox()

        outbox.stage(id: id, roomID: roomID, senderID: senderID, body: "안녕")
        XCTAssertTrue(outbox.confirm(id: id, roomID: roomID))
        XCTAssertTrue(ledger.confirm(message))
        XCTAssertFalse(ledger.confirm(message), "Realtime echo must remain deduplicated")

        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.senderID, senderID)
        XCTAssertEqual(ledger.entries.first?.state, .confirmed)
    }

    func testConfirmedMessageKeepsServerSnapshotBubbleStyleAcrossDuplicateDelivery() {
        let message = ChatMessage(
            id: UUID(),
            roomID: UUID(),
            senderID: UUID(),
            body: "처음 색을 기억해",
            createdAt: .now,
            bubbleStyleID: "bubble_bunny_pink"
        )
        var ledger = MessageLedger()

        XCTAssertTrue(ledger.confirm(message))
        XCTAssertFalse(ledger.confirm(message))
        XCTAssertEqual(ledger.entries.first?.bubbleStyleID, "bubble_bunny_pink")
    }

    @MainActor
    func testHistoryOrdersNewestMessageFirstWithoutLegacyTwentyRowCap() {
        let roomID = UUID()
        let now = Date()
        var ledger = MessageLedger()
        for index in 0..<24 {
            _ = ledger.confirm(ChatMessage(
                id: UUID(),
                roomID: roomID,
                senderID: UUID(),
                body: "메시지 \(index)",
                createdAt: now.addingTimeInterval(TimeInterval(index - 24))
            ), now: now)
        }

        let entries = MessageHistoryMerge.entries(
            pagedMessages: [],
            ledger: ledger,
            outbox: MessageOutbox(),
            roomID: roomID
        )
        XCTAssertEqual(entries.count, 24)
        XCTAssertEqual(entries.first?.body, "메시지 23")
        XCTAssertEqual(entries.last?.body, "메시지 0")
    }

    func testActiveBubblesKeepTwoPerSenderWithoutGlobalEvictionAndExpireIndependently() {
        var bubbles = ActiveBubbleLedger()
        let start = Date(timeIntervalSince1970: 1_000)
        let senders = (0..<12).map { _ in UUID() }
        var messageIDs: [[UUID]] = []

        for (senderIndex, senderID) in senders.enumerated() {
            let ids = [UUID(), UUID()]
            messageIDs.append(ids)
            for messageIndex in 0..<2 {
                bubbles.show(
                    senderID: senderID,
                    messageID: ids[messageIndex],
                    body: "\(senderIndex)-\(messageIndex)",
                    expiresAt: start.addingTimeInterval(TimeInterval(10 + messageIndex))
                )
            }
        }

        XCTAssertEqual(bubbles.bubbles.count, 24)
        XCTAssertEqual(Set(bubbles.bubbles.map(\.senderID)), Set(senders))

        let thirdID = UUID()
        bubbles.show(
            senderID: senders[0],
            messageID: thirdID,
            body: "세 번째",
            expiresAt: start.addingTimeInterval(12)
        )
        XCTAssertEqual(bubbles.bubbles.count, 24)
        XCTAssertFalse(bubbles.bubbles.contains { $0.messageID == messageIDs[0][0] })
        XCTAssertTrue(bubbles.bubbles.contains { $0.messageID == messageIDs[0][1] })
        XCTAssertTrue(bubbles.bubbles.contains { $0.messageID == thirdID })

        bubbles.remove(messageID: thirdID)
        XCTAssertFalse(bubbles.bubbles.contains { $0.messageID == thirdID })
        XCTAssertEqual(bubbles.bubbles.filter { $0.senderID == senders[0] }.count, 1)

        bubbles.prune(at: start.addingTimeInterval(10.5))
        XCTAssertEqual(bubbles.bubbles.count, 12)
        XCTAssertTrue(bubbles.bubbles.allSatisfy { $0.expiresAt > start.addingTimeInterval(10.5) })
    }

    @MainActor
    func testInactiveRoomMessageDoesNotCreateVisibleBubbleAndUnreadDeduplicates() {
        let activeRoomID = UUID()
        let inactiveRoomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = activeRoomID
        let model = AppModel(preferences: preferences)
        model.rooms = [
            Self.room(id: activeRoomID, name: "활성"),
            Self.room(id: inactiveRoomID, name: "다른 그룹")
        ]
        let activeMessage = ChatMessage(
            id: UUID(), roomID: activeRoomID, senderID: UUID(), body: "보이는 메시지", createdAt: .now
        )
        let inactiveMessage = ChatMessage(
            id: UUID(), roomID: inactiveRoomID, senderID: UUID(), body: "조용한 수신", createdAt: .now
        )

        XCTAssertTrue(model.confirmMessage(activeMessage))
        XCTAssertTrue(model.confirmMessage(inactiveMessage, revealBubble: false))
        model.incrementUnread(in: inactiveRoomID)
        XCTAssertFalse(model.confirmMessage(inactiveMessage, revealBubble: false))

        XCTAssertEqual(model.activeBubbles.map(\.body), ["보이는 메시지"])
        XCTAssertEqual(model.unreadCount(in: inactiveRoomID), 1)
    }

    @MainActor
    func testFailedOptimisticMessageRestoresBodyAndRemovesBubble() {
        let id = UUID()
        let roomID = UUID()
        let senderID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomID, name: "활성")]
        model.stageMessage(id: id, roomID: roomID, senderID: senderID, body: "복구할 메시지")

        let failed = model.failMessage(id: id, roomID: roomID)
        XCTAssertEqual(failed?.body, "복구할 메시지")
        XCTAssertEqual(failed?.roomID, roomID)
        XCTAssertEqual(failed?.state, .failed)
        XCTAssertTrue(model.messageLedger.entries.isEmpty)
        XCTAssertEqual(model.messageOutbox.entries.count, 1)
        XCTAssertTrue(model.activeBubbles.isEmpty)
    }

    @MainActor
    func testHistoryReplacementNeverReplaysOldMessagesAsBubbles() {
        let roomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomID, name: "조용한 방")]
        let message = ChatMessage(
            id: UUID(), roomID: roomID, senderID: UUID(), body: "기록 원본", createdAt: .now
        )

        model.replaceMessages(roomID: roomID, with: [message])

        XCTAssertTrue(model.activeBubbles.isEmpty)
        XCTAssertEqual(model.messageLedger.entries.count, 1)
    }

    func testReplacingServerHistoryKeepsPendingMessageAndDeduplicatesRows() {
        let roomID = UUID()
        let pendingID = UUID()
        let confirmed = ChatMessage(
            id: UUID(), roomID: roomID, senderID: UUID(), body: "서버 원본", createdAt: .now
        )
        var ledger = MessageLedger()
        var outbox = MessageOutbox()
        outbox.stage(id: pendingID, roomID: roomID, senderID: UUID(), body: "전송 중")

        ledger.replaceConfirmed(roomID: roomID, with: [confirmed, confirmed])

        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.filter { $0.state == .confirmed }.map(\.id), [confirmed.id])
        XCTAssertEqual(outbox.entries.map(\.id), [pendingID])
    }

    @MainActor
    func testFailureInRoomADoesNotOverwriteRoomBDraft() {
        let roomA = UUID()
        let roomB = UUID()
        let messageID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomA
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomA, name: "A"), Self.room(id: roomB, name: "B")]
        model.stageMessage(
            id: messageID,
            roomID: roomA,
            senderID: UUID(),
            body: "A의 비공개 메시지"
        )

        model.preferences.activeRoomID = roomB
        model.draft = "B에서 작성 중"
        _ = model.failMessage(id: messageID, roomID: roomA)

        XCTAssertEqual(model.draft, "B에서 작성 중")
        XCTAssertEqual(model.messageOutbox.entries.first?.roomID, roomA)
        XCTAssertEqual(model.messageOutbox.entries.first?.state, .failed)
    }

    func testConfirmedLedgerAppliesThreeDayCutoffAndFiftyPerRoomLimit() {
        let roomID = UUID()
        let boundaryRoomID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        var ledger = MessageLedger()
        _ = ledger.confirm(ChatMessage(
            id: UUID(),
            roomID: boundaryRoomID,
            senderID: UUID(),
            body: "만료",
            createdAt: now.addingTimeInterval(-MessageLedger.retentionInterval - 1)
        ), now: now)
        _ = ledger.confirm(ChatMessage(
            id: UUID(),
            roomID: boundaryRoomID,
            senderID: UUID(),
            body: "경계",
            createdAt: now.addingTimeInterval(-MessageLedger.retentionInterval)
        ), now: now)
        for index in 0..<60 {
            _ = ledger.confirm(ChatMessage(
                id: UUID(),
                roomID: roomID,
                senderID: UUID(),
                body: "최근 \(index)",
                createdAt: now.addingTimeInterval(TimeInterval(index - 60))
            ), now: now)
        }

        XCTAssertEqual(ledger.entries.count, 51)
        XCTAssertFalse(ledger.entries.contains(where: { $0.body == "만료" }))
        XCTAssertTrue(ledger.entries.contains(where: { $0.body == "경계" }))
        XCTAssertEqual(ledger.entries.first?.body, "경계")
    }

    private static func room(id: UUID, name: String) -> Room {
        Room(
            id: id,
            name: name,
            ownerID: UUID(),
            members: [],
            inviteCodeHint: "ABCD",
            inviteVersion: 1
        )
    }
}
