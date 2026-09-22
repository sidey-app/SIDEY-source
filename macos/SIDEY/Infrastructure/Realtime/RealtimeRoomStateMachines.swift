import Foundation

struct RealtimeRoomOperation: Equatable, Sendable {
    fileprivate let generation: UInt64
    let roomID: UUID?
}

struct RealtimeActiveRoomState: Equatable, Sendable {
    private(set) var desiredActiveRoomID: UUID?
    private(set) var committedRealtimeActiveRoomID: UUID?
    private var generation: UInt64 = 0

    mutating func request(_ roomID: UUID?) -> RealtimeRoomOperation {
        generation &+= 1
        desiredActiveRoomID = roomID
        return RealtimeRoomOperation(generation: generation, roomID: roomID)
    }

    @discardableResult
    mutating func commit(_ operation: RealtimeRoomOperation) -> Bool {
        guard operation.generation == generation,
              operation.roomID == desiredActiveRoomID
        else { return false }
        committedRealtimeActiveRoomID = operation.roomID
        return true
    }

    mutating func invalidateAll() {
        generation &+= 1
        desiredActiveRoomID = nil
        committedRealtimeActiveRoomID = nil
    }

    @discardableResult
    mutating func invalidate(roomID: UUID) -> Bool {
        guard desiredActiveRoomID == roomID || committedRealtimeActiveRoomID == roomID else {
            return false
        }
        generation &+= 1
        if desiredActiveRoomID == roomID { desiredActiveRoomID = nil }
        if committedRealtimeActiveRoomID == roomID { committedRealtimeActiveRoomID = nil }
        return true
    }
}

struct RealtimeListenerIdentity: Equatable, Sendable {
    let accountID: UUID
    let sessionID: UUID
    let generation: UInt64
}

struct RealtimeLiveListenerIdentity: Equatable, Sendable {
    let owner: RealtimeListenerIdentity
    let roomID: UUID
}

struct RealtimeListenerResources: Equatable, Sendable {
    var inbox: RealtimeListenerIdentity?
    var live: RealtimeLiveListenerIdentity?

    static let empty = Self(inbox: nil, live: nil)
}

struct RealtimeListenerResourcePlan: Equatable, Sendable {
    let stopInbox: RealtimeListenerIdentity?
    let startInbox: RealtimeListenerIdentity?
    let stopLive: RealtimeLiveListenerIdentity?
    let startLive: RealtimeLiveListenerIdentity?
    let result: RealtimeListenerResources

    static func make(
        current: RealtimeListenerResources,
        desiredIdentity: RealtimeListenerIdentity?,
        desiredActiveRoomID: UUID?
    ) -> Self {
        let desiredLive = desiredIdentity.flatMap { identity in
            desiredActiveRoomID.map { RealtimeLiveListenerIdentity(owner: identity, roomID: $0) }
        }
        let result = RealtimeListenerResources(
            inbox: desiredIdentity,
            live: desiredLive
        )
        return Self(
            stopInbox: current.inbox == desiredIdentity ? nil : current.inbox,
            startInbox: current.inbox == desiredIdentity ? nil : desiredIdentity,
            stopLive: current.live == desiredLive ? nil : current.live,
            startLive: current.live == desiredLive ? nil : desiredLive,
            result: result
        )
    }
}

struct PresenceSnapshotRevision: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct PresenceGenerationIdentifier: Equatable, Sendable {
    let roomID: UUID
    let realtimeEpoch: Int
    let snapshotRevision: PresenceSnapshotRevision
    let memberUserIDs: Set<UUID>
}

struct PresenceGenerationToken: Equatable, Sendable {
    fileprivate let generation: UInt64
}

enum PresenceCallbackResult: Equatable, Sendable {
    case stale
    case accepted(readyToCommit: Bool)
}

struct PresenceGenerationCommit: Equatable, Sendable {
    let activated: PresenceGenerationIdentifier
    let retired: PresenceGenerationIdentifier?
}

struct PresenceGenerationState: Equatable, Sendable {
    private struct RuntimeGeneration: Equatable, Sendable {
        let token: PresenceGenerationToken
        let identifier: PresenceGenerationIdentifier
        var acceptedMemberUserIDs: Set<UUID>
        var presenceByUserID: [UUID: PresenceState]
        var syncedTargetUserIDs: Set<UUID> = []
        var selfTrackSucceeded = false

        var readyToCommit: Bool {
            syncedTargetUserIDs.isSuperset(of: acceptedMemberUserIDs) && selfTrackSucceeded
        }
    }

    private var nextGeneration: UInt64 = 0
    private var preparing: RuntimeGeneration?
    private var committed: RuntimeGeneration?

    var preparingIdentifier: PresenceGenerationIdentifier? { preparing?.identifier }
    var committedIdentifier: PresenceGenerationIdentifier? { committed?.identifier }
    var preparingToken: PresenceGenerationToken? { preparing?.token }
    var committedToken: PresenceGenerationToken? { committed?.token }

