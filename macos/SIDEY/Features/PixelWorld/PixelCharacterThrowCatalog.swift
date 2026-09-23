import AppKit
import SpriteKit

enum PixelCharacterThrowCatalog {
    static let fallbackCharacterID = PixelCharacterCatalog.pixelHamsterID
    static let fallbackObjectID = "patch_soft_ball"
    static let actionFrameCount = 8
    static let objectFrameCount = 12
    static let throwFrames = 0..<4
    static let hitFrames = 4..<8
    static let rotationFrames = 0..<8
    static let impactFrames = 8..<12
    static let cannonObjectID = "throwable_toy_cannon"
    static var purchasableObjectIDs: Set<String> {
        Set(CommerceCatalog.products.filter { $0.kind == .throwable }.map(\.catalogItemID))
    }

    static func objectID(for characterID: String) -> String { fallbackObjectID }

    static func interactionDescription(for characterID: String) -> String {
        characterID == PixelCharacterCatalog.pixelTreeID
            ? L10n.text("pixel_world.interaction.tree")
            : L10n.text("pixel_world.interaction.throw")
    }

    static func supports(objectID: String?) -> Bool {
        guard let objectID else { return false }
        return objectID == fallbackObjectID || CommerceCatalog.products.contains {
            $0.kind == .throwable && ($0.catalogItemID == objectID || $0.renderAssetID == objectID)
        }
    }

    static func resolvedObjectID(for characterID: String, equippedObjectID: String?) -> String {
        guard let id = equippedObjectID, supports(objectID: id) else { return fallbackObjectID }
        return CommerceCatalog.products.first { $0.kind == .throwable && $0.catalogItemID == id }?.renderAssetID ?? id
    }

    static func actionAssetURL(for characterID: String, bundle: Bundle = .main) -> URL? {
        let id = PixelCharacterCatalog.canonicalID(for: characterID)
        let name = "\(id)_throw_hit"
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "CharacterThrow/ActionSheets")
            ?? bundle.url(forResource: name, withExtension: "png")
    }

    static func objectAssetURL(for objectID: String, bundle: Bundle = .main) -> URL? {
        let objectID = resolvedObjectID(for: fallbackCharacterID, equippedObjectID: objectID)
        return bundle.url(forResource: objectID, withExtension: "png", subdirectory: "CharacterThrow/ObjectSheets")
            ?? bundle.url(forResource: objectID, withExtension: "png")
    }

    static func emitterAssetURL(for objectID: String, bundle: Bundle = .main) -> URL? {
        let resourceName = "\(objectID)_emitter"
        return bundle.url(forResource: resourceName, withExtension: "png", subdirectory: "CharacterThrow/EmitterSheets")
            ?? bundle.url(forResource: resourceName, withExtension: "png")
    }
}

struct PixelCharacterThrowTextures {
    let throwFrames: [SKTexture]
    let hitFrames: [SKTexture]
    let rotationFrames: [SKTexture]
    let impactFrames: [SKTexture]
    let emitterFrames: [SKTexture]
    let objectID: String

    var usesCannonEmitter: Bool { objectID == PixelCharacterThrowCatalog.cannonObjectID }
}

@MainActor
final class PixelCharacterThrowTextureStore {
    static let shared = PixelCharacterThrowTextureStore()
    private var cache: [String: PixelCharacterThrowTextures] = [:]

