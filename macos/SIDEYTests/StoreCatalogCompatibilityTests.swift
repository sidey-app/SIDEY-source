import Foundation
import XCTest
@testable import SIDEYAppStore

@MainActor
final class StoreCatalogCompatibilityTests: XCTestCase {
    private let newIDs: Set<String> = [
        "character_shiba", "character_duck", "character_poop", "character_tteokbokki", "character_quokka",
        "throwable_tennis_ball", "throwable_tissue_ball", "throwable_fish_cake_skewer", "throwable_leaf"
    ]

    func testOlderServerCatalogKeepsExistingProductsAvailableAndOnlyMissingOffersUnavailable() throws {
        let rows = try CommerceCatalog.products.filter { !newIDs.contains($0.id) }.map { try row($0) }
        let states = try StoreCatalogResponse.validatedStates(Array(rows.reversed()))
        XCTAssertEqual(states.count, 24)
        XCTAssertEqual(states.map { $0.product.sortOrder }, states.map { $0.product.sortOrder }.sorted())
        for usesAppStore in [false, true] {
            let model = AppModel(preferences: .defaults)
            model.applyStoreCatalog(states, usesAppStore: usesAppStore)
            for state in model.commerceProducts {
                XCTAssertEqual(state.purchaseState, newIDs.contains(state.id) ? .unavailable : .available, state.id)
                XCTAssertEqual(state.purchaseState.canStartPurchase, !newIDs.contains(state.id), state.id)
            }
        }
    }

    func testUnknownProductsAreIgnoredWithoutGrantingTheirEntitlements() throws {
        let known = try row(.otter)
        let unknown = try row(.otter, overrides: ["product_id": "future_product", "entitlement_key": "future:key"])
        XCTAssertEqual(try StoreCatalogResponse.validatedStates([unknown, known, unknown]).map { $0.product.id }, [CommerceProduct.otter.id])
    }

    func testDuplicateKnownProductCannotHideAMissingProductInAnEqualSizedResponse() throws {
        var rows = try CommerceCatalog.products.map { try row($0) }
        rows[rows.count - 1] = rows[0]
        XCTAssertThrowsError(try StoreCatalogResponse.validatedStates(rows)) {
            XCTAssertEqual($0 as? StoreCatalogResponse.ValidationError, .duplicateProduct(rows[0].productID))
        }
    }

    func testKnownIdentityMismatchIsRejectedEvenInAPartialResponse() throws {
        let overrides: [[String: Any]] = [
            ["product_kind": "throwable"], ["catalog_item_id": "wrong"],
            ["character_id": "pixel_cat"], ["entitlement_key": "wrong:key"], ["sort_order": -1]
        ]
        for override in overrides {
            let invalid = try row(.otter, overrides: override)
            XCTAssertThrowsError(try StoreCatalogResponse.validatedStates([try row(.pig), invalid])) {
                XCTAssertEqual($0 as? StoreCatalogResponse.ValidationError, .mismatchedProduct(CommerceProduct.otter.id))
            }
        }
    }

    func testMissingOffersPreserveSnapshotOwnershipAndEquippedCosmetics() throws {
        let leaf = try product("throwable_leaf")
        let shiba = try product("character_shiba")
        let bubble = CommerceProduct.bunnyPinkBubble
        let model = ownedModel(character: shiba, bubble: bubble, throwable: leaf)
        let rows = try CommerceCatalog.products.filter {
            !newIDs.contains($0.id) && $0.id != bubble.id
        }.map { try row($0) }
        model.applyStoreCatalog(try StoreCatalogResponse.validatedStates(rows), usesAppStore: true)
        XCTAssertEqual(model.selectedCharacterID, shiba.characterID)
        XCTAssertEqual(model.equippedBubbleStyleID, bubble.catalogItemID)
        XCTAssertEqual(model.equippedThrowableID, leaf.catalogItemID)
        for owned in [shiba, bubble, leaf] {
            XCTAssertTrue(model.activeEntitlementKeys.contains(owned.entitlementKey))
            XCTAssertEqual(model.commerceProduct(id: owned.id)?.purchaseState, .owned)
            XCTAssertEqual(model.commerceProduct(id: owned.id)?.isEquipped, true)
        }
    }

