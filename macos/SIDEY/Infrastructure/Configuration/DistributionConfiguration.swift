import Foundation

enum AppPresentation {
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SIDEY"
}

// Staging changes backend isolation only; both modes use App Store authentication and commerce.
enum AppReleaseChannel: String, Equatable {
    case appStore = "app-store"
    case staging

    static func resolve(from bundle: Bundle = .main) -> AppReleaseChannel {
#if DEBUG
        if ProcessInfo.processInfo.environment["SIDEY_STAGING"] == "1" { return .staging }
#endif
        return .appStore
    }

    var storeAvailability: StoreAvailability { .appStore }
    var keychainService: String {
        self == .appStore ? "com.sidey.desktop.appstore" : "com.sidey.desktop.appstore.staging"
    }
    var preferencesSuiteName: String? {
        self == .appStore ? "app.sidey.desktop.appstore" : "app.sidey.desktop.appstore.staging"
    }
    var loginItemMode: LaunchAtLoginController.Mode { .mainApp }
    var requiresAppleAuthentication: Bool { true }
}
