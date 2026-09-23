import XCTest
@testable import SIDEY

final class RealtimeTransportTests: XCTestCase {
    func testTransportPreferenceRejectsUnknownValues() throws {
        XCTAssertNil(try RealtimeTransportPreference.resolve(nil))
        XCTAssertEqual(try RealtimeTransportPreference.resolve("legacy"), .legacySupabase)
        XCTAssertEqual(try RealtimeTransportPreference.resolve(" firebase-v2 "), .firebaseV2)
        XCTAssertThrowsError(try RealtimeTransportPreference.resolve("automatic"))
    }

    func testMissingConfigurationKeepsLegacyTransport() {
        let selection = RealtimeTransportSelection.resolve(
            requested: nil,
            firebaseV2Allowed: true
        )

        XCTAssertEqual(selection.active, .legacySupabase)
        XCTAssertEqual(selection.fallbackReason, .configurationMissing)
    }

    func testFirebaseBootstrapNotAllowedKeepsLegacyTransport() {
        let selection = RealtimeTransportSelection.resolve(
            requested: .firebaseV2,
            firebaseV2Allowed: false
        )

        XCTAssertEqual(selection.active, .legacySupabase)
        XCTAssertEqual(selection.fallbackReason, .firebaseBootstrapNotAllowed)
    }

    func testRouterPublishesThroughOnlySelectedTransport() async throws {
        let legacy = FakeRealtimeTransport(kind: .legacySupabase)
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { legacy },
            makeFirebaseV2: { firebase }
        )

        try await router.publishTyping(roomID: UUID(), event: "typing_start")

