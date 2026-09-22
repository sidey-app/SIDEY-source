import XCTest
@testable import SIDEY

@MainActor
final class FirebaseV2AuthAdapterTests: XCTestCase {
    private let nowMilliseconds: Int64 = 1_800_000_000_000
    private let leaseExpiresAt: Int64 = 1_800_000_300_000

    func testStaleAttemptCannotReleaseCredentialInstalledByNewerAttempt() {
        let ownership = FirebaseV2AuthCredentialOwnership()
        let older = UUID()
        let newer = UUID()

        ownership.installed(by: older)
        ownership.installed(by: newer)

        XCTAssertFalse(ownership.releaseIfOwned(by: older))
        XCTAssertTrue(ownership.releaseIfOwned(by: newer))
        XCTAssertFalse(ownership.releaseIfOwned(by: newer))
    }

    func testClaimValidatorAcceptsExpectedAccountAndSession() throws {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let identity = try FirebaseV2IdentityClaimValidator.validate(
            firebaseUID: accountID.uuidString.lowercased(),
            claims: [
                "sideySessionId": sessionID.uuidString.lowercased(),
                "sideyRolloutUntil": NSNumber(value: leaseExpiresAt),
            ],
            expected: RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID),
            expectedRolloutLeaseExpiresAt: leaseExpiresAt,
            nowMilliseconds: nowMilliseconds
        )

