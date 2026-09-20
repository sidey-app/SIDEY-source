import AppKit
import SwiftUI
import XCTest
@testable import SIDEYAppStore

@MainActor
final class HistoryInteractionTests: XCTestCase {
    private let roomID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let friendID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testRoomSwitchDoesNotConsumeSharedDraftOrStartTyping() {
        let model = makeModel()
        model.draft = "한글🙂\n둘째 줄"
        model.groupOperation = .switching(UUID())
        XCTAssertFalse(model.canSubmitDraft)
        XCTAssertNil(model.acceptDraft())
        XCTAssertEqual(model.draft, "한글🙂\n둘째 줄")
        XCTAssertFalse(model.updateTypingInput(active: true, source: .history))
        model.groupOperation = .idle
        XCTAssertEqual(model.acceptDraft(), "한글🙂\n둘째 줄")
        XCTAssertEqual(model.draft, "")
    }

    func testDelayedFocusLossFromOverlayCannotStopNewHistoryEditing() {
        let model = makeModel()
        XCTAssertTrue(model.updateTypingInput(active: true, source: .overlay))
        XCTAssertTrue(model.updateTypingInput(active: true, source: .history))
        XCTAssertFalse(model.updateTypingInput(active: false, source: .overlay))
        XCTAssertEqual(model.typingInputSource, .history)
        XCTAssertTrue(model.updateTypingInput(active: false, source: .history))
        XCTAssertNil(model.typingInputSource)
        XCTAssertFalse(model.updateTypingInput(active: false, source: .history))
    }

    func testInitialBottomIncomingAppendAndOlderPrependPreservePartialCard() throws {
        let view = makeScrollView()
        let initial = (10..<30).map { item($0, senderID: friendID) }
        update(view, items: initial)
        XCTAssertTrue(view.isAtBottom)
        let anchorID = initial[4].entry.id
        let originalFrame = try XCTUnwrap(view.frameForMessage(anchorID))
        view.contentView.scroll(to: NSPoint(x: 0, y: originalFrame.minY + 17))
        view.reflectScrolledClipView(view.contentView)
        let beforeAppend = view.contentView.bounds.minY

        update(view, items: initial + [item(30, senderID: friendID)])
        XCTAssertEqual(view.contentView.bounds.minY, beforeAppend, accuracy: 0.5)
        XCTAssertFalse(view.isAtBottom)

        // Older messages from this user are pagination, never a new local send.
        update(view, items: (0..<10).map { item($0, senderID: userID) }
               + initial + [item(30, senderID: friendID)])
        let movedFrame = try XCTUnwrap(view.frameForMessage(anchorID))
        XCTAssertEqual(view.contentView.bounds.minY - movedFrame.minY, 17, accuracy: 0.5)
        XCTAssertFalse(view.isAtBottom)

        update(view, items: (0..<10).map { item($0, senderID: userID) }
               + initial + [item(30, senderID: friendID), item(31, senderID: userID)])
        XCTAssertTrue(view.isAtBottom, "A new local send returns the timeline to the bottom")
    }

    func testUpdatedMessageRemeasuresItsCardAndPreservesReadingPosition() throws {
        let view = makeScrollView()
        var messages = (0..<20).map { item($0, senderID: friendID) }
        update(view, items: messages)
        let anchorID = messages[8].entry.id
        let anchor = try XCTUnwrap(view.frameForMessage(anchorID))
        view.contentView.scroll(to: NSPoint(x: 0, y: anchor.minY + 17))
        let originalHeight = try XCTUnwrap(view.frameForMessage(messages[0].entry.id)).height
        var failedEntry = messages[0].entry
        failedEntry.body = String(repeating: "길어진 내용 ", count: 25)
        failedEntry.state = .failed
        messages[0] = HistoryTimelineItem(entry: failedEntry, participant: messages[0].participant)
        update(view, items: messages)
        XCTAssertGreaterThan(try XCTUnwrap(view.frameForMessage(failedEntry.id)).height, originalHeight)
        let movedAnchor = try XCTUnwrap(view.frameForMessage(anchorID))
        XCTAssertEqual(view.contentView.bounds.minY - movedAnchor.minY, 17, accuracy: 0.5)
    }

