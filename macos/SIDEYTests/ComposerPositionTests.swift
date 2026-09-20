import XCTest
@testable import SIDEYAppStore

final class ComposerPositionTests: XCTestCase {
    private let main = OverlayScreenGeometry(identifier: "main", legacySignature: "main", name: "main",
        visibleFrame: CGRect(x: 0, y: 40, width: 1400, height: 850))
    private let second = OverlayScreenGeometry(identifier: "second", legacySignature: "second", name: "second",
        visibleFrame: CGRect(x: -1900, y: -200, width: 1900, height: 1100))

    func testDraggingToAnotherMonitorRestoresIndependentOfCharacterMonitor() {
        let moved = CGRect(x: -1400, y: 125, width: 400, height: 56)
        XCTAssertEqual(ComposerPositionLayout.screen(for: moved, screens: [main, second]), second)
        let preference = ComposerPositionLayout.preference(frame: moved, screen: second)
        let restored = ComposerPositionLayout.frame(preference: preference, screens: [main, second], fallback: main)
        XCTAssertEqual(restored.minX, moved.minX, accuracy: 0.001)
        XCTAssertEqual(restored.minY, moved.minY, accuracy: 0.001)
        XCTAssertEqual(restored.size, moved.size)
    }

    func testMissingMonitorAndResolutionChangeKeepFixedSizeInsideVisibleFrame() {
        let position = ComposerPositionPreference(screenIdentifier: "second", relativeX: 0.9, relativeY: 0.8)
        let removed = ComposerPositionLayout.frame(preference: position, screens: [main], fallback: main)
        XCTAssertTrue(main.visibleFrame.contains(removed))
        let resized = OverlayScreenGeometry(identifier: "second", legacySignature: "", name: "second",
            visibleFrame: CGRect(x: -800, y: 0, width: 800, height: 600))
        let restored = ComposerPositionLayout.frame(preference: position, screens: [main, resized], fallback: main)
        XCTAssertTrue(resized.visibleFrame.contains(restored))
        XCTAssertEqual(restored.size, CGSize(width: 400, height: 56))
        XCTAssertEqual(restored.minX, -440, accuracy: 0.001)
    }

    func testDragBeyondScreenEdgesClampsAndPreferenceRoundTrips() throws {
        let dragged = CGRect(x: -2500, y: 2000, width: 400, height: 56)
        var preferences = AppPreferences.defaults
        preferences.composerPosition = ComposerPositionLayout.preference(frame: dragged, screen: second)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        let restored = ComposerPositionLayout.frame(preference: decoded.composerPosition, screens: [second], fallback: second)
        XCTAssertTrue(second.visibleFrame.contains(restored))
        XCTAssertEqual(restored.minX, second.visibleFrame.minX)
        XCTAssertEqual(restored.maxY, second.visibleFrame.maxY)
    }

    func testOldPreferencesKeepDefaultComposerPositionAndCharacterScreen() throws {
        let data = Data(#"{"schemaVersion":9,"overlayScreenIdentifier":"legacy"}"#.utf8)
        let old = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertNil(old.composerPosition)
        XCTAssertEqual(old.overlayRegion.screenIdentifier, "legacy")
        XCTAssertEqual(ComposerPositionLayout.frame(preference: nil, screens: [main], fallback: main),
                       OverlayComposerLayout.frame(in: main.visibleFrame))
    }

    func testAvoidanceFollowsActualComposerOnEveryEdgeAndIgnoresOtherMonitor() {
        let activity = CGRect(x: 0, y: 0, width: 1000, height: 240)
        let composer = CGRect(x: 100, y: 20, width: 400, height: 56)
        for edge in [OverlayEdge.top, .bottom, .left, .right] {
            let rects = PixelWorldAvoidanceLayout.composerRects(activityFrame: activity, edge: edge,
                composerVisible: true, composerFrame: composer)
            XCTAssertEqual(rects, [composer.insetBy(dx: -20, dy: -10)])
        }
        XCTAssertTrue(PixelWorldAvoidanceLayout.composerRects(activityFrame: activity, edge: .top,
            composerVisible: true, composerFrame: composer.offsetBy(dx: -2000, dy: 0)).isEmpty)
        XCTAssertTrue(PixelWorldAvoidanceLayout.composerRects(activityFrame: activity, edge: .top,
            composerVisible: false, composerFrame: composer).isEmpty)
    }
}

@MainActor
final class QuietPresentationTests: XCTestCase {
    func testQuietModeHidesBothTypingIndicatorsWithoutChangingPresenceAndRestoresOnlyLiveTyping() {
        let own = UUID(), friend = UUID(), roomID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(snapshot: BackendSnapshot(profile: Profile(id: own, nickname: "나", characterID: "pixel_hamster"),
            rooms: [Room(id: roomID, name: "테스트", ownerID: own,
                members: [RoomMember(userID: own, nickname: "나", characterID: "pixel_hamster", presence: .online),
                          RoomMember(userID: friend, nickname: "친구", characterID: "pixel_hamster", presence: .away)],
                inviteCodeHint: "", inviteVersion: 1)]), currentUserID: own)
        model.connectionState = .online
        model.updateTyping(roomID: roomID, userID: own, active: true)
        model.updateTyping(roomID: roomID, userID: friend, active: true)
        XCTAssertEqual(model.pixelWorldMembers.filter(\.isTyping).count, 2)
        let presence = model.pixelWorldMembers.map(\.presence)
        model.incrementUnread(in: roomID)
        model.stageMessage(id: UUID(), roomID: roomID, senderID: friend, body: "본문", revealBubble: true)
        XCTAssertFalse(model.activeBubbles.isEmpty)
        model.preferences.quietModeEnabled = true
        XCTAssertTrue(model.pixelWorldMembers.allSatisfy { !$0.isTyping })
        XCTAssertTrue(model.activeBubbles.isEmpty)
        XCTAssertEqual(model.totalUnreadCount, 1)
        XCTAssertEqual(model.connectionState, .online)
        XCTAssertEqual(model.pixelWorldMembers.map(\.presence), presence)
        model.updateTyping(roomID: roomID, userID: friend, active: false)
        model.preferences.quietModeEnabled = false
        XCTAssertEqual(model.pixelWorldMembers.filter(\.isTyping).map(\.id), [own])
    }
}
