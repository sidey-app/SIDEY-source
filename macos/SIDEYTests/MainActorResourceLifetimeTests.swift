import Foundation
import XCTest
@testable import SIDEY

@MainActor
final class MainActorResourceLifetimeTests: XCTestCase {
    func testMainThreadReleaseCleansResourcesSynchronouslyOnce() {
        let resource = CleanupResource()
        var lifetime: MainActorResourceLifetime<CleanupResource>? = .init(resource) { value in
            XCTAssertTrue(Thread.isMainThread)
            value.cleanupCount += 1
        }
        XCTAssertTrue(lifetime?.resource === resource)
        XCTAssertEqual(resource.cleanupCount, 0)

        lifetime = nil

        XCTAssertEqual(resource.cleanupCount, 1)
    }

    func testBackgroundReleaseRetainsResourcesUntilMainActorCleanup() async {
        let cleaned = expectation(description: "resource cleaned on main actor")
        let released = expectation(description: "resource released after cleanup")
        let probe = CleanupProbe()

        await Task.detached {
            var lifetime: MainActorResourceLifetime<CleanupResource>? = await MainActor.run {
                let resource = CleanupResource(onRelease: { released.fulfill() })
                probe.resource = resource
                return MainActorResourceLifetime(resource) { value in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(probe.resource === value)
                    value.cleanupCount += 1
                    probe.cleanupCount = value.cleanupCount
                    cleaned.fulfill()
                }
            }
            XCTAssertNotNil(lifetime)
            XCTAssertFalse(Thread.isMainThread)
            lifetime = nil
        }.value

        await fulfillment(of: [cleaned, released], timeout: 2, enforceOrder: true)
        XCTAssertEqual(probe.cleanupCount, 1)
        XCTAssertNil(probe.resource)
    }
}

@MainActor
private final class CleanupProbe {
    weak var resource: CleanupResource?
    var cleanupCount = 0
}

private final class CleanupResource {
    var cleanupCount = 0
    let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void = {}) {
        self.onRelease = onRelease
    }

    deinit { onRelease() }
}