    mutating func prepare(_ identifier: PresenceGenerationIdentifier) -> PresenceGenerationToken {
        nextGeneration &+= 1
        let token = PresenceGenerationToken(generation: nextGeneration)
        preparing = RuntimeGeneration(
            token: token,
            identifier: identifier,
            acceptedMemberUserIDs: identifier.memberUserIDs,
            presenceByUserID: [:]
        )
        return token
    }

    mutating func receiveFirstSync(
        for targetUserID: UUID,
        state: PresenceState?,
        token: PresenceGenerationToken
    ) -> PresenceCallbackResult {
        guard var candidate = preparing,
              candidate.token == token,
              candidate.acceptedMemberUserIDs.contains(targetUserID)
        else { return .stale }
        candidate.presenceByUserID[targetUserID] = state ?? .offline
        candidate.syncedTargetUserIDs.insert(targetUserID)
        preparing = candidate
        return .accepted(readyToCommit: candidate.readyToCommit)
    }

    mutating func markSelfTracked(token: PresenceGenerationToken) -> PresenceCallbackResult {
        guard var candidate = preparing, candidate.token == token else { return .stale }
        candidate.selfTrackSucceeded = true
        preparing = candidate
        return .accepted(readyToCommit: candidate.readyToCommit)
    }

    mutating func commit(token: PresenceGenerationToken) -> PresenceGenerationCommit? {
        guard let candidate = preparing,
              candidate.token == token,
              candidate.readyToCommit
        else { return nil }
        let retired = committed?.identifier
        committed = candidate
        preparing = nil
        return PresenceGenerationCommit(activated: candidate.identifier, retired: retired)
    }

    @discardableResult
    mutating func apply(
        userID: UUID,
        state: PresenceState,
        token: PresenceGenerationToken
    ) -> PresenceCallbackResult {
        guard var current = committed,
              current.token == token,
              current.acceptedMemberUserIDs.contains(userID)
        else { return .stale }
        current.presenceByUserID[userID] = state
        committed = current
        return .accepted(readyToCommit: true)
    }

    mutating func purgeMember(_ userID: UUID) {
        if var candidate = preparing {
            candidate.acceptedMemberUserIDs.remove(userID)
            candidate.syncedTargetUserIDs.remove(userID)
            candidate.presenceByUserID.removeValue(forKey: userID)
            preparing = candidate
        }
        if var current = committed {
            current.acceptedMemberUserIDs.remove(userID)
            current.presenceByUserID.removeValue(forKey: userID)
            committed = current
        }
    }

    @discardableResult
    mutating func deadlineExceeded(token: PresenceGenerationToken) -> Bool {
        guard preparing?.token == token else { return false }
        nextGeneration &+= 1
        preparing = nil
        committed = nil
        return true
    }

    mutating func retireAll() {
        nextGeneration &+= 1
        preparing = nil
        committed = nil
    }

    func presenceState(for userID: UUID) -> PresenceState? {
        guard let committed,
              committed.acceptedMemberUserIDs.contains(userID)
        else { return nil }
        return committed.presenceByUserID[userID] ?? .offline
    }
}

struct RealtimeGrantBarrier: Sendable {
    private(set) var requestedRevision: RealtimeRevision?
    private(set) var acknowledgedRevision: RealtimeRevision?
    private(set) var membershipValid = false
    private(set) var entitlementValid = false
    private(set) var requiresEntitlement = false
    private(set) var isRevoked = false

    var isOpen: Bool {
        guard !isRevoked,
              membershipValid,
              !requiresEntitlement || entitlementValid,
              let requestedRevision,
              let acknowledgedRevision
        else { return false }
        return acknowledgedRevision >= requestedRevision
    }

    /// A requested grant that has not converged yet. Revocations never become
    /// implicit retries; only an in-flight request may be recovered later.
    var pendingRevision: RealtimeRevision? {
        guard !isOpen, !isRevoked else { return nil }
        return requestedRevision
    }

    mutating func request(revision: RealtimeRevision, requiresEntitlement: Bool) {
        requestedRevision = revision
        acknowledgedRevision = nil
        membershipValid = false
        entitlementValid = false
        self.requiresEntitlement = requiresEntitlement
        isRevoked = false
    }

    mutating func acknowledge(
        revision: RealtimeRevision,
        membershipValid: Bool,
        entitlementValid: Bool
    ) {
        if let acknowledgedRevision, revision < acknowledgedRevision { return }
        acknowledgedRevision = revision
        self.membershipValid = membershipValid
        self.entitlementValid = entitlementValid
    }

    mutating func revokeMembership() {
        membershipValid = false
        isRevoked = true
    }

    mutating func revokeEntitlement() {
        entitlementValid = false
        if requiresEntitlement { isRevoked = true }
    }

    mutating func revokeSession() {
        membershipValid = false
        entitlementValid = false
        isRevoked = true
    }
}
