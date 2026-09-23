import Foundation
import OSLog

enum RealtimeTransportKind: String, Equatable, Sendable {
    case legacySupabase = "legacy"
    case firebaseV2 = "firebase-v2"
}

enum RealtimeTransportConfigurationError: Error, Equatable {
    case unsupportedValue
}

enum RealtimeTransportPreference {
    static func resolve(_ rawValue: String?) throws -> RealtimeTransportKind? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        guard let kind = RealtimeTransportKind(rawValue: normalized) else {
            throw RealtimeTransportConfigurationError.unsupportedValue
        }
        return kind
    }
}

enum RealtimeTransportFallbackReason: String, Equatable, Sendable {
    case configurationMissing
    case firebaseBootstrapNotAllowed
}

struct RealtimeRolloutLeaseStatus: Equatable, Sendable {
    let refreshIn: Duration
    let expiresIn: Duration
}

struct RealtimeTransportSelection: Equatable, Sendable {
    let requested: RealtimeTransportKind?
    let active: RealtimeTransportKind
    let fallbackReason: RealtimeTransportFallbackReason?

    /// Resolves startup policy before any adapter operation begins.
    /// `firebaseV2Allowed` is a rollout/contract gate, never a network-health signal.
    static func resolve(
        requested: RealtimeTransportKind?,
        firebaseV2Allowed: Bool
    ) -> Self {
        guard let requested else {
            return Self(
                requested: nil,
                active: .legacySupabase,
                fallbackReason: .configurationMissing
            )
        }
        guard requested == .firebaseV2 else {
            return Self(requested: requested, active: .legacySupabase, fallbackReason: nil)
        }
        guard firebaseV2Allowed else {
            return Self(
                requested: requested,
                active: .legacySupabase,
                fallbackReason: .firebaseBootstrapNotAllowed
            )
        }
        return Self(requested: requested, active: .firebaseV2, fallbackReason: nil)
    }
}

struct RealtimeTransportDiagnostics: Equatable, Sendable {
    let selection: RealtimeTransportSelection
    let lastSuccessfulProtocol: RealtimeTransportKind?
}

/// The authoritative outcome of one chat UUID submission.
///
/// Firebase v2 adapters must translate transport failures whose commit state is
/// unknown to `reconciliationPending`. The coordinator intentionally keeps the
/// existing pending outbox entry for that UUID and never resends it
/// automatically. Only a server response that proves rejection may use
/// `definitelyRejected`.
enum RealtimeChatOutcome: Equatable, Sendable {
    case confirmed(ChatMessage)
    case definitelyRejected(message: String)
    case reconciliationPending
}

enum RoomMessagingTransportRouterError: Error, Equatable {
    case selectedAdapterUnavailable
    case legacyAdapterUnavailable
    case transportTopologyUnavailable
    case selectedAdapterKindMismatch(
        expected: RealtimeTransportKind,
        actual: RealtimeTransportKind
    )
}

/// Application-facing composite realtime boundary.
///
/// A Firebase v2 implementation must keep Supabase Presence and authoritative
/// reconciliation, merge their domain events with Firebase delivery events,
/// and expose only that single merged stream. When Firebase v2 is selected,
/// typing, pulse, and throw publish and receive only through compact RTDB;
/// legacy Supabase transient mirrors are ignored. The legacy adapter resumes
/// Supabase transient ownership only after an explicit selector rollback.
protocol RoomMessagingTransport: Actor {
    nonisolated var kind: RealtimeTransportKind { get }
    nonisolated var events: AsyncStream<BackendEvent> { get }

    func synchronize(rooms: [Room], activeRoomID: UUID?) async throws -> BackendReconciliation
    func setActiveRoom(_ roomID: UUID?) async throws
    func setLocalPresence(_ state: PresenceState) async throws
    func publishTyping(roomID: UUID, event: String) async throws
    func publishCharacterPulse(roomID: UUID, eventID: UUID) async throws
    func publishCharacterThrow(roomID: UUID, eventID: UUID, targetUserID: UUID) async throws
    func convergeAccessGrant(
        revision: RealtimeRevision,
        requiresEntitlement: Bool
    ) async throws
    func rolloutLeaseStatus() -> RealtimeRolloutLeaseStatus?
    func refreshRolloutLease() async throws
    func failClosedForRolloutLease() async
    func sendChat(roomID: UUID, body: String, id: UUID) async -> RealtimeChatOutcome
    func retireForTransportSwitch() async
    func shutdown() async
}

