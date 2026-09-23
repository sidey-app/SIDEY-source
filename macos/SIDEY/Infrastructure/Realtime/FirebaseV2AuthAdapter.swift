import FirebaseAuth
import Foundation

@MainActor
protocol FirebaseV2AuthSession: AnyObject {
    func signIn(customToken: String) async throws -> String
    func tokenClaims(expectedUID: String) async throws -> [String: Any]?
    func signOut() throws
    func addIDTokenDidChangeListener(
        _ listener: @escaping @MainActor (String?) -> Void
    ) -> NSObjectProtocol
    func removeIDTokenDidChangeListener(_ handle: NSObjectProtocol)
}

@MainActor
private final class FirebaseV2SDKAuthSession: FirebaseV2AuthSession {
    private let auth: Auth

    init(auth: Auth) {
        self.auth = auth
    }

    func signIn(customToken: String) async throws -> String {
        try await auth.signIn(withCustomToken: customToken).user.uid
    }

    func tokenClaims(expectedUID: String) async throws -> [String: Any]? {
        guard let user = auth.currentUser, user.uid == expectedUID else { return nil }
        let claims = try await FirebaseV2TokenClaimsBridge.load { completion in
            user.getIDTokenResult { result, error in
                // Firebase guarantees this completion runs asynchronously on the main queue.
                MainActor.assumeIsolated {
                    completion(result?.claims, error)
                }
            }
        }
        guard auth.currentUser === user else { return nil }
        return claims
    }

    func signOut() throws {
        try auth.signOut()
    }

    func addIDTokenDidChangeListener(
        _ listener: @escaping @MainActor (String?) -> Void
    ) -> NSObjectProtocol {
        auth.addIDTokenDidChangeListener { _, user in
            let uid = user?.uid
            Task { @MainActor in listener(uid) }
        }
    }

    func removeIDTokenDidChangeListener(_ handle: NSObjectProtocol) {
        auth.removeIDTokenDidChangeListener(handle)
    }
}

@MainActor
enum FirebaseV2TokenClaimsBridge {
    @MainActor
    private final class ResultHolder {
        var claims: [String: Any]?
    }

    static func load(
        _ request: (@escaping @MainActor ([String: Any]?, Error?) -> Void) -> Void
    ) async throws -> [String: Any] {
        let result = ResultHolder()
        // Only Void crosses the continuation; SDK objects and Any values stay on MainActor.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request { claims, error in
                if let claims {
                    result.claims = claims
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? FirebaseV2AuthError.tokenRefreshValidationFailed)
                }
            }
        }
        guard let claims = result.claims else {
            throw FirebaseV2AuthError.tokenRefreshValidationFailed
        }
        return claims
    }
}

enum FirebaseV2AuthError: LocalizedError, Equatable, Sendable {
    case signedOutDuringCredentialLifetime
    case tokenRefreshValidationFailed
    case malformedAccountIdentifier
    case accountMismatch
    case invalidSessionClaim
    case sessionMismatch
    case invalidRolloutLeaseClaim
    case rolloutLeaseMismatch
    case rolloutLeaseExpired

    var errorDescription: String? {
        switch self {
        case .signedOutDuringCredentialLifetime:
            L10n.text("backend.error.authentication_required")
        case .tokenRefreshValidationFailed:
            L10n.text("firebase.auth.error.token_refresh_validation_failed")
        case .malformedAccountIdentifier:
            L10n.text("firebase.auth.error.malformed_account_identifier")
        case .accountMismatch:
            L10n.text("firebase.auth.error.account_mismatch")
        case .invalidSessionClaim:
            L10n.text("firebase.auth.error.invalid_session_claim")
        case .sessionMismatch:
            L10n.text("firebase.auth.error.session_mismatch")
        case .invalidRolloutLeaseClaim:
            L10n.text("firebase.auth.error.invalid_rollout_lease_claim")
        case .rolloutLeaseMismatch:
            L10n.text("firebase.auth.error.rollout_lease_mismatch")
        case .rolloutLeaseExpired:
            L10n.text("firebase.auth.error.rollout_lease_expired")
        }
    }
}