    func testWidthChangeReflowsCachedCardsWithoutLosingPartialCardPosition() throws {
        let view = makeScrollView()
        let messages = (0..<20).map { index in
            let original = item(index, senderID: friendID)
            var entry = original.entry
            entry.body = String(repeating: "긴 문장🙂 ", count: 30)
            return HistoryTimelineItem(entry: entry, participant: original.participant)
        }
        update(view, items: messages)
        let anchorID = messages[4].entry.id
        let originalFrame = try XCTUnwrap(view.frameForMessage(anchorID))
        view.contentView.scroll(to: NSPoint(x: 0, y: originalFrame.minY + 17))
        view.setFrameSize(NSSize(width: 320, height: 240))
        view.layoutSubtreeIfNeeded()
        let resizedFrame = try XCTUnwrap(view.frameForMessage(anchorID))
        XCTAssertGreaterThan(resizedFrame.height, originalFrame.height)
        XCTAssertEqual(view.contentView.bounds.minY - resizedFrame.minY, 17, accuracy: 0.5)
    }

    func testNewLocalPendingSendScrollsToBottomWhenDeviceClockIsBehindServer() throws {
        let view = makeScrollView()
        let messages = (10..<30).map { item($0, senderID: friendID) }
        update(view, items: messages)
        let anchor = try XCTUnwrap(view.frameForMessage(messages[3].entry.id))
        view.contentView.scroll(to: NSPoint(x: 0, y: anchor.minY + 17))
        XCTAssertFalse(view.isAtBottom)
        let original = item(1, senderID: userID)
        var pending = original.entry
        pending.state = .pending
        update(view, items: [HistoryTimelineItem(entry: pending, participant: original.participant)] + messages)
        XCTAssertTrue(view.isAtBottom)
    }

    func testIncomingAppendFollowsWhenAlreadyAtBottom() {
        let view = makeScrollView()
        let initial = (0..<20).map { item($0, senderID: friendID) }
        update(view, items: initial)
        update(view, items: initial + [item(20, senderID: friendID)])
        XCTAssertTrue(view.isAtBottom)
    }

    func testHistorySendSuccessKeepsComposerClosedAndConfirmsOutbox() async throws {
        let coordinator = makeCoordinator()
        let model = coordinator.model
        configure(model)
        model.draft = "공유 초안🙂"
        let body = try XCTUnwrap(model.acceptDraft())
        let sent = expectation(description: "history send completed")
        coordinator.sendMessage(body, source: .history) { [roomID, userID] room, body, id in
            XCTAssertEqual(room, roomID)
            defer { sent.fulfill() }
            return ChatMessage(id: id, roomID: room, senderID: userID, body: body, createdAt: .now)
        }
        await fulfillment(of: [sent], timeout: 2)
        try await waitUntil { model.messageOutbox.entries.isEmpty }
        XCTAssertEqual(model.messageLedger.entries.last?.body, body)
        XCTAssertFalse(coordinator.overlayWindows.composerVisible)
        XCTAssertNil(model.historySendError)
        XCTAssertEqual(model.draft, "")
    }

    func testHistorySendFailureStaysInHistoryAndDoesNotOverwriteNextDraft() async throws {
        let coordinator = makeCoordinator()
        let model = coordinator.model
        configure(model)
        coordinator.sendMessage("전송할 내용", source: .history) { _, _, _ in
            throw SendFailure()
        }
        model.draft = "다음에 쓸 내용"
        try await waitUntil { model.historySendError != nil }
        XCTAssertFalse(coordinator.overlayWindows.composerVisible)
        XCTAssertEqual(model.messageOutbox.entries.count, 1)
        XCTAssertEqual(model.messageOutbox.entries.first?.state, .failed)
        XCTAssertEqual(model.draft, "다음에 쓸 내용")
    }

