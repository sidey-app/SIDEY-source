import CoreGraphics
import Foundation

struct PixelCharacterFrameContract: Equatable, Sendable {
    let idle: Range<Int>
    let walk: Range<Int>
    let doze: Range<Int>
    let offline: Range<Int>

    static let standard = PixelCharacterFrameContract(
        idle: 0..<2,
        walk: 2..<6,
        doze: 6..<8,
        offline: 8..<10
    )
}

struct PixelCharacterDefinition: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let resourceName: String
    let resourceDirectory: String
    let previewFrame: Int
    let frames: PixelCharacterFrameContract
    let paletteDescription: String
    let entitlementKey: String?
    let mirrorsToMovementDirection: Bool
    let sparkleEffect: PixelSparkleEffect?

    func assetURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: resourceDirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "png")
    }
}

struct PixelSparkleColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

struct PixelSparkleEffect: Equatable, Sendable {
    let ambientDelay: ClosedRange<TimeInterval>
    let ambientDuration: TimeInterval
    let ambientCount: ClosedRange<Int>
    let ambientRadius: ClosedRange<CGFloat>
    let ambientHorizontalPosition: ClosedRange<CGFloat>
    let ambientVerticalPosition: ClosedRange<CGFloat>
    let ambientRise: CGFloat
    let centralFlashDuration: TimeInterval
    let centralFlashRadius: CGFloat
    let pulseWaves: [PixelSparklePulseWave]
    let colors: [PixelSparkleColor]

    var pulseDuration: TimeInterval {
        pulseWaves.map { $0.delay + $0.duration }.max() ?? centralFlashDuration
    }

    var pulseCount: Int {
        pulseWaves.reduce(0) { $0 + $1.count }
    }

    static let starlight = PixelSparkleEffect(
        ambientDelay: 1.0...1.4,
        ambientDuration: 1.05,
        ambientCount: 4...6,
        ambientRadius: 2.6...4.0,
        ambientHorizontalPosition: -25...25,
        ambientVerticalPosition: 5...37,
        ambientRise: 4,
        centralFlashDuration: 0.32,
        centralFlashRadius: 34,
        pulseWaves: [
            PixelSparklePulseWave(
                delay: 0,
                duration: 0.72,
                count: 18,
                distance: 126...168,
                radius: 8...13
            ),
            PixelSparklePulseWave(
                delay: 0.06,
                duration: 0.78,
                count: 24,
                distance: 82...132,
                radius: 4.5...8
            )
        ],
        colors: [
            PixelSparkleColor(red: 0.47, green: 0.76, blue: 0.68),
            PixelSparkleColor(red: 0.66, green: 0.53, blue: 0.84),
            PixelSparkleColor(red: 0.96, green: 0.73, blue: 0.22)
        ]
    )
}

struct PixelSparklePulseWave: Equatable, Sendable {
    let delay: TimeInterval
    let duration: TimeInterval
    let count: Int
    let distance: ClosedRange<CGFloat>
    let radius: ClosedRange<CGFloat>
}

enum PixelCharacterCatalog {
    static let pixelOtterID = "pixel_otter"
    static let pixelPigID = "pixel_pig"
    static let pixelTreeID = "pixel_tree"
    static let pixelHamsterID = "pixel_hamster"
    static let pixelGuineaPigID = "pixel_guinea_pig"
    static let pixelMonkeyID = "pixel_monkey"
    static let pixelChinchillaID = "pixel_chinchilla"
    static let pixelStarlightUpalupaID = "pixel_starlight_upalupa"
    static let starlightUpalupaEntitlementKey = "character:pixel_starlight_upalupa"
    static let guineaPigEntitlementKey = "character:pixel_guinea_pig"
    static let monkeyEntitlementKey = "character:pixel_monkey"
    static let chinchillaEntitlementKey = "character:pixel_chinchilla"
    static let legacyMintyPupID = "minty_pup"
    static let legacyPixelKoalaID = "pixel_koala"

