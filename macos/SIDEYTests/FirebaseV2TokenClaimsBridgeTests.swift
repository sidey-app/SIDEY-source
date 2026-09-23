import Foundation
import XCTest
@testable import SIDEY

@MainActor
final class FirebaseV2TokenClaimsBridgeTests: XCTestCase {
    func testSuccessfulCallbackPreservesClaimValues() async throws {
        let lease = NSNumber(value: Int64(1_800_000_300_000))
        let claims = try await FirebaseV2TokenClaimsBridge.load { completion in
            completion([
                "sideySessionId": "fixture-session",
                "sideyRolloutUntil": lease,
                "enabled": NSNumber(value: true),
                "firebase": ["sign_in_provider": "custom"],
            ], nil)
        }

        XCTAssertEqual(claims["sideySessionId"] as? String, "fixture-session")
        XCTAssertEqual(claims["sideyRolloutUntil"] as? NSNumber, lease)
        XCTAssertEqual(claims["enabled"] as? NSNumber, NSNumber(value: true))
        XCTAssertEqual(claims["firebase"] as? [String: String], ["sign_in_provider": "custom"])
    }

    func testFailedCallbackPropagatesOriginalError() async {
        let expected = NSError(
            domain: "FirebaseTokenClaimsFixture", code: 17,
            userInfo: [NSLocalizedDescriptionKey: "Fixture token refresh failed"]
        )

        do {
            _ = try await FirebaseV2TokenClaimsBridge.load { completion in
                completion(nil, expected)
            }
            XCTFail("A failed token request must not return claims")
        } catch {
            let actual = error as NSError
            XCTAssertEqual(actual.domain, expected.domain)
            XCTAssertEqual(actual.code, expected.code)
            XCTAssertEqual(actual.localizedDescription, expected.localizedDescription)
        }
    }

    func testCallbackWithoutClaimsOrErrorFailsClosed() async {
        do {
            _ = try await FirebaseV2TokenClaimsBridge.load { completion in
                completion(nil, nil)
            }
            XCTFail("Missing token claims must fail validation")
        } catch {
            XCTAssertEqual(error as? FirebaseV2AuthError, .tokenRefreshValidationFailed)
        }
    }

    func testOverlappingRequestsKeepIndependentClaimsWhenCompletedInReverseOrder() async throws {
        let firstStarted = expectation(description: "first request registered")
        let secondStarted = expectation(description: "second request registered")
        let finished = expectation(description: "both requests returned their own claims")
        finished.expectedFulfillmentCount = 2
        var firstCompletion: (@MainActor ([String: Any]?, Error?) -> Void)?
        var secondCompletion: (@MainActor ([String: Any]?, Error?) -> Void)?
        defer {
            // Release any pending continuation if registration assertions fail.
            firstCompletion?(nil, FirebaseV2AuthError.tokenRefreshValidationFailed)
            secondCompletion?(nil, FirebaseV2AuthError.tokenRefreshValidationFailed)
        }

        Task { @MainActor in
            defer { finished.fulfill() }
            do {
                let claims = try await FirebaseV2TokenClaimsBridge.load { completion in
                    firstCompletion = completion
                    firstStarted.fulfill()
                }
                XCTAssertEqual(claims["sideySessionId"] as? String, "first")
                XCTAssertEqual(claims["sideyRolloutUntil"] as? NSNumber, NSNumber(value: 100))
            } catch {
                XCTFail("First request unexpectedly failed: \(error)")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)

        Task { @MainActor in
            defer { finished.fulfill() }
            do {
                let claims = try await FirebaseV2TokenClaimsBridge.load { completion in
                    secondCompletion = completion
                    secondStarted.fulfill()
                }
                XCTAssertEqual(claims["sideySessionId"] as? String, "second")
                XCTAssertEqual(claims["sideyRolloutUntil"] as? NSNumber, NSNumber(value: 200))
            } catch {
                XCTFail("Second request unexpectedly failed: \(error)")
            }
        }
        await fulfillment(of: [secondStarted], timeout: 2)

        let completeSecond = try XCTUnwrap(secondCompletion)
        let completeFirst = try XCTUnwrap(firstCompletion)
        secondCompletion = nil
        firstCompletion = nil
        // Resume both before either task can read the result, exposing shared storage bugs.
        completeSecond(["sideySessionId": "second", "sideyRolloutUntil": NSNumber(value: 200)], nil)
        completeFirst(["sideySessionId": "first", "sideyRolloutUntil": NSNumber(value: 100)], nil)
        await fulfillment(of: [finished], timeout: 2)
    }
}