    func textures(
        for sourceCharacterID: String,
        throwableID: String? = nil,
        bundle: Bundle = .main
    ) -> PixelCharacterThrowTextures {
        let characterID = PixelCharacterCatalog.canonicalID(for: sourceCharacterID)
        let objectID = PixelCharacterThrowCatalog.resolvedObjectID(
            for: characterID,
            equippedObjectID: throwableID
        )
        let cacheKey = "\(characterID)|\(objectID)"
        if let cached = cache[cacheKey] { return cached }
        let actions = frames(
            url: PixelCharacterThrowCatalog.actionAssetURL(for: characterID, bundle: bundle),
            count: PixelCharacterThrowCatalog.actionFrameCount,
            cellSize: CGSize(width: 24, height: 24),
            fallbackColor: .systemOrange
        )
        let objects = frames(
            url: PixelCharacterThrowCatalog.objectAssetURL(for: objectID, bundle: bundle),
            count: PixelCharacterThrowCatalog.objectFrameCount,
            cellSize: CGSize(width: 16, height: 16),
            fallbackColor: .systemTeal
        )
        let emitters = objectID == PixelCharacterThrowCatalog.cannonObjectID
            ? frames(
                url: PixelCharacterThrowCatalog.emitterAssetURL(for: objectID, bundle: bundle),
                count: 4,
                cellSize: CGSize(width: 24, height: 24),
                fallbackColor: .systemGray
            )
            : []
        let result = PixelCharacterThrowTextures(
            throwFrames: Array(actions[PixelCharacterThrowCatalog.throwFrames]),
            hitFrames: Array(actions[PixelCharacterThrowCatalog.hitFrames]),
            rotationFrames: Array(objects[PixelCharacterThrowCatalog.rotationFrames]),
            impactFrames: Array(objects[PixelCharacterThrowCatalog.impactFrames]),
            emitterFrames: emitters,
            objectID: objectID
        )
        cache[cacheKey] = result
        return result
    }

    private func frames(
        url: URL?,
        count: Int,
        cellSize: CGSize,
        fallbackColor: NSColor
    ) -> [SKTexture] {
        let image: NSImage
        if let url, let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(size: CGSize(width: cellSize.width * CGFloat(count), height: cellSize.height))
            image.lockFocus()
            fallbackColor.setFill()
            for index in 0..<count {
                NSBezierPath(ovalIn: CGRect(
                    x: CGFloat(index) * cellSize.width + 3,
                    y: 3,
                    width: cellSize.width - 6,
                    height: cellSize.height - 6
                )).fill()
            }
            image.unlockFocus()
        }
        let sheet = SKTexture(image: image)
        sheet.filteringMode = .nearest
        return (0..<count).map { index in
            let texture = SKTexture(
                rect: CGRect(
                    x: CGFloat(index) / CGFloat(count),
                    y: 0,
                    width: 1 / CGFloat(count),
                    height: 1
                ),
                in: sheet
            )
            texture.filteringMode = .nearest
            return texture
        }
    }
}

enum PixelCharacterThrowStyle {
    static let throwDuration: TimeInterval = 0.4
    static let releaseDelay: TimeInterval = 0.2
    static let hitDuration: TimeInterval = 0.44
    static let impactDuration: TimeInterval = 0.24
    static func impactFrameDurations(for objectID: String) -> [TimeInterval] {
        // Let the filling stretch read as a distinct pose at the normal 30 FPS.
        // The approved four-frame artwork stays unchanged.
        objectID == "throwable_dujjonku"
            ? [0.08, 0.10, 0.28, 0.12]
            : Array(repeating: impactDuration / 4, count: 4)
    }
    static let impactPointSize: CGFloat = 48
    static let impactTorsoOffset: CGFloat = 10
    static let cannonEmitterPointSize: CGFloat = 48
    static let cannonEmitterZPosition: CGFloat = 10
    static let cannonEmitterTangentOffset: CGFloat = 6
    static let cannonEmitterNormalOffset: CGFloat = -1
    static let rotationFrameInterval: TimeInterval = 0.083
    static let maximumActiveProjectiles = 32

    static func arcHeight(for distance: CGFloat) -> CGFloat {
        min(96, max(24, distance * 0.18))
    }

    static func flightDuration(for distance: CGFloat) -> TimeInterval {
        min(0.95, max(0.35, 0.35 + TimeInterval(distance / 1_600)))
    }
}
