import Foundation

/// Bundled metadata describes the product; server entitlements authorize its use.
struct CommerceProductDefinition: Decodable, Sendable {
    let id: String
    let name: String
    let description: String
    let kind: CommerceProductKind
    let itemID: String
    let characterID: String?
    let entitlement: String
    let sortOrder: Int
    let directPrice: Int
    let appStorePrice: Int
    let appStoreProductID: String
    let legacyAppStoreProductIDs: [String]
    let relatedCharacterProductID: String?
    let renderAssetID: String?
    enum CodingKeys: String, CodingKey {
        case id, name, description, kind, entitlement
        case itemID = "item_id", characterID = "character_id", sortOrder = "sort_order"
        case directPrice = "direct_price", appStorePrice = "app_store_price"
        case appStoreProductID = "app_store_product_id", legacyAppStoreProductIDs = "legacy_app_store_product_ids"
        case relatedCharacterProductID = "related_character_product_id", renderAssetID = "render_asset_id"
    }
    var product: CommerceProduct {
        let price = appStorePrice
        return CommerceProduct(id: id, displayName: name, description: description, kind: kind,
            catalogItemID: itemID, characterID: characterID, entitlementKey: entitlement,
            sortOrder: sortOrder, amountKRW: price, currency: "KRW", taxInclusive: true)
    }
}
