import AppKit
import SwiftUI

struct ComposerPositionPreference: Codable, Equatable, Sendable {
    var screenIdentifier: String
    var relativeX: Double
    var relativeY: Double
}

enum ComposerPositionLayout {
    static func frame(preference: ComposerPositionPreference?, screens: [OverlayScreenGeometry],
                      fallback: OverlayScreenGeometry) -> CGRect {
        guard let preference else { return clamp(OverlayComposerLayout.frame(in: fallback.visibleFrame), to: fallback.visibleFrame) }
        let screen = screens.first { $0.identifier == preference.screenIdentifier } ?? fallback
        let visible = screen.visibleFrame
        let x = preference.relativeX.isFinite ? min(1, max(0, preference.relativeX)) : 0.5
        let y = preference.relativeY.isFinite ? min(1, max(0, preference.relativeY)) : 1
        return CGRect(x: visible.minX + max(0, visible.width - OverlayComposerLayout.panelSize.width) * x,
                      y: visible.minY + max(0, visible.height - OverlayComposerLayout.panelSize.height) * y,
                      width: OverlayComposerLayout.panelSize.width, height: OverlayComposerLayout.panelSize.height)
    }

    static func preference(frame: CGRect, screen: OverlayScreenGeometry) -> ComposerPositionPreference {
        let visible = screen.visibleFrame
        let frame = clamp(frame, to: visible)
        return ComposerPositionPreference(screenIdentifier: screen.identifier,
            relativeX: (frame.minX - visible.minX) / max(1, visible.width - frame.width),
            relativeY: (frame.minY - visible.minY) / max(1, visible.height - frame.height))
    }

    static func screen(for frame: CGRect, screens: [OverlayScreenGeometry]) -> OverlayScreenGeometry? {
        screens.max { area(frame.intersection($0.visibleFrame)) < area(frame.intersection($1.visibleFrame)) }
    }

    static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        CGRect(x: min(max(visible.minX, frame.minX), max(visible.minX, visible.maxX - frame.width)),
               y: min(max(visible.minY, frame.minY), max(visible.minY, visible.maxY - frame.height)),
               width: frame.width, height: frame.height)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}

/// Only this explicit handle starts a local window drag. No global input monitoring.
struct ComposerDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Handle: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            toolTip = "입력창 이동"
            setAccessibilityElement(true)
            setAccessibilityLabel("입력창 이동 손잡이")
        }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            for x in [-2.5, 2.5] {
                for y in [-6.0, 0.0, 6.0] {
                    NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1, y: bounds.midY + y - 1, width: 2, height: 2)).fill()
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
            NotificationCenter.default.post(name: .sideyComposerDragEnded, object: window)
        }
    }
}

extension Notification.Name {
    static let sideyComposerDragEnded = Notification.Name("sidey.composer.drag-ended")
}
