import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import SIDEYAppStore

@MainActor
final class KeepsakeStoreTests: XCTestCase {
    func testIndependentOwnershipAndLegacyOfferIdentity() throws {
        XCTAssertEqual(CommerceCatalog.products.count, 33)
        let keepsakes = CommerceCatalog.products.filter(\.isKeepsake)
        XCTAssertEqual(keepsakes.count, 12)
        for product in CommerceCatalog.characterProducts {
            let item = try XCTUnwrap(CommerceCatalog.keepsake(for: product.id))
            XCTAssertNotEqual(product.entitlementKey, item.entitlementKey)
            XCTAssertEqual(item.amountKRW, 1_100)
            XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: try XCTUnwrap(product.characterID)), "patch_soft_ball")
            // A free hamster can render any independently equipped keepsake.
            XCTAssertEqual(PixelCharacterThrowCatalog.resolvedObjectID(for: "pixel_hamster", equippedObjectID: item.catalogItemID), item.renderAssetID)
            XCTAssertNotNil(PixelCharacterThrowCatalog.objectAssetURL(for: item.catalogItemID))
        }
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_monkey_solo")?.id, CommerceProduct.monkey.id)
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_monkey")?.id, CommerceProduct.monkey.id)
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_monkey_solo_2")?.id, CommerceProduct.monkey.id)
        XCTAssertEqual(CommerceProduct.monkey.appStoreProductID, "character_monkey_solo_4")
        XCTAssertEqual(CommerceProduct.tree.appStoreProductID, "character_tree_2")
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_tree_2")?.id, CommerceProduct.tree.id)
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_tree")?.id, CommerceProduct.tree.id)
        XCTAssertEqual(CommerceProduct.tree.entitlementKey, "character:pixel_tree")
        for (id, current, legacy) in [
            ("character_monkey", "character_monkey_solo_4", "character_monkey_solo_3"),
            ("throwable_clam", "throwable_clam_2", "throwable_clam"),
            ("throwable_pork", "throwable_pork_2", "throwable_pork")
        ] {
            let product = try XCTUnwrap(CommerceCatalog.product(id: id))
            XCTAssertEqual(product.appStoreProductID, current)
            XCTAssertEqual(CommerceCatalog.product(appStoreID: current)?.entitlementKey, product.entitlementKey)
            XCTAssertEqual(CommerceCatalog.product(appStoreID: legacy)?.entitlementKey, product.entitlementKey)
        }
        XCTAssertEqual(CommerceProduct.pig.appStoreProductID, "character_pig")
        XCTAssertNil(CommerceCatalog.product(appStoreID: "character_tree_3"))
        XCTAssertNil(CommerceCatalog.product(appStoreID: "haracter_pig"))
    }
    func testFriendClickThrowsKeepsakeWithSoundAndViewUpdatesDoNotThrowAgain() throws {
        var now: TimeInterval = 100
        let scenario = StorePreviewScenario.make(product: .pig)
        let scene = PixelWorldScene(size: StorePreviewStageLayout.size, renderingConfiguration: .storePreview(
            initialTrackFractions: scenario.initialTrackFractions, fixedTrackFractions: scenario.fixedTrackFractions), clock: { now })
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()
        defer { coordinator.stop(detachingScene: true) }
        var sounds: [String] = []
        scene.onCharacterImpact = { object, _ in sounds.append(object) }
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        XCTAssertEqual(view.characterThrowInteraction?.throwableID, "pork")
        let target = try XCTUnwrap(scene.agentStates.first { $0.id == StorePreviewScenario.dubuID })
        XCTAssertTrue(view.playCharacterThrow(at: scene.trackGeometry.point(for: target.trackPosition)))
        XCTAssertEqual(scene.activeProjectileCount, 1)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertEqual(scene.activeProjectileCount, 1)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        now += 0.8
        scene.update(now)
        XCTAssertEqual(sounds, ["pork"])
        // Gameplay still uses the free default; only this local preview selects the keepsake.
        XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: "pixel_pig"), "patch_soft_ball")
        coordinator.stop(detachingScene: true)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        XCTAssertNil(view.scene)
    }
    func testPausedPreviewIgnoresClicksAndDoesNotReplayThemOnResume() throws {
        let scenario = StorePreviewScenario.make(product: .pig)
        let scene = PixelWorldScene(size: StorePreviewStageLayout.size, renderingConfiguration: .storePreview(
            initialTrackFractions: scenario.initialTrackFractions, fixedTrackFractions: scenario.fixedTrackFractions))
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: false)
        let target = try XCTUnwrap(scene.agentStates.first { $0.id == StorePreviewScenario.dubuID })
        XCTAssertFalse(view.playCharacterThrow(at: scene.trackGeometry.point(for: target.trackPosition)))
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        coordinator.stop(detachingScene: true)
    }
    func testCharacterStoryUsesBundledCopyWithOlderServerMetadata() {
        let catalog = CommerceProduct.pig
        let remote = CommerceProduct(id: catalog.id, displayName: catalog.displayName,
            description: "이전 서버 소개", characterID: catalog.characterID,
            entitlementKey: catalog.entitlementKey, amountKRW: 1234,
            currency: "KRW", taxInclusive: true)
        XCTAssertEqual(remote.storeDescription, catalog.description)
        XCTAssertEqual(remote.description, "이전 서버 소개")
        XCTAssertEqual(remote.amountKRW, 1234)
        XCTAssertEqual(CommerceProduct.snowflake.storeDescription, CommerceProduct.snowflake.description)
    }

    func testPairSheetFitsBothPurchaseCardsForAllOwnershipStates() throws {
        for product in CommerceCatalog.characterProducts {
            let item = try XCTUnwrap(CommerceCatalog.keepsake(for: product.id))
            for availability in [StoreAvailability.appStore] {
                for ownsCharacter in [false, true] {
                    for ownsItem in [false, true] {
                        let view = NSHostingView(rootView: StoreProductDetailSheet(
                            productState: .init(product: product,
                                purchaseState: ownsCharacter ? .owned : .available, isWorking: false),
                            relatedProductState: .init(product: item,
                                purchaseState: ownsItem ? .owned : .available, isWorking: false),
                            actions: .empty, availability: availability, onClose: {}))
                        XCTAssertEqual(view.fittingSize.width, 600, accuracy: 0.01, product.id)
                        XCTAssertLessThan(view.fittingSize.height, 720, product.id)
                    }
                }
            }
        }
    }
}
