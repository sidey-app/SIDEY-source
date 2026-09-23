import AppKit

enum PixelBubbleTailAttachment: Equatable, Sendable {
    case bottom
    case left
    case right
}

struct PixelBubbleLayout: Equatable, Sendable {
    let size: CGSize
    let nodePosition: CGPoint
    let nodeRotation: CGFloat
    let labelRotation: CGFloat
    let tailTip: CGPoint
    let tailAttachment: PixelBubbleTailAttachment
    let bodyFrame: CGRect
    let totalFrame: CGRect

    static func make(
        text: String,
        isTyping: Bool,
        tangentPosition: CGFloat,
        tangentLength: CGFloat,
        edge: OverlayEdge,
        bodyMinY: CGFloat = 52,
        includesTail: Bool = true,
        leadingDecorationOverflow: CGFloat = 0,
        maximumContentWidth: CGFloat? = nil
    ) -> Self {
        let maximumWidth = min(220, max(24, maximumContentWidth ?? (tangentLength - 16)))
        let size: CGSize
        if isTyping {
            size = CGSize(width: min(42, maximumWidth), height: 30)
        } else {
            size = PixelBubbleMeasurementCache.shared.size(
                text: text,
                maximumWidth: maximumWidth
            )
        }

        let nodeRotation = edge.bubbleCounterRotation
        let bodyRect = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
        let transform = CGAffineTransform(rotationAngle: nodeRotation)
        let relativeBodyFrame = bodyRect.applying(transform)
        var relativeVisualFrame = relativeBodyFrame
        if leadingDecorationOverflow > 0 {
            let decorationFrame = CGRect(
                x: bodyRect.minX - leadingDecorationOverflow,
                y: bodyRect.maxY - PixelBubbleStyle.decorationSize / 2,
                width: PixelBubbleStyle.decorationSize,
                height: PixelBubbleStyle.decorationSize
            )
            relativeVisualFrame = relativeVisualFrame.union(decorationFrame.applying(transform))
        }

        let tangentSign: CGFloat = switch edge {
        case .bottom, .right: 1
        case .top, .left: -1
        }
        let firstVisualDelta = relativeVisualFrame.minX * tangentSign
        let secondVisualDelta = relativeVisualFrame.maxX * tangentSign
        let minimumVisualDelta = min(firstVisualDelta, secondVisualDelta)
        let maximumVisualDelta = max(firstVisualDelta, secondVisualDelta)
        let minimumCenter = 4 - minimumVisualDelta
        let maximumCenter = tangentLength - 4 - maximumVisualDelta
        let worldCenter = min(
            max(tangentPosition, minimumCenter),
            max(minimumCenter, maximumCenter)
        )
        let localCenterX = (worldCenter - tangentPosition) * tangentSign
        let nodePosition = CGPoint(
            x: localCenterX,
            y: bodyMinY - relativeBodyFrame.minY
        )
        let bodyFrame = relativeBodyFrame.offsetBy(dx: nodePosition.x, dy: nodePosition.y)
        let visualFrame = relativeVisualFrame.offsetBy(dx: nodePosition.x, dy: nodePosition.y)
        let tailTarget = CGPoint(x: 0, y: 44)
        let tailTip = CGPoint(
            x: tailTarget.x - nodePosition.x,
            y: tailTarget.y - nodePosition.y
        ).applying(CGAffineTransform(rotationAngle: -nodeRotation))
        let totalFrame: CGRect
        if includesTail {
            totalFrame = visualFrame.union(CGRect(
                origin: tailTarget,
                size: CGSize(width: 0.001, height: 0.001)
            ))
        } else {
            totalFrame = visualFrame
        }
        let tailAttachment: PixelBubbleTailAttachment = switch edge {
        case .left: .left
        case .right: .right
        case .bottom, .top: .bottom
        }
        return Self(
            size: size,
            nodePosition: nodePosition,
            nodeRotation: nodeRotation,
            labelRotation: edge.readableContentCounterRotation,
            tailTip: tailTip,
            tailAttachment: tailAttachment,
            bodyFrame: bodyFrame,
            totalFrame: totalFrame
        )
    }

    var tailTipInPresentation: CGPoint {
        let rotatedTip = tailTip.applying(CGAffineTransform(rotationAngle: nodeRotation))
        return CGPoint(
            x: rotatedTip.x + nodePosition.x,
            y: rotatedTip.y + nodePosition.y
        )
    }

    func bodyTangentRange(at tangentPosition: CGFloat, edge: OverlayEdge) -> ClosedRange<CGFloat> {
        let tangentSign: CGFloat = switch edge {
        case .bottom, .right: 1
        case .top, .left: -1
        }
        let first = tangentPosition + bodyFrame.minX * tangentSign
        let second = tangentPosition + bodyFrame.maxX * tangentSign
        return min(first, second)...max(first, second)
    }
}

struct PixelBubbleStackEntry: Equatable, Sendable {
    let bubble: ActiveBubble
    let layout: PixelBubbleLayout
    let includesTail: Bool
}

enum PixelBubbleStackLayout {
    static let bodySpacing: CGFloat = 6

