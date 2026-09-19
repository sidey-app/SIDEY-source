import AppKit
import SwiftUI
import XCTest
@testable import SIDEYAppStore

@MainActor
final class NativeMessageFieldTests: XCTestCase {
    func testEmojiVariantsBindAndPreserveUTF16InsertionCursor() {
        let (_, textView) = makeTextView(width: 240, height: 40)
        var boundDraft = ""
        let field = NativeMessageField(
            text: Binding(get: { boundDraft }, set: { boundDraft = $0 }),
            onInputActivity: {},
            onSubmit: {},
            onCancel: {}
        )
        let coordinator = field.makeCoordinator()
        textView.delegate = coordinator

        for emoji in ["🙂", "👨‍👩‍👧‍👦", "👍🏽", "🇰🇷"] {
            let candidate = "앞\(emoji)뒤"
            let cursor = ("앞\(emoji)" as NSString).length
            textView.string = candidate
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            coordinator.textDidChange(
                Notification(name: NSText.didChangeNotification, object: textView)
            )

            XCTAssertEqual(boundDraft, candidate)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: cursor, length: 0))
            XCTAssertEqual(coordinator.lastValidSelection, NSRange(location: cursor, length: 0))
        }
    }

    func testComposedEmojiRespectTwoHundredCharacterLimit() {
        let (_, textView) = makeTextView(width: 240, height: 40)
        let validDraft = String(repeating: "👨‍👩‍👧‍👦", count: 200)
        var boundDraft = validDraft
        let field = NativeMessageField(
            text: Binding(get: { boundDraft }, set: { boundDraft = $0 }),
            onInputActivity: {},
            onSubmit: {},
            onCancel: {}
        )
        let coordinator = field.makeCoordinator()
        coordinator.lastValidText = validDraft
        coordinator.lastValidSelection = NSRange(location: (validDraft as NSString).length, length: 0)
        textView.delegate = coordinator

        XCTAssertEqual(validDraft.count, 200)
        XCTAssertTrue(MessageValidator.isValidDraft(validDraft))
        XCTAssertFalse(MessageValidator.isValidDraft(validDraft + "🙂"))

        textView.string = validDraft + "🙂"
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(textView.string, validDraft)
        XCTAssertEqual(boundDraft, validDraft)
        XCTAssertEqual(textView.selectedRange().location, (validDraft as NSString).length)
    }

    func testLongUnbrokenDraftWrapsVerticallyAndKeepsEndSelectionVisible() async {
        let (scrollView, textView) = makeTextView(width: 130, height: 40)
        let draft = String(repeating: "abcdefghij", count: 20)

        textView.string = draft
        textView.setSelectedRange(NSRange(location: (draft as NSString).length, length: 0))
        textView.revealSelection()
        await Task.yield()

        XCTAssertEqual(textView.textContainer?.maximumNumberOfLines, 0)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, true)
        XCTAssertEqual(textView.textContainer?.heightTracksTextView, false)
        XCTAssertGreaterThan(textView.frame.height, scrollView.contentSize.height)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, 0)
        assertSelectionIsVisible(in: textView)
    }

    func testSingleVisualLineStaysCenteredAndWrappedTextUsesTopInset() {
        let (_, textView) = makeTextView(width: 240, height: 40)

        textView.string = "짧은 입력"
        textView.updateDocumentGeometry()
        XCTAssertGreaterThan(textView.textContainerInset.height, 3)

        textView.string = String(repeating: "긴단어", count: 40)
        textView.updateDocumentGeometry()
        XCTAssertEqual(textView.textContainerInset.height, 3, accuracy: 0.5)
    }

    func testRejectedDraftRestoresSelectionAndRevealsIt() async {
        let (scrollView, textView) = makeTextView(width: 130, height: 40)
        let validDraft = String(repeating: "가", count: MessageValidator.maximumCharacters)
        var boundDraft = validDraft
        let field = NativeMessageField(
            text: Binding(
                get: { boundDraft },
                set: { boundDraft = $0 }
            ),
            onInputActivity: {},
            onSubmit: {},
            onCancel: {}
        )
        let coordinator = field.makeCoordinator()
        coordinator.lastValidText = validDraft
        coordinator.lastValidSelection = NSRange(location: 150, length: 0)
        textView.delegate = coordinator

        textView.string = validDraft + "나"
        textView.setSelectedRange(NSRange(location: 201, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        await Task.yield()

        XCTAssertEqual(textView.string, validDraft)
        XCTAssertEqual(boundDraft, validDraft)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 150, length: 0))
        XCTAssertGreaterThanOrEqual(scrollView.contentView.bounds.origin.y, 0)
        assertSelectionIsVisible(in: textView)
    }

    func testSelectionChangesRevealMiddleAndEndWithoutChangingDraft() async {
        let (_, textView) = makeTextView(width: 130, height: 40)
        let draft = Array(repeating: "이모지🙂영문abcdef", count: 12).joined()
        var boundDraft = draft
        let field = NativeMessageField(
            text: Binding(get: { boundDraft }, set: { boundDraft = $0 }),
            onInputActivity: {},
            onSubmit: {},
            onCancel: {}
        )
        let coordinator = field.makeCoordinator()
        coordinator.lastValidText = draft
        textView.delegate = coordinator
        textView.string = draft

        for location in [40, (draft as NSString).length] {
            textView.setSelectedRange(NSRange(location: location, length: 0))
            coordinator.textViewDidChangeSelection(
                Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
            )
            await Task.yield()
            assertSelectionIsVisible(in: textView)
        }

        XCTAssertEqual(boundDraft, draft)
    }

    func testIMEPasteAndDeletionReportEditsButSelectionDoesNot() {
        let (_, textView) = makeTextView(width: 240, height: 40)
        var draft = ""
        var edited: [Bool] = []
        let field = NativeMessageField(
            text: Binding(get: { draft }, set: { draft = $0 }),
            onInputActivity: {}, onSubmit: {}, onCancel: {},
            onTextEdited: { edited.append($0) }
        )
        let coordinator = field.makeCoordinator()
        textView.delegate = coordinator
        textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(edited.last, true)
        XCTAssertEqual(draft, "", "IME marked text must not prematurely commit the draft")
        textView.unmarkText()
        textView.string = "한글 붙여넣기"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(draft, "한글 붙여넣기")
        let editCount = edited.count
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertEqual(edited.count, editCount)
        textView.string = ""
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(edited.last, false)
    }

    private func makeTextView(
        width: CGFloat,
        height: CGFloat
    ) -> (NSScrollView, VerticallyCenteredMessageTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let textView = VerticallyCenteredMessageTextView()
        textView.configureForMessageInput()
        scrollView.documentView = textView
        textView.setFrameSize(scrollView.contentSize)
        return (scrollView, textView)
    }

    private func assertSelectionIsVisible(
        in textView: VerticallyCenteredMessageTextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return XCTFail("TextKit layout is unavailable", file: file, line: line)
        }

        layoutManager.ensureLayout(for: textContainer)
        let visibleGlyphs = layoutManager.glyphRange(
            forBoundingRect: textView.visibleRect.insetBy(dx: 0, dy: -2),
            in: textContainer
        )
        let visibleCharacters = layoutManager.characterRange(
            forGlyphRange: visibleGlyphs,
            actualGlyphRange: nil
        )
        let selectionLocation = textView.selectedRange().location
        let visibleEnd = NSMaxRange(visibleCharacters)
        XCTAssertGreaterThanOrEqual(selectionLocation, visibleCharacters.location, file: file, line: line)
        XCTAssertLessThanOrEqual(selectionLocation, visibleEnd + 1, file: file, line: line)
    }
}