        let legacyOperationCount = await legacy.operationCount
        let firebaseOperationCount = await firebase.operationCount
        let diagnostics = await router.diagnostics()
        XCTAssertEqual(legacyOperationCount, 0)
        XCTAssertEqual(firebaseOperationCount, 1)
        XCTAssertEqual(diagnostics.lastSuccessfulProtocol, .firebaseV2)
    }

    func testRouterForwardsOnlyTheSelectedTransportEventStream() async throws {
        let legacy = FakeRealtimeTransport(kind: .legacySupabase)
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { legacy },
            makeFirebaseV2: { firebase }
        )
        _ = try await router.synchronize(rooms: [], activeRoomID: nil)
        let eventTask = Task {
            var iterator = router.events.makeAsyncIterator()
            return await iterator.next()
        }

        await legacy.emit(.technicalError("legacy"))
        await firebase.emit(.technicalError("firebase"))

        guard case .technicalError(let message) = await eventTask.value else {
            return XCTFail("The selected transport event must be forwarded")
        }
        XCTAssertEqual(message, "firebase")
    }

    func testRouterRoutesEveryOperationAndShutdownExactlyOnce() async throws {
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { FakeRealtimeTransport(kind: .legacySupabase) },
            makeFirebaseV2: { firebase }
        )
        let roomID = UUID()
        let eventID = UUID()

        _ = try await router.synchronize(rooms: [], activeRoomID: nil)
        try await router.setActiveRoom(roomID)
        try await router.setLocalPresence(.away)
        try await router.publishTyping(roomID: roomID, event: "typing_start")
        try await router.publishCharacterPulse(roomID: roomID, eventID: eventID)
        try await router.publishCharacterThrow(
            roomID: roomID,
            eventID: eventID,
            targetUserID: UUID()
        )
        _ = await router.sendChat(roomID: roomID, body: "hello", id: UUID())
        await router.shutdown()

        let operationCount = await firebase.operationCount
        let shutdownCount = await firebase.shutdownCount
        XCTAssertEqual(operationCount, 7)
        XCTAssertEqual(shutdownCount, 1)
    }

    @MainActor
    func testFirebaseMutationRequestsExactGrantBeforeReturningValueAsReady() async throws {
        let revision = try XCTUnwrap(
            RealtimeRevision(rawValue: "00000000000000000042")
        )
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { FakeRealtimeTransport(kind: .legacySupabase) },
            makeFirebaseV2: { firebase }
        )
        var mutationCallCount = 0

        let result = try await RealtimeGrantAwareMutation.perform(
            selection: try await router.currentSelection(),
            requiresEntitlement: true,
            legacy: {
                XCTFail("Firebase selection must not call the legacy mutation")
                return "legacy"
            },
            firebaseV2: {
                mutationCallCount += 1
                return ("firebase", revision)
            },
            converge: { requestedRevision, requiresEntitlement in
                XCTAssertEqual(mutationCallCount, 1)
                try await router.convergeAccessGrant(
                    revision: requestedRevision,
                    requiresEntitlement: requiresEntitlement
                )
            }
        )

        guard case .ready(let value) = result else {
            return XCTFail("Value must not become ready before grant convergence")
        }
        XCTAssertEqual(value, "firebase")
        let requests = await firebase.grantRequests
        XCTAssertEqual(requests, [FakeGrantRequest(
            revision: revision,
            requiresEntitlement: true
        )])
    }

    @MainActor
    func testLegacyMutationKeepsExistingContractAndSkipsV2Grant() async throws {
        let legacySelection = RealtimeTransportSelection.resolve(
            requested: .legacySupabase,
            firebaseV2Allowed: true
        )
        var legacyCallCount = 0
        var firebaseCallCount = 0
        var convergenceCallCount = 0

        let result = try await RealtimeGrantAwareMutation.perform(
            selection: legacySelection,
            requiresEntitlement: false,
            legacy: {
                legacyCallCount += 1
                return "legacy"
            },
            firebaseV2: {
                firebaseCallCount += 1
                return (
                    "firebase",
                    try XCTUnwrap(RealtimeRevision(rawValue: "00000000000000000042"))
                )
            },
            converge: { _, _ in
                convergenceCallCount += 1
            }
        )

        guard case .ready(let value) = result else {
            return XCTFail("Legacy mutation must remain ready without a Firebase grant")
        }
        XCTAssertEqual(value, "legacy")
        XCTAssertEqual(legacyCallCount, 1)
        XCTAssertEqual(firebaseCallCount, 0)
        XCTAssertEqual(convergenceCallCount, 0)
    }

    @MainActor
    func testFirebaseMutationDoesNotReportCommittedValueAsReadyWhenGrantFails() async throws {
        let revision = try XCTUnwrap(
            RealtimeRevision(rawValue: "00000000000000000043")
        )
        var mutationCallCount = 0
        var convergenceCallCount = 0

        let result = try await RealtimeGrantAwareMutation.perform(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            requiresEntitlement: false,
            legacy: {
                XCTFail("Firebase selection must not call the legacy mutation")
                return "legacy"
            },
            firebaseV2: {
                mutationCallCount += 1
                return ("committed", revision)
            },
            converge: { requestedRevision, requiresEntitlement in
                convergenceCallCount += 1
                XCTAssertEqual(requestedRevision, revision)
                XCTAssertFalse(requiresEntitlement)
                throw FakeGrantConvergenceError.failed
            }
        )

        guard case .committedPendingGrant(let value, _) = result else {
            return XCTFail("A committed mutation must remain pending when grant convergence fails")
        }
        XCTAssertEqual(value, "committed")
        XCTAssertEqual(mutationCallCount, 1)
        XCTAssertEqual(convergenceCallCount, 1)
    }

    func testPermissionFailureDoesNotDowngradeToLegacy() async throws {
        let legacy = FakeRealtimeTransport(kind: .legacySupabase)
        let firebase = FakeRealtimeTransport(
            kind: .firebaseV2,
            failure: FakeTransportError.permissionDenied
        )
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { legacy },
            makeFirebaseV2: { firebase }
        )

        do {
            try await router.publishTyping(roomID: UUID(), event: "typing_start")
            XCTFail("Permission denial must remain visible to the selected transport")
        } catch FakeTransportError.permissionDenied {
            // Expected. A permission denial must not be retried through legacy.
        }

        let legacyOperationCount = await legacy.operationCount
        let firebaseOperationCount = await firebase.operationCount
        let diagnostics = await router.diagnostics()
        XCTAssertEqual(legacyOperationCount, 0)
        XCTAssertEqual(firebaseOperationCount, 1)
        XCTAssertEqual(diagnostics.selection.active, .firebaseV2)
        XCTAssertNil(diagnostics.lastSuccessfulProtocol)
    }

    func testRouterRejectsASelectionWithoutItsAdapter() {
        let legacy = FakeRealtimeTransport(kind: .legacySupabase)

        XCTAssertThrowsError(try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { legacy }
        )) { error in
            XCTAssertEqual(
                error as? RoomMessagingTransportRouterError,
                .selectedAdapterUnavailable
            )
        }
    }

    func testRouterConstructsOnlyTheSelectedAdapter() throws {
        let legacyFactory = FakeTransportFactory(kind: .legacySupabase)
        let firebaseFactory = FakeTransportFactory(kind: .firebaseV2)

        _ = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { legacyFactory.make() },
            makeFirebaseV2: { firebaseFactory.make() }
        )

        XCTAssertEqual(legacyFactory.creationCount, 0)
        XCTAssertEqual(firebaseFactory.creationCount, 1)
    }

    func testRouterRejectsAdapterKindMismatch() {
        XCTAssertThrowsError(try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { FakeRealtimeTransport(kind: .legacySupabase) },
            makeFirebaseV2: { FakeRealtimeTransport(kind: .legacySupabase) }
        )) { error in
            XCTAssertEqual(
                error as? RoomMessagingTransportRouterError,
                .selectedAdapterKindMismatch(expected: .firebaseV2, actual: .legacySupabase)
            )
        }
    }

    func testRouterPropagatesSelectedAdapterConstructionFailure() {
        XCTAssertThrowsError(try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { FakeRealtimeTransport(kind: .legacySupabase) },
            makeFirebaseV2: { throw FakeTransportError.permissionDenied }
        )) { error in
            XCTAssertEqual(error as? FakeTransportError, .permissionDenied)
        }
    }

    func testRouterPreservesReconciliationPendingWithoutReportingChatSuccess() async throws {
        let firebase = FakeRealtimeTransport(
            kind: .firebaseV2,
            chatOutcome: .reconciliationPending
        )
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeLegacy: { FakeRealtimeTransport(kind: .legacySupabase) },
            makeFirebaseV2: { firebase }
        )

        let outcome = await router.sendChat(roomID: UUID(), body: "hello", id: UUID())
        let diagnostics = await router.diagnostics()

        XCTAssertEqual(outcome, .reconciliationPending)
        XCTAssertNil(diagnostics.lastSuccessfulProtocol)
    }

    func testKillSwitchCreatesFreshLegacyAdapterOnlyAtTransitionAndCommitsAfterSync() async throws {
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let legacyFactory = FakeTransportFactory(kind: .legacySupabase)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeFirebaseV2: { firebase },
            makeLegacyForSwitch: { legacyFactory.make() }
        )
        let roomID = UUID()
        _ = try await router.synchronize(
            rooms: [Room(id: roomID, name: "친구", ownerID: UUID(), members: [], inviteCodeHint: "TEST")],
            activeRoomID: roomID
        )
        XCTAssertEqual(legacyFactory.creationCount, 0)

        _ = try await router.switchToLegacy()

        XCTAssertEqual(legacyFactory.creationCount, 1)
        let selection = try await router.currentSelection()
        XCTAssertEqual(selection.active, .legacySupabase)
        let retirementCount = await firebase.retirementCount
        XCTAssertEqual(retirementCount, 1)
    }

    func testKillSwitchSyncFailureBlocksAllTransportOperations() async throws {
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let failingLegacy = FakeRealtimeTransport(
            kind: .legacySupabase,
            failure: FakeTransportError.permissionDenied
        )
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeFirebaseV2: { firebase },
            makeLegacyForSwitch: { failingLegacy }
        )
        _ = try await router.synchronize(rooms: [], activeRoomID: nil)

        await assertThrowsAsync(FakeTransportError.permissionDenied) {
            _ = try await router.switchToLegacy()
        }
        await assertThrowsAsync(RoomMessagingTransportRouterError.transportTopologyUnavailable) {
            try await router.publishTyping(roomID: UUID(), event: "typing_start")
        }
        let legacyOperationCount = await failingLegacy.operationCount
        XCTAssertEqual(legacyOperationCount, 1)
    }

    func testBlockedKillSwitchCommitsLegacyOnlyAfterExplicitSynchronizationRetry() async throws {
        let firebase = FakeRealtimeTransport(kind: .firebaseV2)
        let legacy = FakeRealtimeTransport(
            kind: .legacySupabase,
            failure: FakeTransportError.permissionDenied,
            failureCount: 1
        )
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .firebaseV2, firebaseV2Allowed: true),
            makeFirebaseV2: { firebase },
            makeLegacyForSwitch: { legacy }
        )
        let roomID = UUID()
        let rooms = [
            Room(
                id: roomID,
                name: "친구",
                ownerID: UUID(),
                members: [],
                inviteCodeHint: "TEST"
            ),
        ]
        _ = try await router.synchronize(rooms: rooms, activeRoomID: roomID)

        await assertThrowsAsync(FakeTransportError.permissionDenied) {
            _ = try await router.switchToLegacy()
        }
        _ = try await router.synchronize(rooms: rooms, activeRoomID: roomID)

        let selection = try await router.currentSelection()
        XCTAssertEqual(selection.active, .legacySupabase)
        try await router.publishTyping(roomID: roomID, event: "typing_start")
        let legacyOperationCount = await legacy.operationCount
        XCTAssertEqual(legacyOperationCount, 3)
    }

    @MainActor
    func testReconciliationPendingKeepsTheOriginalUUIDPending() async throws {
        let roomID = UUID()
        let userID = UUID()
        let coordinator = AppCoordinator(
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none,
            keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .appStore,
            arguments: []
        )
        coordinator.model.currentUserID = userID
        coordinator.model.rooms = [
            Room(id: roomID, name: "친구", ownerID: userID, members: [], inviteCodeHint: "TEST")
        ]
        coordinator.model.preferences.activeRoomID = roomID
        let classified = expectation(description: "chat outcome classified")
        var submittedID: UUID?

        coordinator.sendMessage("확인 중", source: .history) { room, _, id -> RealtimeChatOutcome in
            XCTAssertEqual(room, roomID)
            submittedID = id
            classified.fulfill()
            return .reconciliationPending
        }

        await fulfillment(of: [classified], timeout: 2)
        for _ in 0..<10 { await Task.yield() }
        let pending = try XCTUnwrap(coordinator.model.messageOutbox.entries.first)
        XCTAssertEqual(pending.id, submittedID)
        XCTAssertEqual(pending.roomID, roomID)
        XCTAssertEqual(pending.state, .pending)
        XCTAssertNil(coordinator.model.historySendError)
        XCTAssertFalse(coordinator.overlayWindows.composerVisible)
    }

    @MainActor
    func testDisconnectedProductionSendDoesNotStageOrCallTransport() async throws {
        let transport = FakeRealtimeTransport(kind: .legacySupabase)
        let router = try RoomMessagingTransportRouter(
            selection: .resolve(requested: .legacySupabase, firebaseV2Allowed: true),
            makeLegacy: { transport }
        )
        let roomID = UUID()
        let userID = UUID()
        let coordinator = AppCoordinator(
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none,
            keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .appStore,
            arguments: []
        )
        coordinator.messagingTransport = router
        coordinator.model.currentUserID = userID
        coordinator.model.rooms = [
            Room(id: roomID, name: "친구", ownerID: userID, members: [], inviteCodeHint: "TEST")
        ]
        coordinator.model.preferences.activeRoomID = roomID
        coordinator.model.connectionState = .connecting
        coordinator.model.setActiveRoomRealtimeConnected(false)

        coordinator.sendMessage("로컬에만 보이면 안 됨", source: .history)

        let operationCount = await transport.operationCount
        XCTAssertEqual(operationCount, 0)
        XCTAssertTrue(coordinator.model.messageOutbox.entries.isEmpty)
        XCTAssertNotNil(coordinator.model.historySendError)
    }
}

