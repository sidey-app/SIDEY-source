import XCTest
@testable import SIDEY

final class RealtimeCredentialLifecycleTests: XCTestCase {
    private let accountA = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let accountB = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    private let sessionA = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    private let sessionB = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!

    func testCredentialOperationGateReleasesAfterSuccessAndFailure() async throws {
        let gate = RealtimeCredentialOperationGate()

        let first = await gate.perform { 1 }
        XCTAssertEqual(first, 1)

        do {
            _ = try await gate.perform { () async throws -> Int in
                throw ReplacementFailure.storageUnavailable
            }
            XCTFail("The operation failure must be propagated")
        } catch ReplacementFailure.storageUnavailable {
            // Expected. The next operation proves the gate was still released.
        }

        let third = await gate.perform { 3 }
        XCTAssertEqual(third, 3)
    }

    func testOnlyExplicitLifecycleEventsCanStartBootstrap() async throws {
        XCTAssertEqual(
            Set(RealtimeBootstrapTrigger.allCases),
            Set([.initialLogin, .sessionRestore, .explicitRecovery, .rolloutLeaseRefresh])
        )

        let identity = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let login = RealtimeCredentialLifecycle()
        let restored = RealtimeCredentialLifecycle()

        let loginAttempt = try await login.beginBootstrap(
            trigger: .initialLogin,
            identity: identity
        )
        let restoreAttempt = try await restored.beginBootstrap(
            trigger: .sessionRestore,
            identity: identity
        )
        let recoveryAttempt = try await login.beginBootstrap(
            trigger: .explicitRecovery,
            identity: identity
        )

        XCTAssertEqual(loginAttempt.trigger, .initialLogin)
        XCTAssertEqual(restoreAttempt.trigger, .sessionRestore)
        XCTAssertEqual(recoveryAttempt.trigger, .explicitRecovery)

        let inactive = RealtimeCredentialLifecycle()
        do {
            _ = try await inactive.beginBootstrap(
                trigger: .explicitRecovery,
                identity: identity
            )
            XCTFail("Recovery must not establish a session that was never activated")
        } catch RealtimeCredentialLifecycleError.noActiveSession {
            // Expected. There is no timer or polling entry point that can establish identity.
        }
    }

    func testLogoutInvalidatesAnInFlightBootstrapGeneration() async throws {
        let lifecycle = RealtimeCredentialLifecycle()
        let identity = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let attempt = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identity
        )
        let generationBeforeLogout = attempt.generation

        await lifecycle.invalidateForLogout()

        let committed = LockedFlag()
        do {
            try await lifecycle.replaceCredential(
                lease(identity: identity),
                for: attempt,
                evaluatedAt: monotonicBase
            ) { _ in
                committed.set()
            }
            XCTFail("A completion from before logout must be rejected")
        } catch RealtimeCredentialLifecycleError.staleAttempt {
            // Expected.
        }