        XCTAssertEqual(identity.accountID, accountID)
        XCTAssertEqual(identity.sessionID, sessionID)
    }

    func testClaimValidatorRejectsDifferentUIDOrSession() {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let expected = RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)

        XCTAssertThrowsError(try FirebaseV2IdentityClaimValidator.validate(
            firebaseUID: UUID().uuidString,
            claims: [
                "sideySessionId": sessionID.uuidString,
                "sideyRolloutUntil": NSNumber(value: leaseExpiresAt),
            ],
            expected: expected,
            expectedRolloutLeaseExpiresAt: leaseExpiresAt,
            nowMilliseconds: nowMilliseconds
        )) { error in
            XCTAssertEqual(error as? FirebaseV2AuthError, .accountMismatch)
        }
        XCTAssertThrowsError(try FirebaseV2IdentityClaimValidator.validate(
            firebaseUID: accountID.uuidString,
            claims: [
                "sideySessionId": UUID().uuidString,
                "sideyRolloutUntil": NSNumber(value: leaseExpiresAt),
            ],
            expected: expected,
            expectedRolloutLeaseExpiresAt: leaseExpiresAt,
            nowMilliseconds: nowMilliseconds
        )) { error in
            XCTAssertEqual(error as? FirebaseV2AuthError, .sessionMismatch)
        }
    }

    func testClaimValidatorRejectsMissingOrMalformedSessionClaim() {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let expected = RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)

        for claims: [String: Any] in [
            [:],
            ["sideySessionId": 42],
            ["sideySessionId": "not-a-uuid"],
        ] {
            XCTAssertThrowsError(try FirebaseV2IdentityClaimValidator.validate(
                firebaseUID: accountID.uuidString,
                claims: claims,
                expected: expected,
                expectedRolloutLeaseExpiresAt: leaseExpiresAt,
                nowMilliseconds: nowMilliseconds
            )) { error in
                XCTAssertEqual(error as? FirebaseV2AuthError, .invalidSessionClaim)
            }
        }
    }

    func testClaimValidatorRejectsMissingMismatchedOrExpiredRolloutLease() {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let expected = RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)

        for (rawLease, expectedError): (Any?, FirebaseV2AuthError) in [
            (nil, .invalidRolloutLeaseClaim),
            (true, .invalidRolloutLeaseClaim),
            (Double(leaseExpiresAt) + 0.5, .invalidRolloutLeaseClaim),
            (leaseExpiresAt + 1, .rolloutLeaseMismatch),
            (nowMilliseconds, .rolloutLeaseMismatch),
        ] {
            var claims: [String: Any] = ["sideySessionId": sessionID.uuidString]
            if let rawLease { claims["sideyRolloutUntil"] = rawLease }
            XCTAssertThrowsError(try FirebaseV2IdentityClaimValidator.validate(
                firebaseUID: accountID.uuidString,
                claims: claims,
                expected: expected,
                expectedRolloutLeaseExpiresAt: leaseExpiresAt,
                nowMilliseconds: nowMilliseconds
            )) { error in
                XCTAssertEqual(error as? FirebaseV2AuthError, expectedError)
            }
        }

        XCTAssertThrowsError(try FirebaseV2IdentityClaimValidator.validate(
            firebaseUID: accountID.uuidString,
            claims: [
                "sideySessionId": sessionID.uuidString,
                "sideyRolloutUntil": NSNumber(value: nowMilliseconds),
            ],
            expected: expected,
            expectedRolloutLeaseExpiresAt: nowMilliseconds,
            nowMilliseconds: nowMilliseconds
        )) { error in
            XCTAssertEqual(error as? FirebaseV2AuthError, .rolloutLeaseExpired)
        }
    }

    func testLeaseReplacementDetachesPreviousTokenObserverBeforeSignIn() async throws {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let identity = RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)
        let replacementLease = leaseExpiresAt + 300_000
        let auth = FakeFirebaseV2AuthSession(tokens: [
            "initial": .init(uid: accountID.uuidString, claims: [
                "sideySessionId": sessionID.uuidString,
                "sideyRolloutUntil": NSNumber(value: leaseExpiresAt),
            ]),
            "replacement": .init(uid: accountID.uuidString, claims: [
                "sideySessionId": sessionID.uuidString,
                "sideyRolloutUntil": NSNumber(value: replacementLease),
            ]),
        ])
        let currentObserverInvalidated = expectation(
            description: "current observer detects a genuine lease mismatch"
        )
        var invalidations: [FirebaseV2AuthError] = []
        let adapter = FirebaseV2AuthAdapter(
            authSession: auth,
            onIdentityInvalidated: { error in
                if let error = error as? FirebaseV2AuthError {
                    invalidations.append(error)
                    currentObserverInvalidated.fulfill()
                }
            },
            nowMilliseconds: { self.nowMilliseconds }
        )

        _ = try await adapter.signIn(
            customToken: .init(value: "initial"),
            expectedIdentity: identity,
            expectedRolloutLeaseExpiresAt: leaseExpiresAt,
            attemptID: UUID()
        )
        XCTAssertEqual(auth.listenerCount, 1)

        _ = try await adapter.signIn(
            customToken: .init(value: "replacement"),
            expectedIdentity: identity,
            expectedRolloutLeaseExpiresAt: replacementLease,
            attemptID: UUID()
        )

        XCTAssertTrue(invalidations.isEmpty)
        XCTAssertEqual(auth.listenerCount, 1)
        XCTAssertEqual(auth.signOutCount, 0)

        // Firebase can already have queued the removed listener's callback on
        // the main actor. It must not compare the new token with the old lease.
        auth.emitMostRecentlyRemovedIdentityChange(uid: accountID.uuidString)
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(invalidations.isEmpty)
        XCTAssertEqual(auth.listenerCount, 1)
        XCTAssertEqual(auth.signOutCount, 0)

        auth.replaceCurrentToken(uid: accountID.uuidString, claims: [
            "sideySessionId": sessionID.uuidString,
            "sideyRolloutUntil": NSNumber(value: replacementLease + 1),
        ])
        auth.emitIdentityChange(uid: accountID.uuidString)
        await fulfillment(of: [currentObserverInvalidated], timeout: 1)
        XCTAssertEqual(invalidations, [.rolloutLeaseMismatch])
        XCTAssertEqual(auth.listenerCount, 0)
        XCTAssertEqual(auth.signOutCount, 1)
    }

    func testFailedLeaseReplacementRestoresPreviousTokenObserver() async throws {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let identity = RealtimeCredentialIdentity(accountID: accountID, sessionID: sessionID)
        let auth = FakeFirebaseV2AuthSession(tokens: [
            "initial": .init(uid: accountID.uuidString, claims: [
                "sideySessionId": sessionID.uuidString,
                "sideyRolloutUntil": NSNumber(value: leaseExpiresAt),
            ]),
        ])
        let invalidated = expectation(description: "restored observer detects lease mismatch")
        var invalidations: [FirebaseV2AuthError] = []
        let adapter = FirebaseV2AuthAdapter(
            authSession: auth,
            onIdentityInvalidated: { error in
                if let error = error as? FirebaseV2AuthError {
                    invalidations.append(error)
                    invalidated.fulfill()
                }
            },
            nowMilliseconds: { self.nowMilliseconds }
        )
        _ = try await adapter.signIn(
            customToken: .init(value: "initial"),
            expectedIdentity: identity,
            expectedRolloutLeaseExpiresAt: leaseExpiresAt,
            attemptID: UUID()
        )
        auth.signInError = URLError(.timedOut)

        do {
            _ = try await adapter.signIn(
                customToken: .init(value: "replacement"),
                expectedIdentity: identity,
                expectedRolloutLeaseExpiresAt: leaseExpiresAt + 300_000,
                attemptID: UUID()
            )
            XCTFail("Expected replacement failure")
        } catch {
            XCTAssertEqual(error as? URLError, URLError(.timedOut))
        }
        XCTAssertEqual(auth.listenerCount, 1)

        auth.emitIdentityChange(uid: accountID.uuidString)
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(invalidations.isEmpty)
        XCTAssertEqual(auth.signOutCount, 0)

        auth.replaceCurrentToken(uid: accountID.uuidString, claims: [
            "sideySessionId": sessionID.uuidString,
            "sideyRolloutUntil": NSNumber(value: leaseExpiresAt + 1),
        ])
        auth.emitIdentityChange(uid: accountID.uuidString)
        await fulfillment(of: [invalidated], timeout: 1)
        XCTAssertEqual(invalidations, [.rolloutLeaseMismatch])
        XCTAssertEqual(auth.signOutCount, 1)
        XCTAssertEqual(auth.listenerCount, 0)
    }
}