extension RoomMessagingTransport {
    /// Legacy Supabase transport has no separate Firebase credential grant.
    func convergeAccessGrant(
        revision: RealtimeRevision,
        requiresEntitlement: Bool
    ) async throws {}

    func rolloutLeaseStatus() -> RealtimeRolloutLeaseStatus? { nil }

    func refreshRolloutLease() async throws {}

    func failClosedForRolloutLease() async {}

    func retireForTransportSwitch() async {}
}

enum RealtimeGrantAwareMutationResult<Value> {
    case ready(Value)
    case committedPendingGrant(value: Value, error: any Error)

    var value: Value {
        switch self {
        case .ready(let value), .committedPendingGrant(let value, _):
            value
        }
    }

    var grantError: (any Error)? {
        guard case .committedPendingGrant(_, let error) = self else { return nil }
        return error
    }
}

enum RealtimeGrantAwareMutation {
    /// Runs exactly one mutation contract. A Firebase v2 value is not returned
    /// as ready until its exact access revision has been requested and
    /// acknowledged by the selected transport. A convergence failure is kept
    /// distinct from a mutation failure because the server write is committed.
    @MainActor
    static func perform<Value>(
        selection: RealtimeTransportSelection,
        requiresEntitlement: Bool,
        legacy: () async throws -> Value,
        firebaseV2: () async throws -> (value: Value, revision: RealtimeRevision),
        converge: (RealtimeRevision, Bool) async throws -> Void
    ) async throws -> RealtimeGrantAwareMutationResult<Value> {
        guard selection.active == .firebaseV2 else {
            return .ready(try await legacy())
        }
        let grant = try await firebaseV2()
        do {
            try await converge(grant.revision, requiresEntitlement)
            return .ready(grant.value)
        } catch {
            return .committedPendingGrant(value: grant.value, error: error)
        }
    }
}

