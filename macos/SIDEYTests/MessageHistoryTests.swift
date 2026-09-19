import AppKit
import SwiftUI
import XCTest
@testable import SIDEYAppStore

final class MessageHistoryTests: XCTestCase {
    func testPageMapperHandlesZeroThroughFiftyOneRows() throws {
        let roomID = UUID()
        for count in [0, 1, 20, 50] {
            let page = try MessageHistoryPageMapper.page(
                from: Self.databaseRows(count: count, roomID: roomID),
                pageSize: 50
            )
            XCTAssertEqual(page.messages.count, count)
            XCTAssertNil(page.nextCursor)
        }

        let rows = Self.databaseRows(count: 51, roomID: roomID)
        let page = try MessageHistoryPageMapper.page(from: rows, pageSize: 50)
        XCTAssertEqual(page.messages.count, 50)
        XCTAssertEqual(page.nextCursor?.rawCreatedAt, rows[49].createdAt)
        XCTAssertEqual(page.nextCursor?.id, rows[49].id)
    }

    func testKeysetCursorPreservesMicrosecondsAndSplitsEqualTimestampsByUUID() throws {
        let roomID = UUID()
        let rawTimestamp = "2026-08-31T01:02:03.123456Z"
        let rows = (1...51)
            .map { index in
                DatabaseMessage(
                    id: Self.uuid(index),
                    roomID: roomID,
                    senderID: UUID(),
                    body: "메시지 \(index)",
                    createdAt: rawTimestamp
                )
            }
            .sorted { $0.id.uuidString > $1.id.uuidString }

        let page = try MessageHistoryPageMapper.page(from: rows, pageSize: 50)
        let cursor = try XCTUnwrap(page.nextCursor)
        let nextRows = rows.filter {
            $0.createdAt < cursor.rawCreatedAt
                || ($0.createdAt == cursor.rawCreatedAt && $0.id.uuidString < cursor.id.uuidString)
        }

        XCTAssertEqual(cursor.rawCreatedAt, rawTimestamp)
        XCTAssertEqual(nextRows.map(\.id), [rows[50].id])
        XCTAssertTrue(Set(page.messages.map(\.id)).isDisjoint(with: nextRows.map(\.id)))
    }

    func testConfirmedPageMergeDeduplicatesAcrossPagesAndKeepsOneHundredTwentyRows() {
        let roomID = UUID()
        let first = Self.messages(0..<50, roomID: roomID)
        let second = Self.messages(49..<100, roomID: roomID)
        let third = Self.messages(100..<120, roomID: roomID)

        let merged = MessageHistoryMerge.mergeConfirmed(
            MessageHistoryMerge.mergeConfirmed(first, with: second, roomID: roomID),
            with: third,
            roomID: roomID
        )

        XCTAssertEqual(merged.count, 120)
        XCTAssertEqual(merged.first?.body, "메시지 119")
        XCTAssertEqual(merged.last?.body, "메시지 0")
    }

    func testDisplayMergeIncludesRealtimePendingAndFailedWithoutDuplicateUUIDs() {
        let roomID = UUID()
        let senderID = UUID()
        let serverMessage = Self.message(0, roomID: roomID, senderID: senderID)
        let realtimeMessage = Self.message(1, roomID: roomID, senderID: senderID)
        var ledger = MessageLedger()
        var outbox = MessageOutbox()
        _ = ledger.confirm(realtimeMessage)
        outbox.stage(
            id: serverMessage.id,
            roomID: roomID,
            senderID: senderID,
            body: "서버와 같은 UUID",
            createdAt: serverMessage.createdAt
        )
        let pendingID = Self.uuid(900)
        outbox.stage(
            id: pendingID,
            roomID: roomID,
            senderID: senderID,
            body: "전송 중",
            createdAt: serverMessage.createdAt.addingTimeInterval(2)
        )
        let failedID = Self.uuid(901)
        outbox.stage(
            id: failedID,
            roomID: roomID,
            senderID: senderID,
            body: "전송 실패",
            createdAt: serverMessage.createdAt.addingTimeInterval(3)
        )
        _ = outbox.fail(id: failedID, roomID: roomID)

        let entries = MessageHistoryMerge.entries(
            pagedMessages: [serverMessage],
            ledger: ledger,
            outbox: outbox,
            roomID: roomID,
            now: serverMessage.createdAt.addingTimeInterval(4)
        )

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(entries.first(where: { $0.id == serverMessage.id })?.state, .confirmed)
        XCTAssertEqual(entries.first(where: { $0.id == pendingID })?.state, .pending)
        XCTAssertEqual(entries.first(where: { $0.id == failedID })?.state, .failed)
        XCTAssertTrue(entries.contains(where: { $0.id == realtimeMessage.id }))
    }

