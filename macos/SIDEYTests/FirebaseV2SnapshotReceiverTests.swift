import XCTest
@testable import SIDEY

final class FirebaseV2SnapshotReceiverTests: XCTestCase {
    func testDatabaseSnapshotSerializerTreatsMissingFirebaseValueAsEmptyObject() throws {
        for value in [nil, NSNull()] as [Any?] {
            let data = try FirebaseV2DatabaseSnapshotSerializer.data(from: value)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(object?.count, 0)
        }
    }

    func testDatabaseSnapshotSerializerRejectsTopLevelScalarsWithoutCallingJSONWriter() {
        for value in ["invalid", 1, true] as [Any] {
            XCTAssertThrowsError(
                try FirebaseV2DatabaseSnapshotSerializer.data(from: value)
            ) { error in
                XCTAssertEqual(
                    error as? FirebaseV2DatabaseSnapshotSerializationError,
                    .expectedObject
                )
            }
        }
    }

    func testInboxInitialSnapshotIsBaselineAndOnlyIncreasingHintsAct() throws {
        let roomID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        var reconciler = FirebaseV2InboxReconciler()
        let baseline = try FirebaseV2InboxSnapshot.decode(Data("""
        {"a":"00000000000000000010","r":{"\(roomID.uuidString.lowercased())":{
          "v":"00000000000000000020","n":7
        }}}
        """.utf8))
        XCTAssertTrue(reconciler.consume(baseline).isEmpty)

        let advanced = try FirebaseV2InboxSnapshot.decode(Data("""
        {"a":"00000000000000000011","r":{"\(roomID.uuidString.lowercased())":{
          "v":"00000000000000000021","n":10
        }}}
        """.utf8))
        XCTAssertEqual(reconciler.consume(advanced), [
            .accessRevisionAdvanced(try XCTUnwrap(RealtimeRevision(rawValue: "00000000000000000011"))),
            .roomRevisionAdvanced(
                roomID: roomID,
                revision: try XCTUnwrap(RealtimeRevision(rawValue: "00000000000000000021"))
            ),
            .chatSequenceAdvanced(roomID: roomID, sequence: 10, hasGap: true),
        ])

        XCTAssertTrue(reconciler.consume(baseline).isEmpty, "reordered hints must be ignored")
    }

    func testInboxRejectsUnsafeSequenceAndMalformedRevision() {
        XCTAssertThrowsError(try FirebaseV2InboxSnapshot.decode(Data(
            #"{"a":"1","r":{}}"#.utf8
        )))
        XCTAssertThrowsError(try FirebaseV2InboxSnapshot.decode(Data(
            #"{"r":{"11111111-1111-4111-8111-111111111111":{"n":9007199254740992}}}"#.utf8
        )))
    }

    func testFirstChatSequenceAfterBaselineTriggersReconciliation() throws {
        let roomID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        var reconciler = FirebaseV2InboxReconciler()
        let baseline = FirebaseV2InboxSnapshot(
            accessRevision: nil,
            rooms: [roomID: FirebaseV2RoomHint(revision: nil, chatSequence: nil)]
        )
        XCTAssertTrue(reconciler.consume(baseline).isEmpty)

        let firstMessage = FirebaseV2InboxSnapshot(
            accessRevision: nil,
            rooms: [roomID: FirebaseV2RoomHint(revision: nil, chatSequence: 4)]
        )
        XCTAssertEqual(reconciler.consume(firstMessage), [
            .chatSequenceAdvanced(roomID: roomID, sequence: 4, hasGap: true),
        ])
    }