actor RoomMessagingTransportRouter {
    private enum OperationalState: Equatable {
        case running
        case switching
        case blocked
    }

    nonisolated let events: AsyncStream<BackendEvent>

    private let eventContinuation: AsyncStream<BackendEvent>.Continuation
    private var selection: RealtimeTransportSelection
    private var transport: any RoomMessagingTransport
    private let makeLegacyForSwitch: (@Sendable () async throws -> any RoomMessagingTransport)?
    private let shutdownShared: (@Sendable () async -> Void)?
    private let logger = Logger(subsystem: "app.sidey.desktop", category: "RealtimeTransport")
    private var lastSuccessfulProtocol: RealtimeTransportKind?
    private var eventTask: Task<Void, Never>?
    private var eventGeneration: UInt64 = 0
    private var synchronizedRooms: [Room]?
    private var synchronizedActiveRoomID: UUID?
    private var isShutDown = false
    private var operationalState: OperationalState = .running
    private var blockedLegacyTransport: (any RoomMessagingTransport)?

    init(
        selection: RealtimeTransportSelection,
        makeLegacy: (@Sendable () throws -> any RoomMessagingTransport)? = nil,
        makeFirebaseV2: (@Sendable () throws -> any RoomMessagingTransport)? = nil,
        makeLegacyForSwitch: (@Sendable () async throws -> any RoomMessagingTransport)? = nil,
        shutdownShared: (@Sendable () async -> Void)? = nil
    ) throws {
        self.selection = selection
        let selectedTransport: any RoomMessagingTransport
        if selection.active == .firebaseV2 {
            guard let makeFirebaseV2 else {
                throw RoomMessagingTransportRouterError.selectedAdapterUnavailable
            }
            selectedTransport = try makeFirebaseV2()
        } else {
            guard let makeLegacy else {
                throw RoomMessagingTransportRouterError.selectedAdapterUnavailable
            }
            selectedTransport = try makeLegacy()
        }
        guard selectedTransport.kind == selection.active else {
            throw RoomMessagingTransportRouterError.selectedAdapterKindMismatch(
                expected: selection.active,
                actual: selectedTransport.kind
            )
        }
        self.transport = selectedTransport
        self.makeLegacyForSwitch = makeLegacyForSwitch
        self.shutdownShared = shutdownShared
        let pair = AsyncStream<BackendEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = pair.stream
        self.eventContinuation = pair.continuation
        let fallback = selection.fallbackReason?.rawValue ?? "none"
        logger.info(
            "Selected realtime protocol: \(selection.active.rawValue, privacy: .public), fallback: \(fallback, privacy: .public)"
        )
    }

    func currentSelection() throws -> RealtimeTransportSelection {
        guard operationalState == .running, !isShutDown else {
            throw RoomMessagingTransportRouterError.transportTopologyUnavailable
        }
        return selection
    }

    func diagnostics() -> RealtimeTransportDiagnostics {
        RealtimeTransportDiagnostics(
            selection: selection,
            lastSuccessfulProtocol: lastSuccessfulProtocol
        )
    }

    func synchronize(rooms: [Room], activeRoomID: UUID?) async throws -> BackendReconciliation {
        if operationalState == .blocked, let blockedLegacyTransport {
            return try await finishLegacySwitch(
                blockedLegacyTransport,
                rooms: rooms,
                activeRoomID: activeRoomID
            )
        }
        try requireRunning()
        startEventForwardingIfNeeded()
        let reconciliation = try await transport.synchronize(
            rooms: rooms,
            activeRoomID: activeRoomID
        )
        synchronizedRooms = reconciliation.snapshot.rooms
        synchronizedActiveRoomID = reconciliation.activeRoomID
        recordSuccess(operation: "synchronize")
        return reconciliation
    }

    func setActiveRoom(_ roomID: UUID?) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.setActiveRoom(roomID)
        synchronizedActiveRoomID = roomID
        recordSuccess(operation: "set-active-room")
    }

    func setLocalPresence(_ state: PresenceState) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.setLocalPresence(state)
        recordSuccess(operation: "presence")
    }

    func publishTyping(roomID: UUID, event: String) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.publishTyping(roomID: roomID, event: event)
        recordSuccess(operation: "typing")
    }

    func publishCharacterPulse(roomID: UUID, eventID: UUID) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.publishCharacterPulse(roomID: roomID, eventID: eventID)
        recordSuccess(operation: "pulse")
    }

    func publishCharacterThrow(roomID: UUID, eventID: UUID, targetUserID: UUID) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.publishCharacterThrow(
            roomID: roomID,
            eventID: eventID,
            targetUserID: targetUserID
        )
        recordSuccess(operation: "throw")
    }

    func convergeAccessGrant(
        revision: RealtimeRevision,
        requiresEntitlement: Bool
    ) async throws {
        try requireRunning()
        startEventForwardingIfNeeded()
        try await transport.convergeAccessGrant(
            revision: revision,
            requiresEntitlement: requiresEntitlement
        )
        recordSuccess(operation: "grant")
    }

    func rolloutLeaseStatus() async throws -> RealtimeRolloutLeaseStatus? {
        try requireRunning()
        return await transport.rolloutLeaseStatus()
    }

    func refreshRolloutLease() async throws {
        try requireRunning()
        guard selection.active == .firebaseV2 else { return }
        try await transport.refreshRolloutLease()
        recordSuccess(operation: "rollout-lease-refresh")
    }

    func failClosedForRolloutLease() async {
        guard !isShutDown, selection.active == .firebaseV2 else { return }
        await transport.failClosedForRolloutLease()
    }

    func sendChat(roomID: UUID, body: String, id: UUID) async -> RealtimeChatOutcome {
        do {
            try requireRunning()
        } catch {
            return .definitelyRejected(message: error.localizedDescription)
        }
        startEventForwardingIfNeeded()
        let result = await transport.sendChat(roomID: roomID, body: body, id: id)
        if case .confirmed = result {
            recordSuccess(operation: "chat")
        }
        return result
    }

    /// Applies an explicit remote kill-switch without rebuilding the shared
    /// Supabase session/socket. Firebase listeners and Auth retire first; only
    /// then is the legacy adapter synchronized to the last authoritative state.
    @discardableResult
    func switchToLegacy() async throws -> BackendReconciliation? {
        guard selection.active == .firebaseV2 else { return nil }
        guard let makeLegacyForSwitch else {
            throw RoomMessagingTransportRouterError.legacyAdapterUnavailable
        }
        guard let synchronizedRooms else {
            throw RoomMessagingTransportRouterError.transportTopologyUnavailable
        }

        operationalState = .switching
        await transport.retireForTransportSwitch()
        stopEventForwarding()
        let legacyTransport: any RoomMessagingTransport
        do {
            legacyTransport = try await makeLegacyForSwitch()
        } catch {
            operationalState = .blocked
            eventContinuation.yield(.technicalError(
                L10n.text("realtime.kill_switch.error.legacy_connection_creation_failed")
            ))
            throw error
        }
        guard legacyTransport.kind == .legacySupabase else {
            operationalState = .blocked
            throw RoomMessagingTransportRouterError.selectedAdapterKindMismatch(
                expected: .legacySupabase,
                actual: legacyTransport.kind
            )
        }
        do {
            return try await finishLegacySwitch(
                legacyTransport,
                rooms: synchronizedRooms,
                activeRoomID: synchronizedActiveRoomID
            )
        } catch {
            blockedLegacyTransport = legacyTransport
            operationalState = .blocked
            eventContinuation.yield(.technicalError(
                L10n.text("realtime.kill_switch.error.legacy_connection_recovery_failed")
            ))
            throw error
        }
    }

    private func finishLegacySwitch(
        _ legacyTransport: any RoomMessagingTransport,
        rooms: [Room],
        activeRoomID: UUID?
    ) async throws -> BackendReconciliation {
        let reconciliation = try await legacyTransport.synchronize(
            rooms: rooms,
            activeRoomID: activeRoomID
        )
        transport = legacyTransport
        selection = RealtimeTransportSelection.resolve(
            requested: .legacySupabase,
            firebaseV2Allowed: false
        )
        synchronizedRooms = reconciliation.snapshot.rooms
        synchronizedActiveRoomID = reconciliation.activeRoomID
        blockedLegacyTransport = nil
        operationalState = .running
        startEventForwardingIfNeeded()
        recordSuccess(operation: "kill-switch-to-legacy")
        eventContinuation.yield(.reconciliation(reconciliation))
        return reconciliation
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        stopEventForwarding()
        await transport.retireForTransportSwitch()
        if let shutdownShared {
            await shutdownShared()
        } else {
            await transport.shutdown()
        }
        eventContinuation.finish()
    }

    private func startEventForwardingIfNeeded() {
        guard eventTask == nil, !isShutDown else { return }
        eventGeneration &+= 1
        let generation = eventGeneration
        let stream = transport.events
        eventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.forward(event, generation: generation)
            }
        }
    }

    private func stopEventForwarding() {
        eventGeneration &+= 1
        eventTask?.cancel()
        eventTask = nil
    }

    private func forward(_ event: BackendEvent, generation: UInt64) {
        guard generation == eventGeneration, !isShutDown else { return }
        eventContinuation.yield(event)
    }

    private func requireRunning() throws {
        guard operationalState == .running, !isShutDown else {
            throw RoomMessagingTransportRouterError.transportTopologyUnavailable
        }
    }

    private func recordSuccess(operation: String) {
        lastSuccessfulProtocol = transport.kind
        let protocolName = transport.kind.rawValue
        logger.debug(
            "Realtime operation succeeded: \(operation, privacy: .public), protocol: \(protocolName, privacy: .public)"
        )
    }
}

