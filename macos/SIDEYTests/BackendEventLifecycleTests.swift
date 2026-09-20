import Synchronization
import XCTest
@testable import SIDEYAppStore

@MainActor
final class BackendEventLifecycleTests: XCTestCase {
    func testRepeatedStartKeepsStreamAliveAndDeliversEachEventOnce() async throws {
        let savedNicknames = Mutex<[String]>([])
        let coordinator = makeCoordinator(preferencesStore: PreferencesStore(
            load: { .defaults },
            save: { preferences in
                savedNicknames.withLock { $0.append(preferences.nickname) }
            }
        ))
        let (events, continuation) = AsyncStream<BackendEvent>.makeStream()
        defer {
            continuation.finish()
            coordinator.shutdown()
        }

        coordinator.startBackendEventHandling(events)
        let firstTask = try XCTUnwrap(coordinator.roomSession.eventTask)
        // A second start before the task runs must also be harmless.
        coordinator.startBackendEventHandling(events)
        XCTAssertEqual(coordinator.roomSession.eventTask, firstTask)

        continuation.yield(.technicalError("before login"))
        try await waitUntil { coordinator.model.errorMessage == "before login" }

        // Model the restart after Apple authentication with a suspended consumer.
        coordinator.startBackendEventHandling(events)
        XCTAssertEqual(coordinator.roomSession.eventTask, firstTask)
        XCTAssertFalse(firstTask.isCancelled)

        let userID = UUID()
        for nickname in ["첫째", "둘째"] {
            let result = continuation.yield(.snapshot(BackendSnapshot(
                profile: Profile(id: userID, nickname: nickname, characterID: "pixel_hamster"),
                rooms: []
            )))
            guard case .enqueued = result else {
                XCTFail("Restart terminated or dropped a backend event")
                return
            }
        }
        continuation.finish()
        try await waitUntil { coordinator.roomSession.eventTask == nil }

        XCTAssertEqual(savedNicknames.withLock { $0 }, ["첫째", "둘째"])
        XCTAssertEqual(coordinator.model.nickname, "둘째")
        XCTAssertFalse(firstTask.isCancelled)
    }

    func testShutdownCancelsReceiverAndClearsTask() async throws {
        let coordinator = makeCoordinator()
        let (events, continuation) = AsyncStream<BackendEvent>.makeStream()
        defer { continuation.finish() }
        coordinator.startBackendEventHandling(events)
        let task = try XCTUnwrap(coordinator.roomSession.eventTask)
        continuation.yield(.technicalError("received"))
        try await waitUntil { coordinator.model.errorMessage == "received" }

        coordinator.shutdown()
        try await waitUntil { coordinator.roomSession.eventTask == nil }

        XCTAssertTrue(task.isCancelled)
        guard case .terminated = continuation.yield(.technicalError("after shutdown")) else {
            XCTFail("Shutdown must terminate the event stream")
            return
        }
        XCTAssertEqual(coordinator.model.errorMessage, "received")
    }

    func testShutdownBeforeReceiverRunsStillClearsTask() async throws {
        let coordinator = makeCoordinator()
        let (events, continuation) = AsyncStream<BackendEvent>.makeStream()
        defer { continuation.finish() }
        coordinator.startBackendEventHandling(events)
        continuation.yield(.technicalError("must not be handled"))

        coordinator.shutdown()
        try await waitUntil { coordinator.roomSession.eventTask == nil }

        XCTAssertNil(coordinator.model.errorMessage)
    }

    private func makeCoordinator(
        preferencesStore: PreferencesStore = PreferencesStore(load: { .defaults }, save: { _ in })
    ) -> AppCoordinator {
        AppCoordinator(

            preferencesStore: preferencesStore,
            legacyMigrator: .none,
            keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .appStore,
            arguments: []
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Backend event receiver did not reach the expected state")
                throw EventReceiverTimeout()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct EventReceiverTimeout: Error {}
