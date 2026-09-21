import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
import FirebaseFunctions
import Foundation

struct FirebaseV2Configuration: Equatable, Sendable {
    static let appName = "SIDEYFirebaseV2"
    static let expectedProjectID = "sidey-realtime"
    static let expectedGoogleAppID = "1:985965733256:ios:62d9e218a8171e54b4063d"
    static let expectedBundleID = "app.sidey.desktop.appstore"
    static let databaseURL = URL(
        string: "https://sidey.asia-southeast1.firebasedatabase.app"
    )!

    let projectID: String
    let googleAppID: String
    let bundleID: String

    static func load(
        from bundle: Bundle = .main,
        runtimeBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> Self {
        guard let url = bundle.url(
            forResource: "GoogleService-Info",
            withExtension: "plist"
        ) else {
            throw FirebaseV2ConfigurationError.missingPlist
        }
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw FirebaseV2ConfigurationError.invalidPlist
        }
        return try validate(
            plist: plist,
            runtimeBundleIdentifier: runtimeBundleIdentifier
        )
    }

    static func validate(
        plist: [String: Any],
        runtimeBundleIdentifier: String?
    ) throws -> Self {
        guard let projectID = plist["PROJECT_ID"] as? String,
              let googleAppID = plist["GOOGLE_APP_ID"] as? String,
              let bundleID = plist["BUNDLE_ID"] as? String else {
            throw FirebaseV2ConfigurationError.invalidPlist
        }
        guard projectID == expectedProjectID else {
            throw FirebaseV2ConfigurationError.unexpectedProject
        }
        guard googleAppID == expectedGoogleAppID else {
            throw FirebaseV2ConfigurationError.unexpectedApp
        }
        guard bundleID == expectedBundleID,
              runtimeBundleIdentifier == expectedBundleID else {
            throw FirebaseV2ConfigurationError.unexpectedBundle
        }
        guard plist["DATABASE_URL"] as? String == databaseURL.absoluteString else {
            throw FirebaseV2ConfigurationError.unexpectedDatabase
        }
        return Self(
            projectID: projectID,
            googleAppID: googleAppID,
            bundleID: bundleID
        )
    }
}

enum FirebaseV2ConfigurationError: LocalizedError, Equatable {
    case missingPlist
    case invalidPlist
    case unexpectedProject
    case unexpectedApp
    case unexpectedBundle
    case unexpectedDatabase
    case sdkOptionsUnavailable
    case sdkAppUnavailable

    var errorDescription: String? {
        switch self {
        case .missingPlist:
            "App Store Firebase 설정 파일이 번들에 없습니다."
        case .invalidPlist:
            "App Store Firebase 설정 파일을 읽을 수 없습니다."
        case .unexpectedProject:
            "Firebase 설정이 SIDEY production project를 가리키지 않습니다."
        case .unexpectedApp:
            "Firebase 설정이 등록된 App Store app과 일치하지 않습니다."
        case .unexpectedBundle:
            "Firebase 설정과 실행 중인 App Store bundle ID가 일치하지 않습니다."
        case .unexpectedDatabase:
            "Firebase 설정이 active SIDEY Realtime Database를 가리키지 않습니다."
        case .sdkOptionsUnavailable:
            "Firebase SDK 설정을 생성할 수 없습니다."
        case .sdkAppUnavailable:
            "Firebase SDK app을 초기화할 수 없습니다."
        }
    }
}

/// Lazily created only after the Firebase v2 rollout gate selects its adapter.
/// Keeping a named app prevents unrelated code from accidentally using a default
/// Firebase app or the disabled default Realtime Database instance.
@MainActor
final class FirebaseV2Runtime {
    let app: FirebaseApp
    let auth: Auth
    let database: Database
    let functions: Functions

    private init(app: FirebaseApp) {
        self.app = app
        self.auth = Auth.auth(app: app)
        self.database = Database.database(
            app: app,
            url: FirebaseV2Configuration.databaseURL.absoluteString
        )
        self.functions = Functions.functions(app: app, region: "asia-southeast1")
    }

    static func configure(bundle: Bundle = .main) throws -> FirebaseV2Runtime {
        let configuration = try FirebaseV2Configuration.load(
            from: bundle,
            runtimeBundleIdentifier: bundle.bundleIdentifier
        )
        guard let plistPath = bundle.path(
            forResource: "GoogleService-Info",
            ofType: "plist"
        ), let options = FirebaseOptions(contentsOfFile: plistPath) else {
            throw FirebaseV2ConfigurationError.sdkOptionsUnavailable
        }

        // Keep the canonical named URL explicit even though the bundled plist is
        // normalized, so future config regeneration cannot select the default DB.
        options.databaseURL = FirebaseV2Configuration.databaseURL.absoluteString

        let app: FirebaseApp
        if let existing = FirebaseApp.app(name: FirebaseV2Configuration.appName) {
            guard existing.options.projectID == configuration.projectID,
                  existing.options.googleAppID == configuration.googleAppID,
                  existing.options.bundleID == configuration.bundleID,
                  existing.options.databaseURL == FirebaseV2Configuration.databaseURL.absoluteString else {
                throw FirebaseV2ConfigurationError.sdkAppUnavailable
            }
            app = existing
        } else {
            FirebaseApp.configure(
                name: FirebaseV2Configuration.appName,
                options: options
            )
            guard let configured = FirebaseApp.app(name: FirebaseV2Configuration.appName) else {
                throw FirebaseV2ConfigurationError.sdkAppUnavailable
            }
            app = configured
        }

        return FirebaseV2Runtime(app: app)
    }
}