    static let all: [PixelCharacterDefinition] = [
        PixelCharacterDefinition(
            id: pixelHamsterID,
            displayName: L10n.text("character.pixel_hamster.name"),
            resourceName: "pixel_hamster",
            resourceDirectory: "Characters/PixelHamster",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_hamster.palette"),
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_cat",
            displayName: L10n.text("character.pixel_cat.name"),
            resourceName: "pixel_cat",
            resourceDirectory: "Characters/PixelCat",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_cat.palette"),
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_puppy",
            displayName: L10n.text("character.pixel_puppy.name"),
            resourceName: "pixel_puppy",
            resourceDirectory: "Characters/PixelPuppy",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_puppy.palette"),
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_rabbit",
            displayName: L10n.text("character.pixel_rabbit.name"),
            resourceName: "pixel_rabbit",
            resourceDirectory: "Characters/PixelRabbit",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_rabbit.palette"),
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_penguin",
            displayName: L10n.text("character.pixel_penguin.name"),
            resourceName: "pixel_penguin",
            resourceDirectory: "Characters/PixelPenguin",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_penguin.palette"),
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelGuineaPigID,
            displayName: L10n.text("character.pixel_guinea_pig.name"),
            resourceName: "pixel_guinea_pig",
            resourceDirectory: "Characters/PixelGuineaPig",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_guinea_pig.palette"),
            entitlementKey: guineaPigEntitlementKey,
            mirrorsToMovementDirection: true,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelMonkeyID,
            displayName: L10n.text("character.pixel_monkey.name"),
            resourceName: "pixel_monkey",
            resourceDirectory: "Characters/PixelMonkey",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_monkey.palette"),
            entitlementKey: monkeyEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelChinchillaID,
            displayName: L10n.text("character.pixel_chinchilla.name"),
            resourceName: "pixel_chinchilla",
            resourceDirectory: "Characters/PixelChinchilla",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_chinchilla.palette"),
            entitlementKey: chinchillaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelStarlightUpalupaID,
            displayName: L10n.text("character.pixel_starlight_upalupa.name"),
            resourceName: "pixel_starlight_upalupa",
            resourceDirectory: "Characters/PixelStarlightUpalupa",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: L10n.text("character.pixel_starlight_upalupa.palette"),
            entitlementKey: starlightUpalupaEntitlementKey,
            mirrorsToMovementDirection: true,
            sparkleEffect: .starlight
        ),
        PixelCharacterDefinition(
            id: "pixel_otter", displayName: L10n.text("character.pixel_otter.name"),
            resourceName: "pixel_otter", resourceDirectory: "Characters/PixelOtter",
            previewFrame: 0, frames: .standard,
            paletteDescription: L10n.text("character.pixel_otter.palette"),
            entitlementKey: "character:pixel_otter", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_pig", displayName: L10n.text("character.pixel_pig.name"),
            resourceName: "pixel_pig", resourceDirectory: "Characters/PixelPig",
            previewFrame: 0, frames: .standard,
            paletteDescription: L10n.text("character.pixel_pig.palette"),
            entitlementKey: "character:pixel_pig", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_tree", displayName: L10n.text("character.pixel_tree.name"),
            resourceName: "pixel_tree", resourceDirectory: "Characters/PixelTree",
            previewFrame: 0, frames: .standard,
            paletteDescription: L10n.text("character.pixel_tree.palette"),
            entitlementKey: "character:pixel_tree", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_shiba", displayName: L10n.text("character.pixel_shiba.name"),
            resourceName: "pixel_shiba", resourceDirectory: "Characters/PixelShiba",
            previewFrame: 0, frames: .standard, paletteDescription: "",
            entitlementKey: "character:pixel_shiba", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_duck", displayName: L10n.text("character.pixel_duck.name"),
            resourceName: "pixel_duck", resourceDirectory: "Characters/PixelDuck",
            previewFrame: 0, frames: .standard, paletteDescription: "",
            entitlementKey: "character:pixel_duck", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_poop", displayName: L10n.text("character.pixel_poop.name"),
            resourceName: "pixel_poop", resourceDirectory: "Characters/PixelPoop",
            previewFrame: 0, frames: .standard, paletteDescription: "",
            entitlementKey: "character:pixel_poop", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_tteokbokki", displayName: L10n.text("character.pixel_tteokbokki.name"),
            resourceName: "pixel_tteokbokki", resourceDirectory: "Characters/PixelTteokbokki",
            previewFrame: 0, frames: .standard, paletteDescription: "",
            entitlementKey: "character:pixel_tteokbokki", mirrorsToMovementDirection: false, sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_quokka", displayName: L10n.text("character.pixel_quokka.name"),
            resourceName: "pixel_quokka", resourceDirectory: "Characters/PixelQuokka",
            previewFrame: 0, frames: .standard, paletteDescription: "",
            entitlementKey: "character:pixel_quokka", mirrorsToMovementDirection: false, sparkleEffect: nil
        )
    ]

    static let free = all.filter { $0.entitlementKey == nil }

    static let frameCount = 10
    static let framePixelSize = CGSize(width: 24, height: 24)
    static let sheetPixelSize = CGSize(width: 240, height: 24)
    static let footBaselinePixel = 3

    static func canonicalID(for storedID: String) -> String {
        let candidate = switch storedID {
        case legacyMintyPupID: pixelHamsterID
        case legacyPixelKoalaID: pixelChinchillaID
        default: storedID
        }
        return all.contains(where: { $0.id == candidate }) ? candidate : pixelHamsterID
    }

    static func definition(for storedID: String) -> PixelCharacterDefinition {
        let canonical = canonicalID(for: storedID)
        return all.first(where: { $0.id == canonical }) ?? all[0]
    }

    static func selectableDefinitions(entitlementKeys: Set<String>) -> [PixelCharacterDefinition] {
        all.filter { definition in
            guard let entitlementKey = definition.entitlementKey else { return true }
            return entitlementKeys.contains(entitlementKey)
        }
    }

    static func canSelect(_ characterID: String, entitlementKeys: Set<String>) -> Bool {
        let definition = definition(for: characterID)
        guard let entitlementKey = definition.entitlementKey else { return true }
        return entitlementKeys.contains(entitlementKey)
    }
}

enum PixelCharacterAsset {
    static let frameCount = PixelCharacterCatalog.frameCount
    static let framePixelSize = PixelCharacterCatalog.framePixelSize

    static func url(for characterID: String, bundle: Bundle = .main) -> URL? {
        PixelCharacterCatalog.definition(for: characterID).assetURL(bundle: bundle)
    }
}

/// Compatibility surface for existing callers and old asset tests.
enum PixelHamsterAsset {
    static let frameCount = PixelCharacterAsset.frameCount
    static let framePixelSize = PixelCharacterAsset.framePixelSize

    static func url(bundle: Bundle = .main) -> URL? {
        PixelCharacterAsset.url(for: PixelCharacterCatalog.pixelHamsterID, bundle: bundle)
    }
}
