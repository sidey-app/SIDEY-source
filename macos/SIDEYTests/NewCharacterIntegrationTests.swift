import AppKit
import SpriteKit
import XCTest
@testable import SIDEYAppStore

@MainActor
final class NewCharacterIntegrationTests: XCTestCase {
    func testPaidCharactersDefaultToBallAndKeepItemsIndependent() {
        for (character, item) in [("pixel_otter", "clam"), ("pixel_pig", "pork"), ("pixel_tree", "timber")] {
            XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: character), "patch_soft_ball")
            XCTAssertEqual(PixelCharacterThrowCatalog.resolvedObjectID(for: character, equippedObjectID: "throwable_" + item), item)
            XCTAssertFalse(PixelCharacterCatalog.canSelect(character, entitlementKeys: []))
            XCTAssertTrue(PixelCharacterCatalog.canSelect(character, entitlementKeys: ["character:\(character)"]))
            XCTAssertTrue(PixelCharacterThrowCatalog.supports(objectID: item))
        }
        XCTAssertEqual(CommerceProduct.otter.amountKRW, 1_100)
        XCTAssertEqual(CommerceProduct.pig.amountKRW, 1_100)
        XCTAssertEqual(CommerceProduct.tree.amountKRW, 1_100)
        for product in [CommerceProduct.snowflake, .baseball, .wakkuball, .dujjonku] {
            XCTAssertTrue(PixelCharacterThrowCatalog.purchasableObjectIDs.contains(product.catalogItemID))
            XCTAssertNotNil(product.automaticEquipmentAfterFreshPurchase)
        }
    }

    func testApprovedFivePreserveIndependentOwnershipAndRemoteCharacters() throws {
        XCTAssertEqual(PixelCharacterCatalog.all.count, 17)
        XCTAssertEqual(CharacterImpactAudio.objectIDs.count, 19)
        XCTAssertEqual(CommerceCatalog.products.count, 33)
        XCTAssertEqual(CommerceCatalog.products.filter { $0.id == "throwable_squeaky_duck" }.count, 1)
        for (name, object) in [("shiba", "tennis_ball"), ("duck", "throwable_squeaky_duck"),
                               ("poop", "tissue_ball"), ("tteokbokki", "fish_cake_skewer"), ("quokka", "leaf")] {
            let character = try XCTUnwrap(CommerceCatalog.product(id: "character_" + name))
            let characterID = try XCTUnwrap(character.characterID)
            let item = try XCTUnwrap(CommerceCatalog.keepsake(for: character.id))
            XCTAssertEqual(item.renderAssetID, object)
            XCTAssertNotEqual(character.entitlementKey, item.entitlementKey)
            XCTAssertFalse(PixelCharacterCatalog.canSelect(characterID, entitlementKeys: [item.entitlementKey]))
            XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: characterID), "patch_soft_ball")
            let preview = StorePreviewScenario.make(product: character)
            XCTAssertEqual(preview.members.first?.characterID, characterID)
            XCTAssertEqual(preview.characterThrowInteraction?.throwableID, object)

            let user = UUID(), friend = UUID(), room = UUID()
            var preferences = AppPreferences.defaults
            preferences.activeRoomID = room
            let model = AppModel(preferences: preferences)
            model.apply(snapshot: BackendSnapshot(
                profile: Profile(id: user, nickname: "나", characterID: characterID),
                rooms: [Room(id: room, name: "방", ownerID: user, members: [
                    RoomMember(userID: user, nickname: "나", characterID: characterID, presence: .online),
                    RoomMember(userID: friend, nickname: "친구", characterID: characterID, presence: .online)
                ], inviteCodeHint: "AB••••")], activeEntitlementKeys: [character.entitlementKey]), currentUserID: user)
            XCTAssertEqual(model.pixelWorldMembers.map(\.characterID), [characterID, characterID])
            XCTAssertTrue(model.selectableCharacters.contains { $0.id == characterID })
            XCTAssertNil(model.equippedThrowableID)
            model.apply(commerceState: CommerceState(product: character, googleConnected: true,
                entitlementStatus: "refunded", latestOrderStatus: "refunded"))
            XCTAssertEqual(model.selectedCharacterID, PixelCharacterCatalog.pixelHamsterID)
            XCTAssertEqual(model.pixelWorldMembers.first { $0.id == friend }?.characterID, characterID)
            XCTAssertFalse(model.selectableCharacters.contains { $0.id == characterID })
        }
    }

    func testAllCatalogPricesUseApprovedKoreanTiers() {
        let premium: Set<String> = ["bubble_bunny_pink", "bubble_butter_chick", "bubble_starry_cat",
                                    "character_starlight_upalupa", "throwable_dujjonku", "throwable_wakkuball"]
        for product in CommerceCatalog.products {
            let expected = product.id == "throwable_toy_cannon" ? 3_300
                : premium.contains(product.id) ? 2_200 : 1_100
            XCTAssertEqual(product.amountKRW, expected, product.id)
        }
    }

    func testTreeStaysPutThroughMovementAvoidanceAndResumesOnEveryEdge() {
        for edge in [OverlayEdge.bottom, .top, .left, .right] {
            let tree = UUID(), friend = UUID(), room = UUID()
            let scene = PixelWorldScene(size: CGSize(width: 600, height: 600), renderingConfiguration: .storePreview(initialTrackFractions: [tree: 0.3, friend: 0.31], fixedTrackFractions: [:]))
            scene.apply(roomID: room, members: [
                PixelWorldMember(id: tree, nickname: "나무", characterID: "pixel_tree", presence: .online, isTyping: false, isCurrentUser: true),
                PixelWorldMember(id: friend, nickname: "친구", characterID: "pixel_hamster", presence: .online, isTyping: false, isCurrentUser: false)
            ], bubbles: [], edge: edge, activityFrame: CGRect(x: 0, y: 0, width: 600, height: 600), installationSeed: 42, composerVisible: true)
            XCTAssertFalse(scene.toggleTreeMovement(for: friend))
            XCTAssertTrue(scene.toggleTreeMovement(for: tree))
            let initial = scene.agentStates.first { $0.id == tree }!.trackPosition
            for frame in 1...90 { scene.update(Double(frame) / 30) }
            XCTAssertEqual(scene.agentStates.first { $0.id == tree }!.trackPosition, initial, accuracy: 0.001)
            XCTAssertEqual(scene.agentStates.first { $0.id == tree }!.velocity, 0)
            XCTAssertTrue(scene.isTreeMovementPaused(for: tree))
            XCTAssertTrue(scene.toggleTreeMovement(for: tree))
            var moved = false
            for frame in 91...240 {
                scene.update(Double(frame) / 30)
                moved = moved || abs(scene.agentStates.first { $0.id == tree }!.trackPosition - initial) > 1
            }
            XCTAssertTrue(moved, "Tree must resume on \(edge)")
            XCTAssertFalse(PixelCharacterCatalog.definition(for: "pixel_tree").mirrorsToMovementDirection)
        }
    }

    func testTreePauseAndSoundPreferencesSurviveRelaunch() throws {
        var value = AppPreferences()
        value.treeMovementPaused = true
        value.characterSoundEffectsEnabled = false
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(restored.treeMovementPaused)
        XCTAssertFalse(restored.characterSoundEffectsEnabled)
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"schemaVersion":8}"#.utf8))
        XCTAssertFalse(old.treeMovementPaused)
        XCTAssertTrue(old.characterSoundEffectsEnabled)
    }
}
