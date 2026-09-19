import AppKit
import SwiftUI

final class VerticallyCenteredMessageTextView: NSTextView {
    override func layout() {
        super.layout()
        updateDocumentGeometry()
    }

    func configureForMessageInput() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        font = .systemFont(ofSize: 15, weight: .regular)
        textColor = .labelColor
        insertionPointColor = .labelColor
        identifier = NSUserInterfaceItemIdentifier("sidey.message-field")
        textContainerInset = NSSize(width: 0, height: 3)
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        // The three-line contract counts explicit newlines in MessageValidator.
        // Wrapped text must keep laying out so a 200-character word remains reachable.
        textContainer?.maximumNumberOfLines = 0
        textContainer?.lineBreakMode = .byWordWrapping
    }

    func updateDocumentGeometry() {
        guard let layoutManager, let textContainer else { return }

        let viewportSize = enclosingScrollView?.contentSize ?? bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        if abs(frame.width - viewportSize.width) > 0.5 {
            setFrameSize(NSSize(width: viewportSize.width, height: max(frame.height, viewportSize.height)))
        }
        layoutManager.ensureLayout(for: textContainer)

        let availableHeight = viewportSize.height
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let shouldCenter = !string.contains("\n") && usedHeight <= availableHeight
        let inset = shouldCenter ? max(3, floor((availableHeight - usedHeight) / 2)) : 3

        if abs(textContainerInset.height - inset) > 0.5 {
            textContainerInset = NSSize(width: 0, height: inset)
            layoutManager.ensureLayout(for: textContainer)
        }

        let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            + textContainerInset.height * 2
        let targetHeight = max(availableHeight, contentHeight)
        if abs(frame.height - targetHeight) > 0.5 {
            setFrameSize(NSSize(width: viewportSize.width, height: targetHeight))
        }
    }

    func revealSelection() {
        updateDocumentGeometry()
        scrollRangeToVisible(selectedRange())

        // Selection/layout notifications can arrive before AppKit has committed the
        // new glyph geometry (notably after IME commit and undo/redo).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateDocumentGeometry()
            self.scrollRangeToVisible(self.selectedRange())
        }
    }
}

struct NativeMessageField: NSViewRepresentable {
    @Binding var text: String
    let onInputActivity: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var onTextEdited: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = VerticallyCenteredMessageTextView()
        textView.delegate = context.coordinator
        textView.configureForMessageInput()
        textView.string = text
        context.coordinator.lastValidText = text
        context.coordinator.lastValidSelection = NSRange(
            location: (text as NSString).length,
            length: 0
        )
        scrollView.documentView = textView
        textView.setFrameSize(scrollView.contentSize)

        DispatchQueue.main.async {
            textView.revealSelection()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? VerticallyCenteredMessageTextView else { return }
        guard !textView.hasMarkedText(), textView.string != text else {
            textView.revealSelection()
            return
        }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(selection.location, (text as NSString).length),
            length: 0
        ))
        context.coordinator.lastValidText = text
        context.coordinator.lastValidSelection = textView.selectedRange()
        textView.revealSelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMessageField
        var lastValidText = ""
        var lastValidSelection = NSRange(location: 0, length: 0)

        init(parent: NativeMessageField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onInputActivity()
            if textView.hasMarkedText() {
                parent.onTextEdited(!textView.string.isEmpty)
                return
            }
            let candidate = textView.string
            guard MessageValidator.isValidDraft(candidate) else {
                // Replacing the string emits a synchronous selection-change
                // notification. Snapshot the last valid range first so that
                // AppKit's temporary end-of-document selection cannot overwrite it.
                let selectionToRestore = lastValidSelection
                NSSound.beep()
                textView.string = lastValidText
                textView.setSelectedRange(clampedSelection(selectionToRestore, in: lastValidText))
                (textView as? VerticallyCenteredMessageTextView)?.revealSelection()
                return
            }
            lastValidText = candidate
            lastValidSelection = textView.selectedRange()
            parent.text = candidate
            parent.onTextEdited(!candidate.isEmpty)
            (textView as? VerticallyCenteredMessageTextView)?.revealSelection()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if !textView.hasMarkedText(), MessageValidator.isValidDraft(textView.string) {
                lastValidSelection = textView.selectedRange()
            }
            (textView as? VerticallyCenteredMessageTextView)?.revealSelection()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApplication.shared.currentEvent?.modifierFlags.contains(.shift) == true {
                let candidate = (textView.string as NSString).replacingCharacters(
                    in: textView.selectedRange(),
                    with: "\n"
                )
                guard MessageValidator.isValidDraft(candidate) else {
                    NSSound.beep()
                    (textView as? VerticallyCenteredMessageTextView)?.revealSelection()
                    return true
                }
                textView.insertText("\n", replacementRange: textView.selectedRange())
                (textView as? VerticallyCenteredMessageTextView)?.revealSelection()
            } else {
                parent.onSubmit()
            }
            return true
        }

        private func clampedSelection(_ selection: NSRange, in text: String) -> NSRange {
            let length = (text as NSString).length
            let location = min(selection.location, length)
            return NSRange(
                location: location,
                length: min(selection.length, length - location)
            )
        }
    }
}
