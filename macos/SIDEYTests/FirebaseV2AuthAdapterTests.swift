import XCTest
@testable import SIDEY

final class FirebaseV2AuthAdapterTests: XCTestCase {
    private let nowMilliseconds: Int64 = 1_800_000_000_000
    private let leaseExpiresAt: Int64 = 1_800_000_300_000

    @MainActor
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
}