@MainActor
private final class FakeFirebaseV2AuthSession: FirebaseV2AuthSession {
    struct Token {
        let uid: String
        let claims: [String: Any]
    }

    private let tokens: [String: Token]
    private var currentToken: Token?
    private var listener: (@MainActor (String?) -> Void)?
    private var removedListeners: [(@MainActor (String?) -> Void)] = []
    var signInError: Error?
    private(set) var signOutCount = 0
    var listenerCount: Int { listener == nil ? 0 : 1 }

    init(tokens: [String: Token]) {
        self.tokens = tokens
    }

    func signIn(customToken: String) async throws -> String {
        if let signInError { throw signInError }
        guard let token = tokens[customToken] else { throw URLError(.userAuthenticationRequired) }
        currentToken = token
        // Firebase notifies existing listeners as part of custom-token sign-in.
        listener?(token.uid)
        return token.uid
    }

    func tokenClaims(expectedUID: String) async throws -> [String: Any]? {
        guard let currentToken, currentToken.uid == expectedUID else { return nil }
        return currentToken.claims
    }

    func signOut() throws {
        signOutCount += 1
        currentToken = nil
        listener?(nil)
    }

    func addIDTokenDidChangeListener(
        _ listener: @escaping @MainActor (String?) -> Void
    ) -> NSObjectProtocol {
        self.listener = listener
        return NSObject()
    }

    func removeIDTokenDidChangeListener(_ handle: NSObjectProtocol) {
        if let listener { removedListeners.append(listener) }
        listener = nil
    }

    func emitIdentityChange(uid: String?) {
        listener?(uid)
    }

    func emitMostRecentlyRemovedIdentityChange(uid: String?) {
        removedListeners.last?(uid)
    }

    func replaceCurrentToken(uid: String, claims: [String: Any]) {
        currentToken = Token(uid: uid, claims: claims)
    }
}
