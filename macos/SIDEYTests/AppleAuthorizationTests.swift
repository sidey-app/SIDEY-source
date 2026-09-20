import AuthenticationServices
import CryptoKit
import XCTest
@testable import SIDEY

final class AppleAuthorizationTests: XCTestCase {
    func testPrepareCarriesRawNonceInStateAndHashInNonce() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let rawNonce = "sidey-test-nonce"
        let expectedHash = SHA256.hash(data: Data(rawNonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        AppleAuthorization.prepare(request, nonce: rawNonce)

        XCTAssertEqual(request.state, rawNonce)
        XCTAssertEqual(request.nonce, expectedHash)
    }
}
