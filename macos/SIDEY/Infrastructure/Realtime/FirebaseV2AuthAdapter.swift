import FirebaseAuth
import Foundation

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
            "Firebase 인증 세션이 예상보다 일찍 종료되었습니다."
        case .tokenRefreshValidationFailed:
            "Firebase 갱신 인증 정보를 검증할 수 없습니다."
        case .malformedAccountIdentifier:
            "Firebase 인증 계정 식별자가 올바르지 않습니다."
        case .accountMismatch:
            "Firebase 인증 계정이 현재 SIDEY 계정과 일치하지 않습니다."
        case .invalidSessionClaim:
            "Firebase 인증 세션 claim을 확인할 수 없습니다."
        case .sessionMismatch:
            "Firebase 인증 세션이 현재 SIDEY 로그인 세션과 일치하지 않습니다."
        case .invalidRolloutLeaseClaim:
            "Firebase rollout lease claim을 확인할 수 없습니다."
        case .rolloutLeaseMismatch:
            "Firebase rollout lease가 bootstrap 응답과 일치하지 않습니다."
        case .rolloutLeaseExpired:
            "Firebase 실시간 rollout lease가 만료되었습니다."
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
    private let auth: Auth
    private let onIdentityInvalidated: @MainActor @Sendable (Error) -> Void
    private let nowMilliseconds: @MainActor @Sendable () -> Int64
    private let credentialOwnership = FirebaseV2AuthCredentialOwnership()
    private var identityListenerHandle: NSObjectProtocol?
    private var identityValidationGeneration: UInt64 = 0

    init(
        auth: Auth,
        onIdentityInvalidated: @escaping @MainActor @Sendable (Error) -> Void = { _ in },
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.auth = auth
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
        let result = try await auth.signIn(withCustomToken: customToken.value)
        credentialOwnership.installed(by: attemptID)
        do {
            let tokenResult = try await result.user.getIDTokenResult()
            let identity = try FirebaseV2IdentityClaimValidator.validate(
                firebaseUID: result.user.uid,
                claims: tokenResult.claims,
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
        try auth.signOut()
    }

    /// A stale bootstrap may clean up only the Firebase credential that it
    /// installed. A newer recovery can complete while the older lifecycle
    /// commit is being rejected, and must never be signed out by that older
    /// attempt.
    @discardableResult
    func signOut(ifOwnedBy attemptID: UUID) -> Bool {
        guard credentialOwnership.releaseIfOwned(by: attemptID) else { return false }
        stopIdentityMonitoring()
        try? auth.signOut()
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
        identityListenerHandle = auth.addIDTokenDidChangeListener { [weak self] _, user in
            let firebaseUID = user?.uid
            Task { @MainActor [weak self] in
                self?.validateIdentityChange(
                    firebaseUID: firebaseUID,
                    expectedIdentity: expectedIdentity,
                    expectedRolloutLeaseExpiresAt: expectedRolloutLeaseExpiresAt
                )
            }
        }
    }

    private func validateIdentityChange(
        firebaseUID: String?,
        expectedIdentity: RealtimeCredentialIdentity,
        expectedRolloutLeaseExpiresAt: Int64
    ) {
        identityValidationGeneration &+= 1
        let generation = identityValidationGeneration
        guard let firebaseUID, let user = auth.currentUser else {
            invalidateIdentity(with: FirebaseV2AuthError.signedOutDuringCredentialLifetime)
            return
        }
        let validationNowMilliseconds = nowMilliseconds()
        user.getIDTokenResult { [weak self] tokenResult, _ in
            let validation: Result<RealtimeCredentialIdentity, FirebaseV2AuthError>
            if let tokenResult {
                do {
                    validation = .success(try FirebaseV2IdentityClaimValidator.validate(
                        firebaseUID: firebaseUID,
                        claims: tokenResult.claims,
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
            Task { @MainActor [weak self] in
                guard let self, generation == identityValidationGeneration else { return }
                if case .failure(let error) = validation {
                    invalidateIdentity(with: error)
                }
            }
        }
    }

    private func invalidateIdentity(with error: Error) {
        credentialOwnership.clear()
        stopIdentityMonitoring()
        try? auth.signOut()
        onIdentityInvalidated(error)
    }

    private func stopIdentityMonitoring() {
        identityValidationGeneration &+= 1
        if let identityListenerHandle {
            auth.removeIDTokenDidChangeListener(identityListenerHandle)
            self.identityListenerHandle = nil
        }
    }
}
