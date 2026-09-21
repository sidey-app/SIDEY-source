import Foundation

struct StorePreviewScenario: Equatable, Sendable {
    static let roomID = UUID(uuidString: "83DCA9FA-DFB8-4AEF-B851-9655195D41C1")!
    static let mokaID = UUID(uuidString: "D5F0D9BB-FBDA-4B10-AEF9-A7E2A4CFBD25")!
    static let dubuID = UUID(uuidString: "26E5237A-69A1-4EA7-868E-822C831069B6")!
    let productID: String
    let members: [PixelWorldMember]
    let bubbles: [ActiveBubble]
    let initialTrackFractions: [UUID: CGFloat]
    let fixedTrackFractions: [UUID: CGFloat]
    let bubbleSequence: StorePreviewBubbleSequence?
    let throwSequence: StorePreviewThrowSequence?
    let characterThrowInteraction: StorePreviewCharacterThrowInteraction?

    static func make(product: CommerceProduct) -> Self {
        switch product.kind {
        case .character:
            let characterID = product.characterID ?? PixelCharacterCatalog.pixelHamsterID
            return Self(
                productID: product.id,
                members: [
                    moka(characterID: characterID),
                    dubu(characterID: "pixel_cat")
                ],
                bubbles: [],
                initialTrackFractions: [mokaID: 0.22, dubuID: 0.78],
                fixedTrackFractions: [:],
                bubbleSequence: nil,
                throwSequence: nil,
                characterThrowInteraction: StorePreviewCharacterThrowInteraction(
                    roomID: roomID,
                    actorMemberID: mokaID,
                    targetMemberID: dubuID,
                    sourceCharacterID: characterID,
                    throwableID: CommerceCatalog.keepsake(for: product.id)?.renderAssetID
                        ?? PixelCharacterThrowCatalog.fallbackObjectID
                )
            )
        case .bubble:
            let sequence = StorePreviewBubbleSequence(
                leftMemberID: mokaID,
                rightMemberID: dubuID,
                bubbleStyleID: product.catalogItemID
            )
            return Self(
                productID: product.id,
                members: [
                    moka(characterID: PixelCharacterCatalog.pixelHamsterID),
                    dubu(characterID: "pixel_cat")
                ],
                bubbles: [],
                initialTrackFractions: [mokaID: 0.28, dubuID: 0.72],
                fixedTrackFractions: [:],
                bubbleSequence: sequence,
                throwSequence: nil,
                characterThrowInteraction: nil
            )
        case .throwable:
            let members = [
                moka(characterID: PixelCharacterCatalog.pixelHamsterID),
                dubu(characterID: "pixel_cat")
            ]
            return Self(
                productID: product.id,
                members: members,
                bubbles: [],
                initialTrackFractions: [:],
                fixedTrackFractions: [mokaID: 0.22, dubuID: 0.78],
                bubbleSequence: nil,
                throwSequence: StorePreviewThrowSequence(
                    roomID: roomID,
                    leftMemberID: mokaID,
                    rightMemberID: dubuID,
                    throwableID: product.catalogItemID
                ),
                characterThrowInteraction: nil
            )
        }
    }

    private static func moka(characterID: String) -> PixelWorldMember {
        PixelWorldMember(
            id: mokaID,
            nickname: L10n.text("store.preview.member.moka"),
            characterID: characterID,
            presence: .online,
            isTyping: false,
            isCurrentUser: false
        )
    }

    private static func dubu(characterID: String) -> PixelWorldMember {
        PixelWorldMember(
            id: dubuID,
            nickname: L10n.text("store.preview.member.dubu"),
            characterID: characterID,
            presence: .online,
            isTyping: false,
            isCurrentUser: false
        )
    }
}

struct StorePreviewCharacterThrowInteraction: Equatable, Sendable {
    let roomID: UUID
    let actorMemberID: UUID
    let targetMemberID: UUID
    let sourceCharacterID: String
    let throwableID: String

    func event(targetMemberID: UUID, id: UUID = UUID()) -> CharacterThrowEvent? {
        guard targetMemberID == self.targetMemberID else { return nil }
        return CharacterThrowEvent(
            id: id,
            roomID: roomID,
            actorUserID: actorMemberID,
            targetUserID: targetMemberID,
            sourceCharacterID: sourceCharacterID,
            throwableID: throwableID
        )
    }
}

struct StorePreviewBubbleSequence: Equatable, Sendable {
    static let typingDuration: TimeInterval = 1
    static let messageDuration: TimeInterval = 2
    static let cycleDuration = 2 * (typingDuration + messageDuration)
    static var leftBody: String { L10n.text("store.preview.message.left") }
    static var rightBody: String { L10n.text("store.preview.message.right") }
    private static let leftMessageID = UUID(uuidString: "08A6BBCF-45BD-45D6-A373-3056DE9A5CBA")!
    private static let rightMessageID = UUID(uuidString: "87793D0B-A870-4D96-930D-BE1465A1BB92")!

    let leftMemberID: UUID
    let rightMemberID: UUID
    let bubbleStyleID: String

    func scheduledOffset(for index: Int) -> TimeInterval {
        let normalizedIndex = max(0, index)
        let cycle = normalizedIndex / 4
        let phase = normalizedIndex % 4
        let phaseOffset: TimeInterval = switch phase {
        case 0: 0
        case 1: Self.typingDuration
        case 2: Self.typingDuration + Self.messageDuration
        default: Self.typingDuration * 2 + Self.messageDuration
        }
        return Double(cycle) * Self.cycleDuration + phaseOffset
    }

    func presentation(at index: Int) -> StorePreviewBubblePresentation {
        let phase = max(0, index) % 4
        let usesLeftMember = phase < 2
        let senderID = usesLeftMember ? leftMemberID : rightMemberID
        guard !phase.isMultiple(of: 2) else {
            return StorePreviewBubblePresentation(
                senderID: senderID,
                isTyping: true,
                bubble: nil
            )
        }
        return StorePreviewBubblePresentation(
            senderID: senderID,
            isTyping: false,
            bubble: ActiveBubble(
                senderID: senderID,
                messageID: usesLeftMember ? Self.leftMessageID : Self.rightMessageID,
                body: usesLeftMember ? Self.leftBody : Self.rightBody,
                expiresAt: .distantFuture,
                bubbleStyleID: bubbleStyleID
            )
        )
    }
}

struct StorePreviewBubblePresentation: Equatable, Sendable {
    let senderID: UUID
    let isTyping: Bool
    let bubble: ActiveBubble?
}

struct StorePreviewThrowSequence: Equatable, Sendable {
    static let firstDelay: TimeInterval = 0.35
    static let repeatInterval: TimeInterval = 1

    let roomID: UUID
    let leftMemberID: UUID
    let rightMemberID: UUID
    let throwableID: String

    func scheduledOffset(for index: Int) -> TimeInterval {
        Self.firstDelay + Double(max(0, index)) * Self.repeatInterval
    }

    func event(at index: Int, id: UUID = UUID()) -> CharacterThrowEvent {
        let throwsLeftToRight = index.isMultiple(of: 2)
        let actorID = throwsLeftToRight ? leftMemberID : rightMemberID
        let targetID = throwsLeftToRight ? rightMemberID : leftMemberID
        let sourceCharacterID = throwsLeftToRight
            ? PixelCharacterCatalog.pixelHamsterID
            : "pixel_cat"
        return CharacterThrowEvent(
            id: id,
            roomID: roomID,
            actorUserID: actorID,
            targetUserID: targetID,
            sourceCharacterID: sourceCharacterID,
            throwableID: throwableID
        )
    }
}
