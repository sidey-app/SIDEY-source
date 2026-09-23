import XCTest
@testable import SIDEY

final class FirebaseV2SupabaseSessionTests: XCTestCase {
    func testDecodesAccountAndSessionWithoutExposingTokenInDescription() throws {
        let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let token = try jwt([
            "sub": accountID.uuidString.lowercased(),
            "session_id": sessionID.uuidString.lowercased(),
        ])

        let session = try FirebaseV2SupabaseSessionDecoder.decode(
            accessToken: token,
            expectedAccountID: accountID
        )

        XCTAssertEqual(session.identity.accountID, accountID)
        XCTAssertEqual(session.identity.sessionID, sessionID)
        XCTAssertEqual(session.accessToken, token)
        XCTAssertFalse(session.description.contains(token))
        XCTAssertFalse(session.debugDescription.contains(token))
    }

    func testRejectsDifferentAccountAndMissingSessionClaim() throws {
        let expected = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let different = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let sessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        XCTAssertThrowsError(try FirebaseV2SupabaseSessionDecoder.decode(
            accessToken: try jwt([
                "sub": different.uuidString,
                "session_id": sessionID.uuidString,
            ]),
            expectedAccountID: expected
        )) { error in
            XCTAssertEqual(error as? FirebaseV2SupabaseSessionError, .accountMismatch)
        }
        XCTAssertThrowsError(try FirebaseV2SupabaseSessionDecoder.decode(
            accessToken: try jwt(["sub": expected.uuidString]),
            expectedAccountID: expected
        )) { error in
            XCTAssertEqual(error as? FirebaseV2SupabaseSessionError, .missingSessionID)
        }
    }

    func testRejectsMalformedJWT() {
        XCTAssertThrowsError(try FirebaseV2SupabaseSessionDecoder.decode(
            accessToken: "not-a-jwt",
            expectedAccountID: UUID()
        )) { error in
            XCTAssertEqual(error as? FirebaseV2SupabaseSessionError, .malformedToken)
        }
    }

    private func jwt(_ payload: [String: String]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
        let body = try JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(header)).\(base64URL(body)).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