enum FirebaseV2IdentityClaimValidator {
    static func validate(
        firebaseUID: String,
        claims: [String: Any],
        expected: RealtimeCredentialIdentity,
        expectedRolloutLeaseExpiresAt: Int64,
        nowMilliseconds: Int64
    ) throws -> RealtimeCredentialIdentity {
        guard let accountID = UUID(uuidString: firebaseUID) else {
            throw FirebaseV2AuthError.malformedAccountIdentifier
        }
        guard accountID == expected.accountID else {
            throw FirebaseV2AuthError.accountMismatch
        }
        guard let rawSessionID = claims["sideySessionId"] as? String,
              let sessionID = UUID(uuidString: rawSessionID) else {
            throw FirebaseV2AuthError.invalidSessionClaim
        }
        guard sessionID == expected.sessionID else {
            throw FirebaseV2AuthError.sessionMismatch
        }
        guard let leaseNumber = claims["sideyRolloutUntil"] as? NSNumber,
              CFGetTypeID(leaseNumber) != CFBooleanGetTypeID(),
              leaseNumber.doubleValue.isFinite,
              leaseNumber.doubleValue == Double(leaseNumber.int64Value),
              (1...FirebaseV2RolloutLeaseSchedule.maximumSafeInteger).contains(
                leaseNumber.int64Value
              ) else {
            throw FirebaseV2AuthError.invalidRolloutLeaseClaim
        }
        guard leaseNumber.int64Value == expectedRolloutLeaseExpiresAt else {
            throw FirebaseV2AuthError.rolloutLeaseMismatch
        }
        guard leaseNumber.int64Value > nowMilliseconds else {
            throw FirebaseV2AuthError.rolloutLeaseExpired
        }
        return RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)
    }
}

@MainActor
final class FirebaseV2AuthCredentialOwnership {
    private var owner: UUID?

    func installed(by attemptID: UUID) {
        owner = attemptID
    }

    func releaseIfOwned(by attemptID: UUID) -> Bool {
        guard owner == attemptID else { return false }
        owner = nil
        return true
    }

    func clear() {
        owner = nil
    }
}

/// Owns the Firebase Auth SDK session. Firebase itself owns ID-token refresh and
/// refresh-token rotation; SIDEY never copies those credentials into Keychain.
@MainActor
final class FirebaseV2AuthAdapter {
    private struct MonitoringExpectation {
        let identity: RealtimeCredentialIdentity
        let rolloutLeaseExpiresAt: Int64
    }

    private let authSession: any FirebaseV2AuthSession
    private let onIdentityInvalidated: @MainActor @Sendable (Error) -> Void
    private let nowMilliseconds: @MainActor @Sendable () -> Int64
    private let credentialOwnership = FirebaseV2AuthCredentialOwnership()
    private var identityListenerHandle: NSObjectProtocol?
    private var identityListenerGeneration: UInt64 = 0
    private var identityValidationGeneration: UInt64 = 0

    init(
        auth: Auth,
        onIdentityInvalidated: @escaping @MainActor @Sendable (Error) -> Void = { _ in },
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.authSession = FirebaseV2SDKAuthSession(auth: auth)
        self.onIdentityInvalidated = onIdentityInvalidated
        self.nowMilliseconds = nowMilliseconds
    }

    init(
        authSession: any FirebaseV2AuthSession,
        onIdentityInvalidated: @escaping @MainActor @Sendable (Error) -> Void = { _ in },
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.authSession = authSession
        self.onIdentityInvalidated = onIdentityInvalidated
        self.nowMilliseconds = nowMilliseconds
    }

    @discardableResult
    func signIn(
        customToken: FirebaseV2CustomToken,
        expectedIdentity: RealtimeCredentialIdentity,
        expectedRolloutLeaseExpiresAt: Int64,
        attemptID: UUID
    ) async throws -> RealtimeCredentialIdentity {
        // A custom-token refresh synchronously publishes an ID-token change.
        // Detach the previous lease observer before installing the new token,
        // otherwise it compares the new lease against the old expiry and
        // falsely shuts down a healthy session.
        let suspendedMonitoring = suspendIdentityMonitoring()
        var installedCredential = false
        do {
            let firebaseUID = try await authSession.signIn(customToken: customToken.value)
            credentialOwnership.installed(by: attemptID)
            installedCredential = true
            guard let claims = try await authSession.tokenClaims(expectedUID: firebaseUID) else {
                throw FirebaseV2AuthError.tokenRefreshValidationFailed
            }
            let identity = try FirebaseV2IdentityClaimValidator.validate(
                firebaseUID: firebaseUID,
                claims: claims,
                expected: expectedIdentity,
                expectedRolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt,
                nowMilliseconds: nowMilliseconds()
            )
            startIdentityMonitoring(
                expectedIdentity: expectedIdentity,
                expectedRolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt
            )
            return identity
        } catch {
            if !installedCredential, let suspendedMonitoring {
                startIdentityMonitoring(
                    expectedIdentity: suspendedMonitoring.identity,
                    expectedRolloutLeaseExpiresAt:
                        suspendedMonitoring.rolloutLeaseExpiresAt
                )
            }
            // A failed claim check must not leave a credential from the wrong
            // account/session installed in the named Firebase app.
            if signOut(ifOwnedBy: attemptID) {
                onIdentityInvalidated(error)
            }
            throw error
        }
    }

