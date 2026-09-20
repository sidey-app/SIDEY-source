import XCTest
@testable import SIDEYAppStore

@MainActor
final class TypingActivityTests: XCTestCase {
    @MainActor
    private final class Harness {
        var time: TimeInterval = 0
        var sent: [String] = []
        var rooms: [UUID] = []
        var local: [Bool] = []
        var fail = false
        var heldStart: CheckedContinuation<Void, Never>?
        var holdStart = false
        var started: XCTestExpectation?
        lazy var controller = TypingActivityController(
            now: { [unowned self] in time }, automaticallySchedule: false,
            publish: { [unowned self] room, event in
                sent.append(event)
                rooms.append(room)
                if holdStart && event == "typing_start" {
                    await withCheckedContinuation { heldStart = $0; started?.fulfill() }
                }
                if fail { throw URLError(.timedOut) }
            },
            localTyping: { [unowned self] _, active in local.append(active) }
        )
        func advance(_ value: TimeInterval) async {
            time = value
            controller.processDeadlines()
            await controller.drain()
        }
    }

    func testSendOrCancelBeforeDelayProducesNoRemoteStart() async {
        for endAt in [0.0, 0.1, 0.499] {
            let h = Harness()
            h.controller.edited(roomID: UUID(), hasText: true)
            XCTAssertEqual(h.local, [true])
            h.time = endAt
            h.controller.stop()
            await h.advance(10)
            XCTAssertEqual(h.sent, [])
            XCTAssertEqual(h.local, [true, false])
        }
    }

    func testContinuousEditsDoNotPostponeStartAndRefreshNeedsNewEdits() async {
        let h = Harness(), room = UUID()
        h.controller.edited(roomID: room, hasText: true)
        for instant in [0.1, 0.2, 0.4] {
            h.time = instant
            h.controller.edited(roomID: room, hasText: true)
        }
        await h.advance(0.5)
        XCTAssertEqual(h.sent, ["typing_start"])
        await h.advance(2.5)
        XCTAssertEqual(h.sent.count, 1, "Timer ticks without editing cannot refresh")
        h.time = 2.6
        h.controller.edited(roomID: room, hasText: true)
        await h.controller.drain()
        XCTAssertEqual(h.sent, ["typing_start", "typing_keepalive"])
        h.time = 2.7
        h.controller.edited(roomID: room, hasText: true)
        await h.advance(4.59)
        XCTAssertEqual(h.sent.count, 2)
        await h.advance(4.6)
        XCTAssertEqual(h.sent.count, 3)
        await h.advance(7.7)
        XCTAssertEqual(h.sent.last, "typing_stop")
        XCTAssertEqual(h.local.last, false)
    }

    func testIdleDeadlineIsLastEditPlusFiveSeconds() async {
        let h = Harness()
        h.controller.edited(roomID: UUID(), hasText: true)
        await h.advance(0.5)
        await h.advance(4.99)
        XCTAssertEqual(h.sent, ["typing_start"])
        await h.advance(5)
        XCTAssertEqual(h.sent, ["typing_start", "typing_stop"])
    }

    func testStopDuringDelayedStartIsSentAfterStartCompletes() async {
        let h = Harness(), room = UUID()
        h.holdStart = true
        h.started = expectation(description: "Start entered transport")
        h.controller.edited(roomID: room, hasText: true)
        h.time = 0.5
        h.controller.processDeadlines()
        await fulfillment(of: [h.started!], timeout: 2)
        h.controller.stop()
        XCTAssertEqual(h.local.last, false)
        h.heldStart?.resume()
        await h.controller.drain()
        XCTAssertEqual(h.sent, ["typing_start", "typing_stop"])
        XCTAssertEqual(h.rooms, [room, room])
    }

    func testRoomSwitchDropsQueuedStartAndStopsOriginalRoom() async {
        let h = Harness(), first = UUID(), second = UUID()
        h.holdStart = true
        h.started = expectation(description: "Start entered transport")
        h.controller.edited(roomID: first, hasText: true)
        h.time = 0.5
        h.controller.processDeadlines()
        await fulfillment(of: [h.started!], timeout: 2)
        h.controller.edited(roomID: second, hasText: true)
        h.time = 1
        h.controller.processDeadlines()
        h.controller.stop()
        h.heldStart?.resume()
        await h.controller.drain()
        XCTAssertEqual(h.sent, ["typing_start", "typing_stop"])
        XCTAssertEqual(h.rooms, [first, first])
    }

    func testFailureDoesNotRetryWithoutAnotherRealEdit() async {
        let h = Harness(), room = UUID()
        h.fail = true
        h.controller.edited(roomID: room, hasText: true)
        await h.advance(0.5)
        await h.advance(2.5)
        XCTAssertEqual(h.sent.count, 1)
        h.fail = false
        h.time = 3
        h.controller.edited(roomID: room, hasText: true)
        await h.controller.drain()
        XCTAssertEqual(h.sent.count, 2)
        h.controller.edited(roomID: room, hasText: false)
        await h.controller.drain()
        XCTAssertEqual(h.sent.last, "typing_stop")
    }

    func testShutdownCancelsCooperativeTransportWithinGracePeriod() async {
        let entered = expectation(description: "Transport started")
        let cancelled = expectation(description: "Transport cancelled")
        var instant = 0.0
        let controller = TypingActivityController(
            now: { instant }, automaticallySchedule: false,
            publish: { _, event in
                guard event == "typing_start" else { return }
                entered.fulfill()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled.fulfill(); throw error }
            }, localTyping: { _, _ in }
        )
        controller.edited(roomID: UUID(), hasText: true)
        instant = 0.5
        controller.processDeadlines()
        await fulfillment(of: [entered], timeout: 2)
        await controller.shutdown(timeout: .milliseconds(20))
        await fulfillment(of: [cancelled], timeout: 2)
        await controller.drain()
    }

    func testSlowRequestCannotAccumulateRefreshesOrExtendIdleDeadline() async {
        let h = Harness(), room = UUID()
        h.holdStart = true
        h.started = expectation(description: "Start entered transport")
        h.controller.edited(roomID: room, hasText: true)
        h.time = 0.5
        h.controller.processDeadlines()
        await fulfillment(of: [h.started!], timeout: 2)
        for instant in [1.0, 3.0, 5.0] {
            h.time = instant
            h.controller.edited(roomID: room, hasText: true)
        }
        h.time = 10
        h.controller.processDeadlines()
        XCTAssertEqual(h.local.last, false)
        h.heldStart?.resume()
        await h.controller.drain()
        XCTAssertEqual(h.sent, ["typing_start", "typing_stop"])
    }
}