extension SideyBackend: RoomMessagingTransport {
    nonisolated var kind: RealtimeTransportKind { .legacySupabase }

    func synchronize(
        rooms: [Room],
        activeRoomID: UUID?
    ) async throws -> BackendReconciliation {
        try await syncRealtime(rooms: rooms, activeRoomID: activeRoomID)
    }

    func publishTyping(roomID: UUID, event: String) async throws {
        try await broadcastTyping(roomID: roomID, event: event)
    }

    func publishCharacterPulse(roomID: UUID, eventID: UUID) async throws {
        try await broadcastCharacterPulse(roomID: roomID, eventID: eventID)
    }

    func publishCharacterThrow(
        roomID: UUID,
        eventID: UUID,
        targetUserID: UUID
    ) async throws {
        try await broadcastCharacterThrow(
            roomID: roomID,
            eventID: eventID,
            targetUserID: targetUserID
        )
    }

    func sendChat(roomID: UUID, body: String, id: UUID) async -> RealtimeChatOutcome {
        do {
            return .confirmed(try await sendMessage(roomID: roomID, body: body, id: id))
        } catch {
            // Preserve the legacy adapter's existing terminal-failure behavior.
            // Firebase v2 owns the stricter ambiguous-commit classification.
            return .definitelyRejected(message: error.localizedDescription)
        }
    }
}
