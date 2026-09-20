import XCTest
@testable import SIDEY

final class MessageValidatorTests: XCTestCase {
    func testAcceptsThreeLinesAndTwoHundredCharacters() {
        XCTAssertTrue(MessageValidator.isValid("a\nb\nc"))
        XCTAssertTrue(MessageValidator.isValid(String(repeating: "가", count: 200)))
    }

    func testRejectsEmptyLongAndFourLineMessages() {
        XCTAssertFalse(MessageValidator.isValid(""))
        XCTAssertFalse(MessageValidator.isValid(String(repeating: "a", count: 201)))
        XCTAssertFalse(MessageValidator.isValid("a\nb\nc\nd"))
    }

    func testNormalizationUsesLineFeedsAndTrimsEdges() {
        XCTAssertEqual(MessageValidator.normalized("  안녕\r\n친구  \r"), "안녕\n친구")
    }

    func testDraftLimitRejectsBeforeMutatingInput() {
        XCTAssertTrue(MessageValidator.isValidDraft("a\nb\nc"))
        XCTAssertTrue(MessageValidator.isValidDraft(String(repeating: "가", count: 200)))
        XCTAssertFalse(MessageValidator.isValidDraft("a\nb\nc\nd"))
        XCTAssertFalse(MessageValidator.isValidDraft(String(repeating: "가", count: 201)))
    }
}