    func testMissingSenderUsesSafeHamsterFallback() {
        let senderID = UUID()
        let participant = MessageHistoryParticipantResolver.resolve(
            senderID: senderID,
            in: Room(
                id: UUID(),
                name: "친구들",
                ownerID: UUID(),
                members: [],
                inviteCodeHint: "ABCD"
            ),
            currentUserID: nil
        )

        XCTAssertEqual(participant.nickname, "알 수 없는 친구")
        XCTAssertEqual(participant.characterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertFalse(participant.isCurrentUser)
    }

    func testKnownCurrentUserUsesMemberIdentityAndMeBadgeState() {
        let senderID = UUID()
        let participant = MessageHistoryParticipantResolver.resolve(
            senderID: senderID,
            in: Room(
                id: UUID(),
                name: "친구들",
                ownerID: senderID,
                members: [
                    RoomMember(
                        userID: senderID,
                        nickname: "  사이디  ",
                        characterID: "pixel_penguin",
                        presence: .online
                    )
                ],
                inviteCodeHint: "ABCD"
            ),
            currentUserID: senderID
        )

        XCTAssertEqual(participant.nickname, "사이디")
        XCTAssertEqual(participant.characterID, "pixel_penguin")
        XCTAssertTrue(participant.isCurrentUser)
    }

    @MainActor
    func testStoreLoadsOneHundredTwentyMessagesInFiftyRowPages() async throws {
        let roomID = UUID()
        let firstCursor = MessageHistoryCursor(
            rawCreatedAt: "2026-08-31T01:02:03.123456Z",
            id: Self.uuid(50)
        )
        let secondCursor = MessageHistoryCursor(
            rawCreatedAt: "2026-08-30T01:02:03.654321Z",
            id: Self.uuid(100)
        )
        let store = MessageHistoryStore { requestedRoomID, cursor, pageSize in
            XCTAssertEqual(requestedRoomID, roomID)
            XCTAssertEqual(pageSize, 50)
            switch cursor {
            case nil:
                return MessageHistoryPage(
                    messages: Self.messages(0..<50, roomID: roomID),
                    nextCursor: firstCursor
                )
            case firstCursor:
                return MessageHistoryPage(
                    messages: Self.messages(50..<100, roomID: roomID),
                    nextCursor: secondCursor
                )
            default:
                return MessageHistoryPage(
                    messages: Self.messages(100..<120, roomID: roomID),
                    nextCursor: nil
                )
            }
        }

        store.activate(roomID: roomID)
        try await Self.waitUntil { store.messages.count == 50 && store.olderState == .idle }
        store.loadNextPage()
        try await Self.waitUntil { store.messages.count == 100 && store.olderState == .idle }
        store.loadNextPage()
        try await Self.waitUntil { store.messages.count == 120 && store.olderState == .exhausted }

        XCTAssertEqual(store.messages.first?.body, "메시지 119")
        XCTAssertEqual(store.messages.last?.body, "메시지 0")
    }

    @MainActor
    func testRoomSwitchCancelsStaleRequestAndCloseReleasesLoadedPages() async throws {
        let roomA = UUID()
        let roomB = UUID()
        let cancellation = expectation(description: "이전 방 요청 취소")
        let store = MessageHistoryStore { roomID, _, _ in
            if roomID == roomA {
                return try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(30))
                    return MessageHistoryPage(
                        messages: Self.messages(0..<1, roomID: roomA),
                        nextCursor: nil
                    )
                } onCancel: {
                    cancellation.fulfill()
                }
            }
            return MessageHistoryPage(
                messages: Self.messages(100..<101, roomID: roomB),
                nextCursor: nil
            )
        }

        store.activate(roomID: roomA)
        await Task.yield()
        store.roomDidChange(to: roomB)
        await fulfillment(of: [cancellation], timeout: 1)
        try await Self.waitUntil { store.initialState == .loaded }

        XCTAssertEqual(store.roomID, roomB)
        XCTAssertEqual(store.messages.map(\.roomID), [roomB])