    func signOut() throws {
        credentialOwnership.clear()
        stopIdentityMonitoring()
        try authSession.signOut()
    }

    /// A stale bootstrap may clean up only the Firebase credential that it
    /// installed. A newer recovery can complete while the older lifecycle
    /// commit is being rejected, and must never be signed out by that older
    /// attempt.
    @discardableResult
    func signOut(ifOwnedBy attemptID: UUID) -> Bool {
        guard credentialOwnership.releaseIfOwned(by: attemptID) else { return false }
        stopIdentityMonitoring()
        try? authSession.signOut()
        return true
    }

    /// Firebase rotates ID tokens internally. Every token-change callback is
    /// therefore revalidated against the current Supabase session identity;
    /// a same-UID token from a different SIDEY session fails closed.
    private func startIdentityMonitoring(
        expectedIdentity: RealtimeCredentialIdentity,
        expectedRolloutLeaseExpiresAt: Int64
    ) {
        stopIdentityMonitoring()
        let listenerGeneration = identityListenerGeneration
        monitoringExpectation = MonitoringExpectation(
            identity: expectedIdentity,
            rolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt
        )
        identityListenerHandle = authSession.addIDTokenDidChangeListener { [weak self] uid in
            guard let self, listenerGeneration == self.identityListenerGeneration else { return }
            self.validateIdentityChange(
                firebaseUID: uid,
                expectedIdentity: expectedIdentity,
                expectedRolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt
            )
        }
    }

    private func validateIdentityChange(
        firebaseUID: String?,
        expectedIdentity: RealtimeCredentialIdentity,
        expectedRolloutLeaseExpiresAt: Int64
    ) {
        identityValidationGeneration &+= 1
        let generation = identityValidationGeneration
        guard let firebaseUID else {
            invalidateIdentity(with: FirebaseV2AuthError.signedOutDuringCredentialLifetime)
            return
        }
        let validationNowMilliseconds = nowMilliseconds()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let validation: Result<RealtimeCredentialIdentity, FirebaseV2AuthError>
            if let claims = try? await authSession.tokenClaims(expectedUID: firebaseUID) {
                do {
                    validation = .success(try FirebaseV2IdentityClaimValidator.validate(
                        firebaseUID: firebaseUID,
                        claims: claims,
                        expected: expectedIdentity,
                        expectedRolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt,
                        nowMilliseconds: validationNowMilliseconds
                    ))
                } catch let error as FirebaseV2AuthError {
                    validation = .failure(error)
                } catch {
                    validation = .failure(.tokenRefreshValidationFailed)
                }
            } else {
                validation = .failure(.tokenRefreshValidationFailed)
            }
            guard generation == identityValidationGeneration else { return }
            if case .failure(let error) = validation {
                invalidateIdentity(with: error)
            }
        }
    }

    private func invalidateIdentity(with error: Error) {
        credentialOwnership.clear()
        stopIdentityMonitoring()
        try? authSession.signOut()
        onIdentityInvalidated(error)
    }

    private var monitoringExpectation: MonitoringExpectation?

    private func suspendIdentityMonitoring() -> MonitoringExpectation? {
        let expectation = monitoringExpectation
        stopIdentityMonitoring()
        return expectation
    }

    private func stopIdentityMonitoring() {
        identityListenerGeneration &+= 1
        identityValidationGeneration &+= 1
        monitoringExpectation = nil
        if let identityListenerHandle {
            authSession.removeIDTokenDidChangeListener(identityListenerHandle)
            self.identityListenerHandle = nil
        }
    }
}
