import XCTest
@testable import SIDEY

final class FirebaseV2TransientWriterTests: XCTestCase {
    func testTypingWritesServerTimestampAndStopsOnlyExactSessionSlot() async throws {
        let transport = FirebaseV2DatabaseWriteTransportStub()
        let context = makeContext()
        let writer = FirebaseV2TransientWriter(transport: transport, context: context)

        try await writer.publishTyping(roomID: context.activeRoomID, event: "typing_start")
        try await writer.publishTyping(roomID: context.activeRoomID, event: "typing_keepalive")
        try await writer.publishTyping(roomID: context.activeRoomID, event: "typing_stop")

        let path = FirebaseV2Path.typing(
            roomID: context.activeRoomID,
            userID: context.identity.accountID,
            sessionID: context.identity.sessionID
        )
        let operations = await transport.operations
        XCTAssertEqual(operations, [
            .setServerTimestamp(path: path),
            .setServerTimestamp(path: path),
            .remove(path: path),
        ])
    }

    func testPulseAndThrowUseActiveRoomAndRuntimeWireMapping() async throws {
        let transport = FirebaseV2DatabaseWriteTransportStub()
        let context = makeContext()
        let writer = FirebaseV2TransientWriter(transport: transport, context: context)
        let targetID = UUID()

        try await writer.publishPulse(roomID: context.activeRoomID)
        try await writer.publishThrow(
            roomID: context.activeRoomID,
            targetUserID: targetID,
            catalogItemID: "throwable_leaf"
        )

        let operations = await transport.operations
        XCTAssertEqual(operations, [
            .setServerTimestamp(path: FirebaseV2Path.pulse(
                roomID: context.activeRoomID,
                userID: context.identity.accountID
            )),
            .setThrow(
                path: FirebaseV2Path.characterThrow(
                    roomID: context.activeRoomID,
                    userID: context.identity.accountID
                ),
                targetUserID: targetID,
                wireCode: try XCTUnwrap(FirebaseV2WireCode(rawValue: "18"))
            ),
        ])
    }

    func testUnknownOrUnauthorizedWireCodeFailsClosedWithoutWrite() async throws {
        let transport = FirebaseV2DatabaseWriteTransportStub()
        var context = makeContext()
        context.authorizedWireCodes = []
        let writer = FirebaseV2TransientWriter(transport: transport, context: context)

        do {
            try await writer.publishThrow(
                roomID: context.activeRoomID,
                targetUserID: UUID(),
                catalogItemID: "throwable_leaf"
            )
            XCTFail("An unauthorized wire code must be dropped")
        } catch let error as FirebaseV2TransientWriterError {
            XCTAssertEqual(error, .wireCodeUnavailable)
        }
        let operations = await transport.operations
        XCTAssertEqual(operations, [])
    }

    func testInactiveRoomAndUnsupportedTypingEventFailBeforeWrite() async throws {
        let transport = FirebaseV2DatabaseWriteTransportStub()
        let context = makeContext()
        let writer = FirebaseV2TransientWriter(transport: transport, context: context)

        do {
            try await writer.publishPulse(roomID: UUID())
            XCTFail("Inactive room write must fail")
        } catch let error as FirebaseV2TransientWriterError {
            XCTAssertEqual(error, .inactiveRoom)
        }
        do {
            try await writer.publishTyping(roomID: context.activeRoomID, event: "retry_now")
            XCTFail("Unknown typing state must fail")
        } catch let error as FirebaseV2TransientWriterError {
            XCTAssertEqual(error, .unsupportedTypingEvent)
        }
        let operations = await transport.operations
        XCTAssertEqual(operations, [])
    }

    private func makeContext() -> FirebaseV2TransientContext {
        FirebaseV2TransientContext(
            identity: RealtimeCredentialIdentity(accountID: UUID(), sessionID: UUID()),
            activeRoomID: UUID(),
            throwableWireCodesByCatalogID: [
                "throwable_leaf": FirebaseV2WireCode(rawValue: "18")!,
            ],
            authorizedWireCodes: [FirebaseV2WireCode(rawValue: "18")!]
        )
    }
}

private actor FirebaseV2DatabaseWriteTransportStub: FirebaseV2DatabaseWriteTransport {
    private(set) var operations: [FirebaseV2DatabaseWriteOperation] = []

    func perform(_ operation: FirebaseV2DatabaseWriteOperation) async throws {
        operations.append(operation)
    }
}