        store.deactivate()
        XCTAssertNil(store.roomID)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.initialState, .idle)
    }

    @MainActor
    func testInitialAndNextPageFailuresCanBeRetried() async throws {
        let roomID = UUID()
        let cursor = MessageHistoryCursor(
            rawCreatedAt: "2026-08-31T01:02:03.123456Z",
            id: Self.uuid(1)
        )
        var initialAttempts = 0
        var nextAttempts = 0
        let store = MessageHistoryStore { _, requestedCursor, _ in
            if requestedCursor == nil {
                initialAttempts += 1
                if initialAttempts == 1 { throw TestFailure.expected }
                return MessageHistoryPage(
                    messages: Self.messages(0..<1, roomID: roomID),
                    nextCursor: cursor
                )
            }
            nextAttempts += 1
            if nextAttempts == 1 { throw TestFailure.expected }
            return MessageHistoryPage(
                messages: Self.messages(1..<2, roomID: roomID),
                nextCursor: nil
            )
        }

        store.activate(roomID: roomID)
        try await Self.waitUntil {
            if case .failed = store.initialState { return true }
            return false
        }
        store.retryInitial()
        try await Self.waitUntil { store.initialState == .loaded && store.olderState == .idle }
        store.loadNextPage()
        try await Self.waitUntil {
            if case .failed = store.olderState { return true }
            return false
        }
        store.retryNextPage()
        try await Self.waitUntil { store.messages.count == 2 && store.olderState == .exhausted }

        XCTAssertEqual(initialAttempts, 2)
        XCTAssertEqual(nextAttempts, 2)
    }

    @MainActor
    func testLongHistoryRendersAtTopAndBottomInLightAndDarkModes() async throws {
        let roomID = UUID()
        let currentUserID = Self.uuid(8_000)
        let friendID = Self.uuid(8_001)
        let messages = (0..<50).map { index in
            Self.message(
                index,
                roomID: roomID,
                senderID: index.isMultiple(of: 2) ? currentUserID : friendID
            )
        }
        let store = MessageHistoryStore { _, _, _ in
            MessageHistoryPage(messages: messages, nextCursor: nil)
        }
        store.activate(roomID: roomID)
        try await Self.waitUntil { store.initialState == .loaded }

        let model = AppModel(preferences: .defaults)
        model.currentUserID = currentUserID
        model.preferences.activeRoomID = roomID
        model.rooms = [
            Room(
                id: roomID,
                name: "긴 기록 테스트",
                ownerID: currentUserID,
                members: [
                    RoomMember(
                        userID: currentUserID,
                        nickname: "나",
                        characterID: PixelCharacterCatalog.pixelHamsterID,
                        presence: .online
                    ),
                    RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "pixel_cat",
                        presence: .online
                    )
                ],
                inviteCodeHint: "ABCD"
            )
        ]

        let snapshotSentinel = "/private/tmp/sidey-history-snapshots"
        let outputDirectory = ProcessInfo.processInfo.environment["SIDEY_HISTORY_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (FileManager.default.fileExists(atPath: snapshotSentinel)
                ? URL(fileURLWithPath: snapshotSentinel, isDirectory: true)
                : nil)
        if let outputDirectory {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        for scheme in [ColorScheme.light, .dark] {
            for scrollToBottom in [false, true] {
                let data = try Self.renderHistory(
                    model: model,
                    store: store,
                    colorScheme: scheme,
                    scrollToBottom: scrollToBottom
                )
                XCTAssertGreaterThan(data.count, 10_000)
                if let outputDirectory {
                    let mode = scheme == .light ? "light" : "dark"
                    let position = scrollToBottom ? "bottom" : "top"
                    try data.write(
                        to: outputDirectory.appending(path: "history-\(mode)-\(position).png")
                    )
                }
            }
        }
        store.deactivate()
    }

    private enum TestFailure: LocalizedError {
        case expected

        var errorDescription: String? { "테스트 오류" }
    }

    private static func databaseRows(count: Int, roomID: UUID) -> [DatabaseMessage] {
        (0..<count).map { index in
            DatabaseMessage(
                id: uuid(index + 1),
                roomID: roomID,
                senderID: uuid(index + 1_000),
                body: "메시지 \(index)",
                createdAt: "2026-08-31T01:02:03.123456Z"
            )
        }
    }

    private static func messages(
        _ indices: Range<Int>,
        roomID: UUID
    ) -> [ChatMessage] {
        indices.map { message($0, roomID: roomID, senderID: uuid(8_000)) }
    }

    private static func message(
        _ index: Int,
        roomID: UUID,
        senderID: UUID
    ) -> ChatMessage {
        ChatMessage(
            id: uuid(index + 1),
            roomID: roomID,
            senderID: senderID,
            body: "메시지 \(index)",
            createdAt: Date(timeIntervalSince1970: 2_000_000_000 + TimeInterval(index))
        )
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw TestFailure.expected }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private static func renderHistory(
        model: AppModel,
        store: MessageHistoryStore,
        colorScheme: ColorScheme,
        scrollToBottom: Bool
    ) throws -> Data {
        let size = HistoryWindowController.contentSize
        let root = OverlayHistoryView(model: model, history: store, onClose: {})
            .environment(\.colorScheme, colorScheme)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        if scrollToBottom,
           let scrollView = descendants(of: NSScrollView.self, in: hostingView)
               .first(where: { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }),
           let documentView = scrollView.documentView {
            scrollView.contentView.scroll(
                to: NSPoint(
                    x: 0,
                    y: max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    private static func descendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        root.subviews.flatMap { subview -> [T] in
            let current = (subview as? T).map { [$0] } ?? []
            return current + descendants(of: type, in: subview)
        }
    }
}