        let snapshot = await lifecycle.snapshot()
        XCTAssertGreaterThan(snapshot.generation, generationBeforeLogout)
        XCTAssertNil(snapshot.identity)
        XCTAssertNil(snapshot.credential)
        XCTAssertFalse(committed.value)
    }

    func testAccountSwitchInvalidatesOldCompletionEvenForSameUID() async throws {
        let lifecycle = RealtimeCredentialLifecycle()
        let identityA = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let identityB = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionB)
        let attemptA = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identityA
        )

        await lifecycle.invalidateForAccountSwitch(to: identityB)
        let attemptB = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identityB
        )

        do {
            try await lifecycle.replaceCredential(
                lease(identity: identityA),
                for: attemptA,
                evaluatedAt: monotonicBase
            ) { _ in }
            XCTFail("Session A must not replace credentials after session B becomes active")
        } catch RealtimeCredentialLifecycleError.staleAttempt {
            // Expected.
        }

        let credentialB = lease(identity: identityB)
        try await lifecycle.replaceCredential(
            credentialB,
            for: attemptB,
            evaluatedAt: monotonicBase
        ) { _ in }

        let snapshot = await lifecycle.snapshot()
        XCTAssertEqual(snapshot.identity, identityB)
        XCTAssertEqual(snapshot.credential, credentialB)
    }

    func testCandidateIdentityMustMatchAccountAndSession() async throws {
        let lifecycle = RealtimeCredentialLifecycle()
        let identityA = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let attempt = try await lifecycle.beginBootstrap(
            trigger: .sessionRestore,
            identity: identityA
        )

        for mismatchedIdentity in [
            RealtimeCredentialIdentity(accountID: accountB, sessionID: sessionA),
            RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionB),
        ] {
            do {
                try await lifecycle.replaceCredential(
                    lease(identity: mismatchedIdentity),
                    for: attempt,
                    evaluatedAt: monotonicBase
                ) { _ in }
                XCTFail("Account and session must both match the bootstrap attempt")
            } catch RealtimeCredentialLifecycleError.identityMismatch {
                // Expected.
            }
        }
    }

    func testMonotonicLifetimeUsesSafetyMarginAndRejectsFutureReceipt() async throws {
        let lifecycle = RealtimeCredentialLifecycle(safetyMargin: .seconds(30))
        let identity = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let attempt = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identity
        )
        let candidate = lease(identity: identity, expiresIn: .seconds(100))

        XCTAssertTrue(candidate.isUsable(
            at: monotonicBase.advanced(by: .seconds(69)),
            safetyMargin: .seconds(30)
        ))
        XCTAssertFalse(candidate.isUsable(
            at: monotonicBase.advanced(by: .seconds(70)),
            safetyMargin: .seconds(30)
        ))
        XCTAssertFalse(lease(
            identity: identity,
            receivedAt: monotonicBase.advanced(by: .seconds(1))
        ).isUsable(at: monotonicBase, safetyMargin: .seconds(30)))

        do {
            try await lifecycle.replaceCredential(
                lease(identity: identity, expiresIn: .seconds(30)),
                for: attempt,
                evaluatedAt: monotonicBase
            ) { _ in }
            XCTFail("A lease no longer than its safety margin must be rejected")
        } catch RealtimeCredentialLifecycleError.invalidLifetime {
            // Expected.
        }
    }

    func testFailedAtomicReplacementPreservesExistingCredential() async throws {
        let lifecycle = RealtimeCredentialLifecycle(safetyMargin: .seconds(30))
        let identity = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let firstAttempt = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identity
        )
        let existing = lease(identity: identity)
        try await lifecycle.replaceCredential(
            existing,
            for: firstAttempt,
            evaluatedAt: monotonicBase
        ) { _ in }

        let recovery = try await lifecycle.beginBootstrap(
            trigger: .explicitRecovery,
            identity: identity
        )
        let replacement = lease(identity: identity, handle: UUID())
        do {
            try await lifecycle.replaceCredential(
                replacement,
                for: recovery,
                evaluatedAt: monotonicBase
            ) { _ in
                throw ReplacementFailure.storageUnavailable
            }
            XCTFail("Replacement failure must be visible")
        } catch ReplacementFailure.storageUnavailable {
            // Expected.
        }

        let snapshot = await lifecycle.snapshot()
        XCTAssertEqual(snapshot.identity, identity)
        XCTAssertEqual(snapshot.credential, existing)
    }

    func testNewerAttemptInvalidatesOlderAttemptWithoutDiscardingUsableCredential() async throws {
        let lifecycle = RealtimeCredentialLifecycle(safetyMargin: .seconds(30))
        let identity = RealtimeCredentialIdentity(accountID: accountA, sessionID: sessionA)
        let initial = try await lifecycle.beginBootstrap(
            trigger: .initialLogin,
            identity: identity
        )
        let existing = lease(identity: identity)
        try await lifecycle.replaceCredential(
            existing,
            for: initial,
            evaluatedAt: monotonicBase
        ) { _ in }

        let olderRecovery = try await lifecycle.beginBootstrap(
            trigger: .explicitRecovery,
            identity: identity
        )
        let newerRecovery = try await lifecycle.beginBootstrap(
            trigger: .explicitRecovery,
            identity: identity
        )

        do {
            try await lifecycle.replaceCredential(
                lease(identity: identity, handle: UUID()),
                for: olderRecovery,
                evaluatedAt: monotonicBase
            ) { _ in }
            XCTFail("Only the newest explicit attempt may commit")
        } catch RealtimeCredentialLifecycleError.staleAttempt {
            // Expected.
        }
        let snapshotAfterStaleAttempt = await lifecycle.snapshot()
        XCTAssertEqual(snapshotAfterStaleAttempt.credential, existing)

        let newest = lease(identity: identity, handle: UUID())
        try await lifecycle.replaceCredential(
            newest,
            for: newerRecovery,
            evaluatedAt: monotonicBase
        ) { _ in }
        let finalSnapshot = await lifecycle.snapshot()
        XCTAssertEqual(finalSnapshot.credential, newest)
    }

    private var monotonicBase: ContinuousClock.Instant {
        ContinuousClock().now
    }

    private func lease(
        identity: RealtimeCredentialIdentity,
        handle: UUID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!,
        receivedAt: ContinuousClock.Instant? = nil,
        expiresIn: Duration = .seconds(3_600)
    ) -> RealtimeCredentialLease {
        RealtimeCredentialLease(
            identity: identity,
            handle: handle,
            receivedAt: receivedAt ?? monotonicBase,
            expiresIn: expiresIn
        )
    }
}

private enum ReplacementFailure: Error {
    case storageUnavailable
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }
}