    func testLiveBaselineSuppressesPersistentPulseThrowAndChatReplay() throws {
        let actor = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let target = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let baseline = try liveSnapshot(
            actor: actor,
            target: target,
            timestamp: 10_000,
            sequence: 4,
            typing: true
        )
        var reconciler = FirebaseV2LiveReconciler()

        XCTAssertEqual(
            reconciler.consume(baseline, receivedAtMilliseconds: 10_100),
            [.typing(userID: actor, active: true)]
        )

        let advanced = try liveSnapshot(
            actor: actor,
            target: target,
            timestamp: 11_000,
            sequence: 5,
            typing: false
        )
        XCTAssertEqual(reconciler.consume(advanced, receivedAtMilliseconds: 11_100), [
            .typing(userID: actor, active: false),
            .pulse(
                userID: actor,
                timestamp: try XCTUnwrap(FirebaseV2Timestamp(rawValue: 11_000))
            ),
            .characterThrow(
                actorUserID: actor,
                payload: FirebaseV2ThrowPayload(
                    wireCode: try XCTUnwrap(FirebaseV2WireCode(rawValue: "7")),
                    timestamp: try XCTUnwrap(FirebaseV2Timestamp(rawValue: 11_000)),
                    targetUserID: target
                )
            ),
            .chatHint(FirebaseV2ChatEventPayload(
                body: "new",
                messageID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                bubbleWireCode: nil,
                sequence: 5,
                senderUserID: actor,
                timestamp: try XCTUnwrap(FirebaseV2Timestamp(rawValue: 11_000))
            )),
        ])
    }

    func testLiveDropsDuplicateAndExpiredTransientValues() throws {
        let actor = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let target = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        var reconciler = FirebaseV2LiveReconciler()
        let baseline = try liveSnapshot(actor: actor, target: target, timestamp: 10_000, sequence: 4)
        _ = reconciler.consume(baseline, receivedAtMilliseconds: 10_100)
        XCTAssertTrue(reconciler.consume(baseline, receivedAtMilliseconds: 10_200).isEmpty)

        let expired = try liveSnapshot(actor: actor, target: target, timestamp: 20_000, sequence: 4)
        XCTAssertTrue(reconciler.consume(expired, receivedAtMilliseconds: 25_001).isEmpty)
    }

    func testTypingSlotExpiresAfterSixSecondsWithoutRemovalSnapshot() throws {
        let actor = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let target = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        var reconciler = FirebaseV2LiveReconciler()
        let snapshot = try liveSnapshot(
            actor: actor,
            target: target,
            timestamp: 10_000,
            sequence: 1,
            typing: true
        )

        XCTAssertEqual(
            reconciler.consume(snapshot, receivedAtMilliseconds: 10_100),
            [.typing(userID: actor, active: true)]
        )
        XCTAssertEqual(reconciler.nextTypingExpiryMilliseconds, 16_000)
        XCTAssertTrue(reconciler.expireTyping(receivedAtMilliseconds: 15_999).isEmpty)
        XCTAssertEqual(
            reconciler.expireTyping(receivedAtMilliseconds: 16_000),
            [.typing(userID: actor, active: false)]
        )
        XCTAssertTrue(reconciler.expireTyping(receivedAtMilliseconds: 17_000).isEmpty)
    }

    func testStaleTypingSlotNeverBecomesActive() throws {
        let actor = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let target = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        var reconciler = FirebaseV2LiveReconciler()
        let snapshot = try liveSnapshot(
            actor: actor,
            target: target,
            timestamp: 10_000,
            sequence: 1,
            typing: true
        )

        XCTAssertTrue(reconciler.consume(snapshot, receivedAtMilliseconds: 16_001).isEmpty)
        XCTAssertNil(reconciler.nextTypingExpiryMilliseconds)
    }

    private func liveSnapshot(
        actor: UUID,
        target: UUID,
        timestamp: Int64,
        sequence: Int64,
        typing: Bool = false
    ) throws -> FirebaseV2LiveSnapshot {
        let actorID = actor.uuidString.lowercased()
        let targetID = target.uuidString.lowercased()
        let typingJSON = typing ? #", "t":{"\#(actorID)":{"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa":\#(timestamp)}}"# : ""
        return try FirebaseV2LiveSnapshot.decode(Data("""
        {
          "c":{"\(actorID)":\(timestamp)},
          "x":{"\(actorID)":{"u":"\(targetID)","k":"7","t":\(timestamp)}},
          "e":{"i":"55555555-5555-4555-8555-555555555555","s":"\(actorID)","b":"new","t":\(timestamp),"n":\(sequence)}
          \(typingJSON)
        }
        """.utf8))
    }
}
