import XCTest
@testable import SIDEY

final class LegacySettingsMigratorTests: XCTestCase {
    func testMigratesLegacyGodotSettingsOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sidey-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appending(path: "settings.json")
        let json = #"{"schema_version":4,"overlay":{"visible":false,"locked":false,"scale":1.8,"position":[120,240],"screen_signature":"2560x1440@2.000"},"local_state":{"profile":{"nickname":"민지","character_id":"minty_pup"},"rooms":[{"id":"A33009C1-B56D-4DEB-9CF2-ECEB778B658F"}],"active_room_id":"A33009C1-B56D-4DEB-9CF2-ECEB778B658F","onboarding_complete":true}}"#
        try Data(json.utf8).write(to: settingsURL)

        let suiteName = "app.sidey.desktop.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferencesStore.userDefaults(defaults)
        let migrator = LegacySettingsMigrator.files([settingsURL])

        let migrated = migrator.migrateIfNeeded(store)

        XCTAssertEqual(migrated.nickname, "민지")
        XCTAssertEqual(migrated.selectedCharacterID, "pixel_hamster")
        XCTAssertEqual(migrated.activeRoomID?.uuidString, "A33009C1-B56D-4DEB-9CF2-ECEB778B658F")
        XCTAssertFalse(migrated.overlayVisible)
        XCTAssertFalse(migrated.overlayLocked)
        XCTAssertEqual(migrated.overlayScale, 1.8)
        XCTAssertEqual(migrated.overlayFrame?.x, 120)
        XCTAssertEqual(migrated.overlayFrame?.y, 240)
        XCTAssertEqual(migrated.overlayScreenIdentifier, "2560x1440@2.000")
        XCTAssertEqual(migrated.overlayRegion.edge, .bottom)
        XCTAssertEqual(migrated.overlayRegion.span, .full)
        XCTAssertEqual(migrated.overlayRegion.screenIdentifier, "2560x1440@2.000")
        XCTAssertTrue(migrated.onboardingComplete)
        XCTAssertFalse(migrated.keychainTransitionComplete)

        try Data(#"{"local_state":{"profile":{"nickname":"덮어쓰기"}}}"#.utf8).write(to: settingsURL)
        XCTAssertEqual(migrator.migrateIfNeeded(store).nickname, "민지")
    }

    func testSupportsPreLocalStateLegacyShape() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sidey-old-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appending(path: "settings.json")
        try Data(#"{"profile":{"nickname":"이전형식"},"rooms":{"active_room_id":"6D827F23-8E06-4DAA-A810-883D90E5601C"},"onboarding_complete":true}"#.utf8)
            .write(to: settingsURL)

        let suiteName = "app.sidey.desktop.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let migrated = LegacySettingsMigrator.files([settingsURL])
            .migrateIfNeeded(.userDefaults(defaults))

        XCTAssertEqual(migrated.nickname, "이전형식")
        XCTAssertEqual(migrated.activeRoomID?.uuidString, "6D827F23-8E06-4DAA-A810-883D90E5601C")
        XCTAssertTrue(migrated.onboardingComplete)
    }
}