    func testLateHistoryFailureDuringSwitchStaysWithOriginalRoom() async throws {
        let coordinator = makeCoordinator()
        configure(coordinator.model)
        let (gate, release) = AsyncStream<Void>.makeStream()
        let started = expectation(description: "sender started")
        coordinator.sendMessage("이전 방 메시지", source: .history) { _, _, _ in
            started.fulfill()
            for await _ in gate { break }
            throw SendFailure()
        }
        await fulfillment(of: [started], timeout: 2)
        coordinator.model.groupOperation = .switching(UUID())
        coordinator.model.draft = "새 방 초안"
        release.yield(())
        release.finish()
        try await waitUntil { coordinator.model.messageOutbox.entries.first?.state == .failed }
        XCTAssertEqual(coordinator.model.messageOutbox.entries.first?.roomID, roomID)
        XCTAssertNil(coordinator.model.historySendError)
        XCTAssertEqual(coordinator.model.draft, "새 방 초안")
        XCTAssertFalse(coordinator.overlayWindows.composerVisible)
    }

    func testMessageStartedInQuietModeDoesNotReplayBubbleAfterQuietModeEnds() async throws {
        let coordinator = makeCoordinator()
        configure(coordinator.model)
        coordinator.model.preferences.quietModeEnabled = true
        let (gate, release) = AsyncStream<Void>.makeStream()
        let started = expectation(description: "sender started")
        coordinator.sendMessage("조용히 보낸 메시지", source: .history) { [userID] room, body, id in
            started.fulfill()
            for await _ in gate { break }
            return ChatMessage(id: id, roomID: room, senderID: userID, body: body, createdAt: .now)
        }
        await fulfillment(of: [started], timeout: 2)
        coordinator.model.preferences.quietModeEnabled = false
        release.yield(())
        release.finish()
        try await waitUntil { coordinator.model.messageOutbox.entries.isEmpty }
        XCTAssertEqual(coordinator.model.messageLedger.entries.count, 1)
        XCTAssertTrue(coordinator.model.activeBubbles.isEmpty)
    }

    func testHistoryTransportBoundaryRejectsSwitchWithoutCallingSender() {
        let coordinator = makeCoordinator()
        configure(coordinator.model)
        coordinator.model.groupOperation = .switching(UUID())
        coordinator.sendMessage("유지할 내용", source: .history) { _, _, _ in
            XCTFail("Room switch must block the transport")
            throw SendFailure()
        }
        XCTAssertEqual(coordinator.model.draft, "유지할 내용")
        XCTAssertNotNil(coordinator.model.historySendError)
        XCTAssertTrue(coordinator.model.messageOutbox.entries.isEmpty)
        XCTAssertFalse(coordinator.overlayWindows.composerVisible)
    }

    private func makeModel() -> AppModel {
        let model = AppModel(preferences: .defaults)
        configure(model)
        return model
    }

    private func configure(_ model: AppModel) {
        model.currentUserID = userID
        model.rooms = [Room(id: roomID, name: "친구", ownerID: userID, members: [], inviteCodeHint: "TEST")]
        model.preferences.activeRoomID = roomID
    }

    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
                       legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
                       releaseChannel: .appStore, arguments: [])
    }

    private func item(_ index: Int, senderID: UUID) -> HistoryTimelineItem {
        HistoryTimelineItem(
            entry: MessageLedgerEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%012X", index))!,
                roomID: roomID, senderID: senderID, body: "메시지 \(index)\n둘째 줄",
                createdAt: Date(timeIntervalSince1970: 2_000_000_000 + Double(index)), state: .confirmed),
            participant: MessageHistoryParticipant(nickname: "친구", characterID: "pixel_hamster",
                                                   isCurrentUser: senderID == userID)
        )
    }

    private func makeScrollView() -> HistoryTimelineScrollView {
        let view = HistoryTimelineScrollView(frame: CGRect(x: 0, y: 0, width: 500, height: 240))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func update(_ view: HistoryTimelineScrollView, items: [HistoryTimelineItem]) {
        view.update(items: items, currentUserID: userID, olderState: .exhausted,
                    header: AnyView(Text("기록 시작").frame(height: 24)), onLoadOlder: {})
        view.layoutSubtreeIfNeeded()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else { throw SendFailure() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct SendFailure: Error {}
}
