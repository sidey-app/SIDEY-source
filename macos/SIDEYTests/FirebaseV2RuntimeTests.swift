import XCTest
@testable import SIDEY

final class FirebaseV2RuntimeTests: XCTestCase {
    func testBundledAppStoreConfigurationHasExpectedIdentity() throws {
        let configuration = try FirebaseV2Configuration.load(
            from: .main,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )

        XCTAssertEqual(configuration.projectID, "sidey-realtime")
        XCTAssertEqual(
            configuration.googleAppID,
            "1:985965733256:ios:62d9e218a8171e54b4063d"
        )
        XCTAssertEqual(configuration.bundleID, "app.sidey.desktop.appstore")
    }

    func testRejectsDevelopmentOrUnknownFirebaseIdentity() {
        var plist = validPlist
        plist["BUNDLE_ID"] = "app.sidey.desktop.dev"
        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: plist,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .unexpectedBundle)
        }

        plist = validPlist
        plist["GOOGLE_APP_ID"] = "1:985965733256:ios:unknown"
        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: plist,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .unexpectedApp)
        }

        plist = validPlist
        plist["PROJECT_ID"] = "different-project"
        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: plist,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .unexpectedProject)
        }
    }

    func testRejectsRuntimeBundleMismatch() {
        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: validPlist,
            runtimeBundleIdentifier: "app.sidey.desktop.dev"
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .unexpectedBundle)
        }
    }

    func testRejectsDownloadedDefaultDatabaseURL() {
        var plist = validPlist
        plist["DATABASE_URL"] = "https://sidey-realtime-default-rtdb.asia-southeast1.firebasedatabase.app"

        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: plist,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .unexpectedDatabase)
        }

        XCTAssertEqual(
            FirebaseV2Configuration.databaseURL.absoluteString,
            "https://sidey.asia-southeast1.firebasedatabase.app"
        )
    }

    func testRejectsMissingRequiredIdentityField() {
        var plist = validPlist
        plist.removeValue(forKey: "GOOGLE_APP_ID")

        XCTAssertThrowsError(try FirebaseV2Configuration.validate(
            plist: plist,
            runtimeBundleIdentifier: FirebaseV2Configuration.expectedBundleID
        )) { error in
            XCTAssertEqual(error as? FirebaseV2ConfigurationError, .invalidPlist)
        }
    }

    private var validPlist: [String: Any] {
        [
            "PROJECT_ID": FirebaseV2Configuration.expectedProjectID,
            "GOOGLE_APP_ID": FirebaseV2Configuration.expectedGoogleAppID,
            "BUNDLE_ID": FirebaseV2Configuration.expectedBundleID,
            "DATABASE_URL": FirebaseV2Configuration.databaseURL.absoluteString
        ]
    }
}