private func assertThrowsAsync<E: Error & Equatable>(
    _ expected: E,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? E, expected, file: file, line: line)
    }
}

private final class FakeTransportFactory: @unchecked Sendable {
    private let kind: RealtimeTransportKind
    private let lock = NSLock()
    private var storedCreationCount = 0

    var creationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCreationCount
    }

    init(kind: RealtimeTransportKind) {
        self.kind = kind
    }

    func make() -> FakeRealtimeTransport {
        lock.lock()
        storedCreationCount += 1
        lock.unlock()
        return FakeRealtimeTransport(kind: kind)
    }
}

private enum FakeTransportError: Error {
    case permissionDenied
}

private enum FakeGrantConvergenceError: Error {
    case failed
}

private struct FakeGrantRequest: Equatable, Sendable {
    let revision: RealtimeRevision
    let requiresEntitlement: Bool
}

private actor FakeRealtimeTransport: RoomMessagingTransport {
    nonisolated let kind: RealtimeTransportKind
    nonisolated let events: AsyncStream<BackendEvent>

    private let failure: (any Error)?
    private var remainingFailureCount: Int
    private let chatOutcome: RealtimeChatOutcome?
    private let eventContinuation: AsyncStream<BackendEvent>.Continuation
    private(set) var operationCount = 0
    private(set) var shutdownCount = 0
    private(set) var retirementCount = 0
    private(set) var grantRequests: [FakeGrantRequest] = []

    init(
        kind: RealtimeTransportKind,
        failure: (any Error)? = nil,
        failureCount: Int = .max,
        chatOutcome: RealtimeChatOutcome? = nil
    ) {
        self.kind = kind
        self.failure = failure
        self.remainingFailureCount = failure == nil ? 0 : failureCount
        self.chatOutcome = chatOutcome
        let pair = AsyncStream<BackendEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.events = pair.stream
        self.eventContinuation = pair.continuation
    }

    func synchronize(rooms: [Room], activeRoomID: UUID?) async throws -> BackendReconciliation {
        try recordOperation()
        return BackendReconciliation(
            snapshot: BackendSnapshot(profile: nil, rooms: rooms),
            activeRoomID: activeRoomID,
            activeMessages: []
        )
    }

    func setActiveRoom(_ roomID: UUID?) async throws { try recordOperation() }
    func setLocalPresence(_ state: PresenceState) async throws { try recordOperation() }
    func publishTyping(roomID: UUID, event: String) async throws { try recordOperation() }
    func publishCharacterPulse(roomID: UUID, eventID: UUID) async throws { try recordOperation() }
    func publishCharacterThrow(roomID: UUID, eventID: UUID, targetUserID: UUID) async throws {
        try recordOperation()
    }
    func convergeAccessGrant(
        revision: RealtimeRevision,
        requiresEntitlement: Bool
    ) async throws {
        try recordOperation()
        grantRequests.append(FakeGrantRequest(
            revision: revision,
            requiresEntitlement: requiresEntitlement
        ))
    }
    func sendChat(roomID: UUID, body: String, id: UUID) async -> RealtimeChatOutcome {
        do {
            try recordOperation()
            return chatOutcome ?? .confirmed(ChatMessage(
                id: id,
                roomID: roomID,
                senderID: UUID(),
                body: body,
                createdAt: .now
            ))
        } catch {
            return .definitelyRejected(message: error.localizedDescription)
        }
    }
    func shutdown() async {
        shutdownCount += 1
        eventContinuation.finish()
    }

    func retireForTransportSwitch() async {
        retirementCount += 1
        eventContinuation.finish()
    }

    func emit(_ event: BackendEvent) {
        eventContinuation.yield(event)
    }

    private func recordOperation() throws {
        operationCount += 1
        if let failure, remainingFailureCount > 0 {
            remainingFailureCount -= 1
            throw failure
        }
    }
}
