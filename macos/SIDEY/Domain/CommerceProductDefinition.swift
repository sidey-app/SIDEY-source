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
    func product(localization: CommerceProductLocalization) -> CommerceProduct {
        let price = appStorePrice
        return CommerceProduct(id: id, displayName: localization.displayName,
            description: localization.marketingDescription, kind: kind,
            catalogItemID: itemID, characterID: characterID, entitlementKey: entitlement,
            sortOrder: sortOrder, amountKRW: price, currency: "KRW", taxInclusive: true)
    }
}

struct CommerceProductLocalization: Decodable, Equatable, Sendable {
    let displayName: String
    let iapDescription: String
    let marketingDescription: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case iapDescription = "iap_description"
        case marketingDescription = "marketing_description"
    }
}

struct CommerceLocalizationDocument: Decodable, Sendable {
    struct Product: Decodable, Sendable {
        let id: String
        let localizations: [String: CommerceProductLocalization]
    }

    let schema: Int
    let locales: [String]
    let products: [Product]
}

enum CommerceLocalizationCatalog {
    static let supportedLocales = ["ko", "en", "ja", "zh-Hant"]

    static func resolvedLocale(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        locale: Locale = .current
    ) -> String {
        let candidates = preferredLocalizations.isEmpty ? [locale.identifier] : preferredLocalizations
        for candidate in candidates {
            let normalized = candidate.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized == "ko" || normalized.hasPrefix("ko-") { return "ko" }
            if normalized == "ja" || normalized.hasPrefix("ja-") { return "ja" }
            if normalized == "zh-hant" || normalized.hasPrefix("zh-hant-")
                || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk")
                || normalized.hasPrefix("zh-mo") {
                return "zh-Hant"
            }
            if normalized == "en" || normalized.hasPrefix("en-") { return "en" }
        }
        return "en"
    }

    static func load(
        bundle: Bundle = .main,
        preferredLocale: String? = nil
    ) -> [String: CommerceProductLocalization] {
        let url = bundle.url(
            forResource: "commerce-localizations",
            withExtension: "json",
            subdirectory: "Commerce"
        ) ?? bundle.url(forResource: "commerce-localizations", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(CommerceLocalizationDocument.self, from: data),
              document.schema == 1,
              document.locales == supportedLocales,
              Set(document.products.map(\.id)).count == document.products.count
        else {
            preconditionFailure("Bundled commerce localizations are invalid")
        }
        let locale = preferredLocale ?? resolvedLocale()
        return Dictionary(uniqueKeysWithValues: document.products.map { product in
            guard let value = product.localizations[locale] ?? product.localizations["en"] else {
                preconditionFailure("Bundled commerce localization is incomplete: \(product.id)")
            }
            return (product.id, value)
        })
    }
}
