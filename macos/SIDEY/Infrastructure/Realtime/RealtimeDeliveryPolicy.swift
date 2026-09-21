import Foundation

enum RealtimeTransientKind: CaseIterable, Equatable, Sendable {
    case typing
    case pulse
    case characterThrow
}

enum RealtimeTransientDeliveryOutcome: Equatable, Sendable {
    case accepted
    case definitelyRejected
    case permissionDenied
    case ambiguous
}

enum RealtimeTransientRecoveryAction: Equatable, Sendable {
    case none
    case waitForNaturalStateChange
    case drop
    case revalidateAccess
}

enum RealtimeTransientDeliveryPolicy {
    static func action(
        for kind: RealtimeTransientKind,
        outcome: RealtimeTransientDeliveryOutcome
    ) -> RealtimeTransientRecoveryAction {
        switch outcome {
        case .accepted:
            .none
        case .permissionDenied:
            .revalidateAccess
        case .definitelyRejected:
            .drop
        case .ambiguous:
            kind == .typing ? .waitForNaturalStateChange : .drop
        }
    }
}

enum RealtimeChatDeliveryOutcome: Equatable, Sendable {
    case confirmed
    case definitelyRejected
    case ambiguous
}

enum RealtimeChatRecoveryAction: Equatable, Sendable {
    case confirm
    case markFailed
    case lookupByClientMessageID
}

enum RealtimeChatDeliveryPolicy {
    static func action(for outcome: RealtimeChatDeliveryOutcome) -> RealtimeChatRecoveryAction {
        switch outcome {
        case .confirmed:
            .confirm
        case .definitelyRejected:
            .markFailed
        case .ambiguous:
            .lookupByClientMessageID
        }
    }
}

enum InitialRealtimeValueHandling: Equatable, Sendable {
    case establishBaseline
    case deliverCurrent
}

enum RealtimeSequenceObservation: Equatable, Sendable {
    case baseline
    case next
    case gap(previous: Int, current: Int)
    case duplicateOrStale
}

struct RealtimeSequenceTracker: Equatable, Sendable {
    let initialValueHandling: InitialRealtimeValueHandling
    private(set) var latest: Int?

    init(initialValueHandling: InitialRealtimeValueHandling) {
        self.initialValueHandling = initialValueHandling
    }

    mutating func observe(_ value: Int) -> RealtimeSequenceObservation {
        guard value > 0 else { return .duplicateOrStale }
        guard let latest else {
            self.latest = value
            return initialValueHandling == .establishBaseline ? .baseline : .next
        }
        guard value > latest else { return .duplicateOrStale }
        self.latest = value
        guard value == latest + 1 else {
            return .gap(previous: latest, current: value)
        }
        return .next
    }
}