    static func make(
        bubbles: [ActiveBubble],
        tangentPosition: CGFloat,
        tangentLength: CGFloat,
        edge: OverlayEdge,
        inwardNormalLength: CGFloat? = nil
    ) -> [PixelBubbleStackEntry] {
        let ordered = bubbles.sorted(by: ActiveBubble.presentationOrder)
        let visible = Array(ordered.suffix(ActiveBubbleLedger.maximumVisiblePerSender))
        let decorationOverflow: CGFloat = switch edge {
        case .right:
            visible.reduce(CGFloat.zero) { total, bubble in
                total + (PixelBubbleTheme.resolve(bubble.bubbleStyleID).decorationAssetName == nil
                    ? 0
                    : PixelBubbleStyle.decorationLeadingOverflow)
            }
        case .left:
            visible.dropLast().reduce(CGFloat.zero) { total, bubble in
                total + (PixelBubbleTheme.resolve(bubble.bubbleStyleID).decorationAssetName == nil
                    ? 0
                    : PixelBubbleStyle.decorationLeadingOverflow)
            }
        case .bottom, .top:
            0
        }
        let maximumContentWidth: CGFloat? = if !edge.isHorizontal,
                                               let inwardNormalLength,
                                               !visible.isEmpty {
            max(
                24,
                min(
                    220,
                    (inwardNormalLength - 52 - bodySpacing * CGFloat(visible.count - 1) - 4
                        - decorationOverflow) / CGFloat(visible.count)
                )
            )
        } else {
            nil
        }
        var nextBodyMinY: CGFloat = 52
        var reversedEntries: [PixelBubbleStackEntry] = []

        for bubble in visible.reversed() {
            let isLatest = bubble.messageID == ordered.last?.messageID
            let decorationLeadingOverflow = PixelBubbleTheme.resolve(bubble.bubbleStyleID)
                .decorationAssetName == nil ? 0 : PixelBubbleStyle.decorationLeadingOverflow
            var layout = PixelBubbleLayout.make(
                text: bubble.body,
                isTyping: false,
                tangentPosition: tangentPosition,
                tangentLength: tangentLength,
                edge: edge,
                bodyMinY: nextBodyMinY,
                includesTail: isLatest,
                leadingDecorationOverflow: decorationLeadingOverflow,
                maximumContentWidth: maximumContentWidth
            )
            if !edge.isHorizontal, !reversedEntries.isEmpty {
                let leadingVisualOverflow = max(0, layout.bodyFrame.minY - layout.totalFrame.minY)
                if leadingVisualOverflow > 0 {
                    layout = PixelBubbleLayout.make(
                        text: bubble.body,
                        isTyping: false,
                        tangentPosition: tangentPosition,
                        tangentLength: tangentLength,
                        edge: edge,
                        bodyMinY: nextBodyMinY + leadingVisualOverflow,
                        includesTail: isLatest,
                        leadingDecorationOverflow: decorationLeadingOverflow,
                        maximumContentWidth: maximumContentWidth
                    )
                }
            }
            reversedEntries.append(PixelBubbleStackEntry(
                bubble: bubble,
                layout: layout,
                includesTail: isLatest
            ))
            nextBodyMinY = (edge.isHorizontal ? layout.bodyFrame.maxY : layout.totalFrame.maxY)
                + bodySpacing
        }

        return Array(reversedEntries.reversed())
    }

    static func bodyTangentRange(
        for entries: [PixelBubbleStackEntry],
        at tangentPosition: CGFloat,
        edge: OverlayEdge
    ) -> ClosedRange<CGFloat>? {
        let ranges = entries.map { $0.layout.bodyTangentRange(at: tangentPosition, edge: edge) }
        guard let first = ranges.first else { return nil }
        return ranges.dropFirst().reduce(first) { partial, range in
            min(partial.lowerBound, range.lowerBound)...max(partial.upperBound, range.upperBound)
        }
    }
}

private extension ActiveBubble {
    static func presentationOrder(_ lhs: ActiveBubble, _ rhs: ActiveBubble) -> Bool {
        lhs.expiresAt == rhs.expiresAt
            ? lhs.messageID.uuidString < rhs.messageID.uuidString
            : lhs.expiresAt < rhs.expiresAt
    }
}

private final class PixelBubbleMeasurementCache: @unchecked Sendable {
    static let shared = PixelBubbleMeasurementCache()

    private let cache = NSCache<NSString, PixelBubbleMeasuredSize>()

    private init() {
        cache.countLimit = 128
    }

    func size(text: String, maximumWidth: CGFloat) -> CGSize {
        let key = "10.5|\(Int((maximumWidth * 10).rounded()))|\(text)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.alignment = .center
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: max(8, maximumWidth - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).integral.size
        let result = CGSize(
            width: min(maximumWidth, max(28, ceil(measured.width) + 16)),
            height: max(28, ceil(measured.height) + 14)
        )
        cache.setObject(PixelBubbleMeasuredSize(result), forKey: key)
        return result
    }
}

private final class PixelBubbleMeasuredSize: NSObject {
    let value: CGSize

    init(_ value: CGSize) {
        self.value = value
    }
}
