import CoreGraphics
import Foundation

struct CodableRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct AppPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 10
    var characterSoundEffectsEnabled = true
    var treeMovementPaused = false

    var schemaVersion = currentSchemaVersion
    var hasShownNativeLanding = false
    /// 새 설치는 안내가 필요 없고, schema 6 이하에서 올라온 설치만 false로 디코딩된다.
    var keychainTransitionComplete = true
    var onboardingComplete = false
    var overlayVisible = true
    var overlayRegion = OverlayRegionPreference.defaultValue
    var showOfflineMembers = true
    var requiresRightClickToThrow = false
    var overlayLocked = true
    var overlayScale = 1.5
    var quietModeEnabled = false
    var launchAtLogin = false
    var overlayFrame: CodableRect?
    var overlayScreenIdentifier: String?
    var composerPosition: ComposerPositionPreference?
    var nickname = "나"
    var selectedCharacterID = PixelCharacterCatalog.pixelHamsterID
    var activeRoomID: UUID?
    var installationSeed = UInt64.random(in: UInt64.min...UInt64.max)

    static let defaults = AppPreferences()

    enum CodingKeys: String, CodingKey {
        case characterSoundEffectsEnabled
        case treeMovementPaused
        case schemaVersion
        case hasShownNativeLanding
        case keychainTransitionComplete
        case onboardingComplete
        case overlayVisible
        case overlayRegion
        case showOfflineMembers
        case requiresRightClickToThrow
        case overlayLocked
        case overlayScale
        case quietModeEnabled
        case launchAtLogin
        case overlayFrame
        case overlayScreenIdentifier
        case composerPosition
        case nickname
        case selectedCharacterID
        case activeRoomID
        case installationSeed
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = Self.currentSchemaVersion
        characterSoundEffectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .characterSoundEffectsEnabled) ?? true
        treeMovementPaused = try values.decodeIfPresent(Bool.self, forKey: .treeMovementPaused) ?? false
        hasShownNativeLanding = try values.decodeIfPresent(Bool.self, forKey: .hasShownNativeLanding) ?? false
        keychainTransitionComplete = try values.decodeIfPresent(
            Bool.self,
            forKey: .keychainTransitionComplete
        ) ?? (decodedSchemaVersion >= 7)
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        overlayVisible = try values.decodeIfPresent(Bool.self, forKey: .overlayVisible) ?? true
        showOfflineMembers = try values.decodeIfPresent(Bool.self, forKey: .showOfflineMembers) ?? true
        requiresRightClickToThrow = try values.decodeIfPresent(
            Bool.self,
            forKey: .requiresRightClickToThrow
        ) ?? false
        // frame/lock/scale remain decodable for rollback compatibility, but the
        // pixel world migrates them to the bottom/full region contract.
        overlayLocked = try values.decodeIfPresent(Bool.self, forKey: .overlayLocked) ?? true
        overlayScale = try values.decodeIfPresent(Double.self, forKey: .overlayScale) ?? 1.5
        quietModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .quietModeEnabled) ?? false
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        overlayFrame = try values.decodeIfPresent(CodableRect.self, forKey: .overlayFrame)
        overlayScreenIdentifier = try values.decodeIfPresent(String.self, forKey: .overlayScreenIdentifier)
        composerPosition = try values.decodeIfPresent(ComposerPositionPreference.self, forKey: .composerPosition)
        overlayRegion = try values.decodeIfPresent(
            OverlayRegionPreference.self,
            forKey: .overlayRegion
        ) ?? OverlayRegionPreference(
            edge: .bottom,
            span: .full,
            screenIdentifier: overlayScreenIdentifier
        )
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? "나"
        selectedCharacterID = PixelCharacterCatalog.canonicalID(
            for: try values.decodeIfPresent(String.self, forKey: .selectedCharacterID)
                ?? PixelCharacterCatalog.pixelHamsterID
        )
        activeRoomID = try values.decodeIfPresent(UUID.self, forKey: .activeRoomID)
        installationSeed = try values.decodeIfPresent(UInt64.self, forKey: .installationSeed)
            ?? UInt64.random(in: UInt64.min...UInt64.max)
    }
}

struct PreferencesStore: Sendable {
    var load: @Sendable () -> AppPreferences
    var save: @Sendable (AppPreferences) -> Void

    static let live = PreferencesStore(
        load: {
            guard let data = UserDefaults.standard.data(forKey: "sidey.preferences"),
                  let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
            else { return .defaults }
            return value
        },
        save: { value in
            guard let data = try? JSONEncoder().encode(value) else { return }
            UserDefaults.standard.set(data, forKey: "sidey.preferences")
        }
    )

    static func userDefaults(_ defaults: UserDefaults) -> PreferencesStore {
        let box = UserDefaultsBox(defaults)
        return PreferencesStore(
            load: {
                guard let data = box.value.data(forKey: "sidey.preferences"),
                      let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
                else { return .defaults }
                return value
            },
            save: { value in
                guard let data = try? JSONEncoder().encode(value) else { return }
                box.value.set(data, forKey: "sidey.preferences")
            }
        )
    }
}

private final class UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults
    init(_ value: UserDefaults) { self.value = value }
}
