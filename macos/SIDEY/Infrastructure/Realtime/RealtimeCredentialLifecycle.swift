import Foundation

enum RealtimeBootstrapTrigger: CaseIterable, Equatable, Sendable {
    case initialLogin
    case sessionRestore
    case explicitRecovery
    case rolloutLeaseRefresh
}

struct RealtimeCredentialIdentity: Equatable, Sendable {
    let accountID: UUID
    let sessionID: UUID
}

/// An opaque reference to credential material owned by a later transport adapter.
///
/// This type deliberately carries no token, endpoint, wire response, or persistence
/// representation. Lifetime is measured only with a monotonic clock so wall-clock
/// corrections cannot extend a credential.
struct RealtimeCredentialLease: Equatable, Sendable {
    let identity: RealtimeCredentialIdentity
    let handle: UUID
    let receivedAt: ContinuousClock.Instant
    let expiresIn: Duration

    func isUsable(
        at now: ContinuousClock.Instant,
        safetyMargin: Duration
    ) -> Bool {
        guard safetyMargin >= .zero,
              expiresIn > safetyMargin,
              now >= receivedAt else {
            return false
        }
        return now < receivedAt.advanced(by: expiresIn - safetyMargin)
    }
}

struct RealtimeCredentialBootstrapAttempt: Equatable, Sendable {
    let trigger: RealtimeBootstrapTrigger
    let identity: RealtimeCredentialIdentity
    let generation: UInt64
}

struct RealtimeCredentialLifecycleSnapshot: Equatable, Sendable {
    let generation: UInt64
    let identity: RealtimeCredentialIdentity?
    let credential: RealtimeCredentialLease?
}

enum RealtimeCredentialLifecycleError: Error, Equatable {
    case noActiveSession
    case identityMismatch
    case staleAttempt
    case invalidLifetime
}

/// Serializes Firebase Auth mutations with lifecycle commits. Firebase Auth is
/// a singleton per named app, so overlapping recoveries can otherwise complete
/// out of order and let an older custom-token sign-in overwrite the credential
/// already committed by a newer attempt.
actor RealtimeCredentialOperationGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        await enter()
        do {
            let value = try await operation()
            leave()
            return value
        } catch {
            leave()
            throw error
        }
    }

    private func enter() async {
        guard occupied else {
            occupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func leave() {
        guard !waiters.isEmpty else {
            occupied = false
            return
        }
        waiters.removeFirst().resume()
    }
}

/// Owns credential eligibility and replacement ordering, not credential I/O.
///
/// Bootstrap is event-driven: callers can begin it only for a typed login,
/// restore, or explicit recovery trigger. There is intentionally no timer,
/// tick, polling, or implicit refresh entry point.
actor RealtimeCredentialLifecycle {
    private let safetyMargin: Duration
    private var generation: UInt64 = 0
    private var identity: RealtimeCredentialIdentity?
    private var credential: RealtimeCredentialLease?

    init(safetyMargin: Duration = .seconds(60)) {
        precondition(safetyMargin >= .zero)
        self.safetyMargin = safetyMargin
    }

    func beginBootstrap(
        trigger: RealtimeBootstrapTrigger,
        identity requestedIdentity: RealtimeCredentialIdentity
    ) throws -> RealtimeCredentialBootstrapAttempt {
        switch trigger {
        case .initialLogin, .sessionRestore:
            if identity != requestedIdentity {
                invalidateCurrentIdentity(replacingWith: requestedIdentity)
            }
        case .explicitRecovery, .rolloutLeaseRefresh:
            guard let identity else {
                throw RealtimeCredentialLifecycleError.noActiveSession
            }
            guard identity == requestedIdentity else {
                throw RealtimeCredentialLifecycleError.identityMismatch
            }
        }

        advanceGeneration()
        return RealtimeCredentialBootstrapAttempt(
            trigger: trigger,
            identity: requestedIdentity,
            generation: generation
        )
    }

    func invalidateForLogout() {
        advanceGeneration()
        identity = nil
        credential = nil
    }

    func invalidateForAccountSwitch(to newIdentity: RealtimeCredentialIdentity) {
        advanceGeneration()
        identity = newIdentity
        credential = nil
    }

    /// Commits external storage first and publishes the new in-memory lease only
    /// after that commit succeeds. The commit closure is synchronous by design:
    /// actor reentrancy cannot let logout or account switch interleave between the
    /// generation check and replacement.
    func replaceCredential(
        _ candidate: RealtimeCredentialLease,
        for attempt: RealtimeCredentialBootstrapAttempt,
        evaluatedAt now: ContinuousClock.Instant,
        commit: @Sendable (RealtimeCredentialLease) throws -> Void
    ) throws {
        guard attempt.generation == generation else {
            throw RealtimeCredentialLifecycleError.staleAttempt
        }
        guard identity == attempt.identity,
              candidate.identity == attempt.identity else {
            throw RealtimeCredentialLifecycleError.identityMismatch
        }
        guard candidate.isUsable(at: now, safetyMargin: safetyMargin) else {
            throw RealtimeCredentialLifecycleError.invalidLifetime
        }

        try commit(candidate)
        credential = candidate
    }

    func snapshot() -> RealtimeCredentialLifecycleSnapshot {
        RealtimeCredentialLifecycleSnapshot(
            generation: generation,
            identity: identity,
            credential: credential
        )
    }

    private func invalidateCurrentIdentity(replacingWith newIdentity: RealtimeCredentialIdentity) {
        advanceGeneration()
        identity = newIdentity
        credential = nil
    }

    private func advanceGeneration() {
        generation &+= 1
    }
}
