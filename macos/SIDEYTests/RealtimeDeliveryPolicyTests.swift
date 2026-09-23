import XCTest
@testable import SIDEY

final class RealtimeDeliveryPolicyTests: XCTestCase {
    func testAmbiguousTypingWaitsForNaturalStateChangeWithoutRetry() {
        XCTAssertEqual(
            RealtimeTransientDeliveryPolicy.action(for: .typing, outcome: .ambiguous),
            .waitForNaturalStateChange
        )
    }

    func testAmbiguousPulseAndThrowAreDroppedWithoutRetry() {
        XCTAssertEqual(
            RealtimeTransientDeliveryPolicy.action(for: .pulse, outcome: .ambiguous),
            .drop
        )
        XCTAssertEqual(
            RealtimeTransientDeliveryPolicy.action(for: .characterThrow, outcome: .ambiguous),
            .drop
        )
    }

    func testPermissionDenialRequiresAccessRevalidation() {
        for kind in RealtimeTransientKind.allCases {
            XCTAssertEqual(
                RealtimeTransientDeliveryPolicy.action(for: kind, outcome: .permissionDenied),
                .revalidateAccess
            )
        }
    }

    func testAmbiguousChatUsesTargetedLookupInsteadOfResend() {
        XCTAssertEqual(
            RealtimeChatDeliveryPolicy.action(for: .ambiguous),
            .lookupByClientMessageID
        )
        XCTAssertEqual(
            RealtimeChatDeliveryPolicy.action(for: .definitelyRejected),
            .markFailed
        )
        XCTAssertEqual(
            RealtimeChatDeliveryPolicy.action(for: .confirmed),
            .confirm
        )
    }

    func testInitialSequenceCanEstablishBaselineWithoutReplay() {
        var tracker = RealtimeSequenceTracker(initialValueHandling: .establishBaseline)

        XCTAssertEqual(tracker.observe(8), .baseline)
        XCTAssertEqual(tracker.observe(8), .duplicateOrStale)
        XCTAssertEqual(tracker.observe(9), .next)
    }

    func testSequenceGapRequestsAuthoritativeReconciliation() {
        var tracker = RealtimeSequenceTracker(initialValueHandling: .establishBaseline)

        XCTAssertEqual(tracker.observe(4), .baseline)
        XCTAssertEqual(tracker.observe(7), .gap(previous: 4, current: 7))
        XCTAssertEqual(tracker.observe(6), .duplicateOrStale)
    }
}
