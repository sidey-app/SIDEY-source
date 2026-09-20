import XCTest
@testable import SIDEY

final class ProfileValidatorTests: XCTestCase {
    func testNicknameAcceptsTwoThroughEightCharacters() {
        XCTAssertTrue(ProfileValidator.isValidNickname("가나"))
        XCTAssertTrue(ProfileValidator.isValidNickname("가나다라마바사아"))
    }

    func testNicknameRejectsInvalidLengthAndLineBreaks() {
        XCTAssertFalse(ProfileValidator.isValidNickname("가"))
        XCTAssertFalse(ProfileValidator.isValidNickname("가나다라마바사아자"))
        XCTAssertFalse(ProfileValidator.isValidNickname("친구\n이름"))
        XCTAssertFalse(ProfileValidator.isValidNickname("친구\t이름"))
    }

    func testNicknameDraftAndDisplayAreDefensivelyLimited() {
        XCTAssertEqual(ProfileValidator.limitedNicknameDraft("가나다라마바사아자차"), "가나다라마바사아")
        XCTAssertEqual(ProfileValidator.limitedNicknameDraft("친구\n이름"), "친구이름")
        XCTAssertEqual(ProfileValidator.displayNickname("  가나다라마바사아자  "), "가나다라마바사아")
    }
}
