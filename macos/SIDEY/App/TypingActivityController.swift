import Foundation

/// Owns only transient typing. Message delivery and connection recovery remain independent.
@MainActor
final class TypingActivityController {
    static let startDelay: TimeInterval = 0.5
    static let refreshInterval: TimeInterval = 2
    static let idleInterval: TimeInterval = 5

    private final class Session {
        let roomID: UUID
        var valid = true
        var attempted = false
        var pending = false
        init(roomID: UUID) { self.roomID = roomID }
    }

    private let now: () -> TimeInterval
    private let automaticallySchedule: Bool
    private let publish: @MainActor (UUID, String) async throws -> Void
    private let localTyping: (UUID, Bool) -> Void
    private var session: Session?
    private var firstEdit: TimeInterval = 0
    private var lastEdit: TimeInterval = 0
    private var lastEmission: TimeInterval?
    private var dirty = false
    private var timer: Task<Void, Never>?
    private var outbound: Task<Void, Never>?
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var shutdownWaiter: CheckedContinuation<Void, Never>?
    private var shutdownTimeout: Task<Void, Never>?
    private var isShuttingDown = false

    init(
        now: @escaping () -> TimeInterval,
        automaticallySchedule: Bool = true,
        publish: @escaping @MainActor (UUID, String) async throws -> Void,
        localTyping: @escaping (UUID, Bool) -> Void
    ) {
        self.now = now
        self.automaticallySchedule = automaticallySchedule
        self.publish = publish
        self.localTyping = localTyping
    }

    /// Called only for a user text edit, never for restoring a draft or focusing input.
    func edited(roomID: UUID, hasText: Bool) {
        guard !isShuttingDown else { return }
        guard hasText else { stop(); return }
        if session?.roomID != roomID {
            stop()
            session = Session(roomID: roomID)
            firstEdit = now()
            lastEmission = nil
        }
        lastEdit = now()
        dirty = true
        localTyping(roomID, true)
        processDeadlines()
    }

    func processDeadlines() {
        guard let session else { return }
        let instant = now()
        if instant >= lastEdit + Self.idleInterval {
            stop()
            return
        }
        let due = lastEmission.map { $0 + Self.refreshInterval } ?? (firstEdit + Self.startDelay)
        if dirty && !session.pending && instant >= due {
            let event = lastEmission == nil ? "typing_start" : "typing_keepalive"
            session.pending = true
            enqueue { [weak self, session] in
                guard let self, session.valid else { return }
                guard self.now() < self.lastEdit + Self.idleInterval else {
                    self.stop()
                    return
                }
                // Consume edits at dispatch, not at response completion.
                self.dirty = false
                self.lastEmission = self.now()
                session.attempted = true
                self.scheduleNextDeadline()
                do {
                    try await self.publish(session.roomID, event)
                } catch {
                    // A lost ephemeral event must never become an automatic retry.
                    if session.valid { self.dirty = false }
                }
                session.pending = false
                if session.valid { self.processDeadlines() }
            }
        }
        scheduleNextDeadline()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        guard let stopped = session else { return }
        session = nil
        stopped.valid = false
        dirty = false
        lastEmission = nil
        localTyping(stopped.roomID, false)
        enqueue { [publish, stopped] in
            // The old start may already be in flight. FIFO places this stop after it.
            guard stopped.attempted else { return }
            try? await publish(stopped.roomID, "typing_stop")
        }
    }

    func drain() async {
        await outbound?.value
    }

    /// Give an in-flight start and its stop a bounded grace period, then cancel transport work.
    func shutdown(timeout: Duration = .seconds(2)) async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stop()
        guard !operations.isEmpty else { return }
        await withCheckedContinuation { continuation in
            shutdownWaiter = continuation
            shutdownTimeout = Task { [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                guard let self else { return }
                for operation in operations.values { operation.cancel() }
                finishShutdown()
            }
        }
    }

    private func finishShutdown() {
        shutdownTimeout?.cancel()
        shutdownTimeout = nil
        shutdownWaiter?.resume()
        shutdownWaiter = nil
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = outbound
        let id = UUID()
        let task = Task { [weak self] in
            await previous?.value
            if !Task.isCancelled { await operation() }
            guard let self else { return }
            operations[id] = nil
            if operations.isEmpty { finishShutdown() }
        }
        operations[id] = task
        outbound = task
    }

    private func scheduleNextDeadline() {
        timer?.cancel()
        guard automaticallySchedule, session != nil else { return }
        var deadline = lastEdit + Self.idleInterval
        if dirty && session?.pending == false {
            deadline = min(deadline, lastEmission.map { $0 + Self.refreshInterval } ?? (firstEdit + Self.startDelay))
        }
        let delay = max(0, deadline - now())
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.processDeadlines()
        }
    }
}
