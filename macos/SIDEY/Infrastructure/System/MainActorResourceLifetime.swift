import Foundation

/// Keeps native resources alive until their cleanup has run on the main actor.
/// Avoids isolated-deinit runtime bugs on older supported versions of macOS.
@MainActor
final class MainActorResourceLifetime<Resource> {
    let resource: Resource
    private let cleanup: @MainActor @Sendable () -> Void

    init(_ resource: Resource, cleanup: @escaping @MainActor @Sendable (Resource) -> Void) {
        self.resource = resource
        // Capture the resource, never this owner: an off-main release must retain only
        // the cleanup payload until the main actor can dispose of it.
        self.cleanup = { cleanup(resource) }
    }

    nonisolated deinit {
        let action = cleanup
        if Thread.isMainThread {
            MainActor.assumeIsolated { action() }
        } else {
            Task { @MainActor in action() }
        }
    }
}