    func testExplicitReturnedRevocationStillClearsOwnershipAndEquipment() throws {
        let leaf = try product("throwable_leaf")
        let shiba = try product("character_shiba")
        let bubble = CommerceProduct.bunnyPinkBubble
        let model = ownedModel(character: shiba, bubble: bubble, throwable: leaf)
        model.applyStoreCatalog(try StoreCatalogResponse.validatedStates([
            row(shiba), row(bubble), row(leaf)
        ]), usesAppStore: true)
        XCTAssertEqual(model.selectedCharacterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertNil(model.equippedBubbleStyleID)
        XCTAssertNil(model.equippedThrowableID)
        XCTAssertFalse(model.activeEntitlementKeys.contains(leaf.entitlementKey))
    }

    func testEmptyResponsePreservesOwnedItemsAndBlocksEveryUnownedOffer() throws {
        let shiba = try product("character_shiba")
        let model = ownedModel(character: shiba)
        model.applyStoreCatalog([], usesAppStore: true)
        for state in model.commerceProducts {
            XCTAssertEqual(state.purchaseState, state.id == shiba.id ? .owned : .unavailable, state.id)
        }
        XCTAssertEqual(model.selectedCharacterID, shiba.characterID)
    }

    func testFailedRefreshPreservesOwnedProductsAndSuccessfulResponseRecoversTransientStates() throws {
        let model = ownedModel(character: .otter)
        let rows = try CommerceCatalog.products.filter { !newIDs.contains($0.id) }.map {
            try row($0, overrides: $0.id == CommerceProduct.otter.id ? ["entitlement_status": "active", "is_equipped": true] : [:])
        }
        model.failStoreCatalogLoading(productIDs: CommerceCatalog.products.map(\.id))
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.otter.id)?.purchaseState, .owned)
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.pig.id)?.purchaseState, .error("상점 상태를 불러오지 못했습니다."))
        model.applyStoreCatalog(try StoreCatalogResponse.validatedStates(rows), usesAppStore: true)
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.pig.id)?.purchaseState, .available)
        XCTAssertEqual(model.commerceProduct(id: "character_shiba")?.purchaseState, .unavailable)
        let full = try CommerceCatalog.products.map {
            try row($0, overrides: $0.id == CommerceProduct.otter.id ? ["entitlement_status": "active", "is_equipped": true] : [:])
        }
        model.applyStoreCatalog(try StoreCatalogResponse.validatedStates(full), usesAppStore: true)
        XCTAssertEqual(model.commerceProduct(id: "character_shiba")?.purchaseState, .available)
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.otter.id)?.purchaseState, .owned)
    }

    func testAppStoreAvailabilityAndApplePriceAreIndependent() throws {
        let shiba = try product("character_shiba")
        let model = AppModel(preferences: .defaults)
        model.setCommerceLocalizedPrices([shiba.id: "₩1,100"])
        model.applyStoreCatalog([], usesAppStore: true)
        XCTAssertEqual(model.commerceProduct(id: shiba.id)?.purchaseState, .unavailable)
        XCTAssertFalse(try XCTUnwrap(model.commerceProduct(id: shiba.id)).purchaseState.canStartPurchase)
        model.applyStoreCatalog(try StoreCatalogResponse.validatedStates([row(shiba, overrides: ["google_connected": false])]), usesAppStore: true)
        XCTAssertEqual(model.commerceProduct(id: shiba.id)?.purchaseState, .available)
        XCTAssertEqual(model.commerceProduct(id: shiba.id)?.localizedPrice, "₩1,100")
    }

    func testPurchaseEntryRejectsUnavailableAndOtherNonPurchasableStates() {
        let blocked: [CommercePurchaseState] = [.unavailable, .owned, .error("failure"), .confirming, .openingCheckout]
        for state in blocked {
            XCTAssertFalse(state.canStartPurchase)
        }
        XCTAssertTrue(CommercePurchaseState.available.canStartPurchase)
        XCTAssertTrue(CommercePurchaseState.refunded.canStartPurchase)
        XCTAssertEqual(CommercePurchaseState.unavailable.label, "현재 구매 불가")
    }

    private func product(_ id: String) throws -> CommerceProduct {
        try XCTUnwrap(CommerceCatalog.product(id: id))
    }

    private func ownedModel(character: CommerceProduct, bubble: CommerceProduct? = nil, throwable: CommerceProduct? = nil) -> AppModel {
        let user = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(snapshot: BackendSnapshot(
            profile: Profile(id: user, nickname: "친구", characterID: character.characterID!,
                equippedBubbleStyleID: bubble?.catalogItemID, equippedThrowableID: throwable?.catalogItemID),
            rooms: [], activeEntitlementKeys: Set([character, bubble, throwable].compactMap { $0?.entitlementKey })
        ), currentUserID: user)
        return model
    }

    private func row(_ product: CommerceProduct, overrides: [String: Any] = [:]) throws -> DatabaseCommerceState {
        var value: [String: Any] = [
            "product_id": product.id, "display_name": product.displayName, "product_description": product.description,
            "product_kind": product.kind.rawValue, "catalog_item_id": product.catalogItemID,
            "character_id": product.characterID.map { $0 as Any } ?? NSNull(), "entitlement_key": product.entitlementKey,
            "sort_order": product.sortOrder, "amount_krw": product.amountKRW, "currency": "KRW", "tax_inclusive": true,
            "google_connected": true, "entitlement_status": NSNull(), "latest_order_status": NSNull(), "is_equipped": false
        ]
        value.merge(overrides) { _, new in new }
        return try JSONDecoder().decode(DatabaseCommerceState.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
