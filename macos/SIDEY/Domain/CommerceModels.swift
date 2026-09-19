import Foundation

enum CommerceCatalog {
    static let starlightUpalupaProductID = "character_starlight_upalupa"
    static let starlightUpalupaCharacterID = "pixel_starlight_upalupa"
    static let starlightUpalupaEntitlementKey = "character:pixel_starlight_upalupa"
    static let starlightUpalupaDescription = "진주빛 몸과 별빛 아가미를 가진 우파루파예요. 온라인일 때 별이 은은하게 따라다니고, 더블클릭하면 별무리가 두 겹으로 팡 터져요."

    static let guineaPigProductID = "character_guinea_pig"
    static let guineaPigEntitlementKey = "character:pixel_guinea_pig"
    static let monkeyProductID = "character_monkey"
    static let monkeyEntitlementKey = "character:pixel_monkey"
    static let chinchillaProductID = "character_chinchilla"
    static let chinchillaEntitlementKey = "character:pixel_chinchilla"

    static let products: [CommerceProduct] = definitions.map { $0.product }.sorted { $0.sortOrder < $1.sortOrder }
    static var characterProducts: [CommerceProduct] { products.filter { $0.kind == .character } }
    static var cosmeticProducts: [CommerceProduct] { products.filter { $0.kind != .character } }

    static func product(id: String) -> CommerceProduct? { products.first { $0.id == id } }
    static func product(appStoreID: String) -> CommerceProduct? {
        definitions.first { $0.appStoreProductID == appStoreID || $0.legacyAppStoreProductIDs.contains(appStoreID) }?.product
    }
    static func keepsake(for characterProductID: String) -> CommerceProduct? {
        products.first { $0.relatedCharacterProductID == characterProductID }
    }
    static func definition(id: String) -> CommerceProductDefinition? { definitions.first { $0.id == id } }
    private static let definitions: [CommerceProductDefinition] = {
        let url = Bundle.main.url(forResource: "commerce-catalog", withExtension: "json", subdirectory: "Commerce")
            ?? Bundle.main.url(forResource: "commerce-catalog", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([CommerceProductDefinition].self, from: data),
              Set(values.map(\.id)).count == values.count else {
            preconditionFailure("Bundled commerce catalog is invalid")
        }
        return values
    }()

}

enum CommerceProductKind: String, Codable, CaseIterable, Sendable {
    case character
    case bubble
    case throwable

    var title: String {
        switch self {
        case .character: "캐릭터"
        case .bubble: "말풍선"
        case .throwable: "투척물"
        }
    }
}

struct CosmeticEquipmentRequest: Equatable, Sendable {
    let kind: CommerceProductKind
    let catalogItemID: String?
}

struct CommerceProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let kind: CommerceProductKind
    let catalogItemID: String
    let characterID: String?
    let entitlementKey: String
    let sortOrder: Int
    let amountKRW: Int
    let currency: String
    let taxInclusive: Bool

    init(
        id: String,
        displayName: String,
        description: String,
        kind: CommerceProductKind = .character,
        catalogItemID: String? = nil,
        characterID: String?,
        entitlementKey: String,
        sortOrder: Int = 0,
        amountKRW: Int,
        currency: String,
        taxInclusive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.kind = kind
        self.catalogItemID = catalogItemID ?? characterID ?? id
        self.characterID = characterID
        self.entitlementKey = entitlementKey
        self.sortOrder = sortOrder
        self.amountKRW = amountKRW
        self.currency = currency
        self.taxInclusive = taxInclusive
    }

    static var starlightUpalupa: CommerceProduct { CommerceCatalog.product(id: "character_starlight_upalupa")! }
    static var guineaPig: CommerceProduct { CommerceCatalog.product(id: "character_guinea_pig")! }
    static var monkey: CommerceProduct { CommerceCatalog.product(id: "character_monkey")! }
    static var chinchilla: CommerceProduct { CommerceCatalog.product(id: "character_chinchilla")! }
    static var bunnyPinkBubble: CommerceProduct { CommerceCatalog.product(id: "bubble_bunny_pink")! }
    static var butterChickBubble: CommerceProduct { CommerceCatalog.product(id: "bubble_butter_chick")! }
    static var starryCatBubble: CommerceProduct { CommerceCatalog.product(id: "bubble_starry_cat")! }
    static var bouncyHeart: CommerceProduct { CommerceCatalog.product(id: "throwable_bouncy_heart")! }
    static var toyCannon: CommerceProduct { CommerceCatalog.product(id: "throwable_toy_cannon")! }
    static var squeakyDuck: CommerceProduct { CommerceCatalog.product(id: "throwable_squeaky_duck")! }
    static var otter: CommerceProduct { CommerceCatalog.product(id: "character_otter")! }
    static var pig: CommerceProduct { CommerceCatalog.product(id: "character_pig")! }
    static var tree: CommerceProduct { CommerceCatalog.product(id: "character_tree")! }
    static var snowflake: CommerceProduct { CommerceCatalog.product(id: "throwable_snowflake")! }
    static var baseball: CommerceProduct { CommerceCatalog.product(id: "throwable_baseball")! }
    static var wakkuball: CommerceProduct { CommerceCatalog.product(id: "throwable_wakkuball")! }
    static var dujjonku: CommerceProduct { CommerceCatalog.product(id: "throwable_dujjonku")! }

    var relatedCharacterProductID: String? { CommerceCatalog.definition(id: id)?.relatedCharacterProductID }
    var renderAssetID: String { CommerceCatalog.definition(id: id)?.renderAssetID ?? catalogItemID }
    var appStoreProductID: String { CommerceCatalog.definition(id: id)?.appStoreProductID ?? id }
    var isKeepsake: Bool { relatedCharacterProductID != nil }

    /// Character stories ship with the app so older server metadata cannot replace them.
    var storeDescription: String {
        guard kind == .character else { return description }
        return CommerceCatalog.definition(id: id)?.description ?? description
    }

    var formattedPrice: String {
        amountKRW.formatted(.number.grouping(.automatic)) + "원"
    }

    /// A newly completed cosmetic purchase should be immediately visible to
    /// the buyer. Restore and launch reconciliation intentionally never use
    /// this policy, so they cannot overwrite an existing selection.
    var automaticEquipmentAfterFreshPurchase: CosmeticEquipmentRequest? {
        guard kind != .character else { return nil }
        return CosmeticEquipmentRequest(kind: kind, catalogItemID: catalogItemID)
    }
}

enum StorePriceLoadState: Equatable, Sendable {
    case notRequested, loading, available, unavailable, failed
}

struct CommerceProductState: Equatable, Identifiable, Sendable {
    var product: CommerceProduct
    var purchaseState: CommercePurchaseState
    var isWorking: Bool
    var localizedPrice: String?
    var priceLoadState: StorePriceLoadState = .notRequested
    var isEquipped: Bool

    init(
        product: CommerceProduct,
        purchaseState: CommercePurchaseState,
        isWorking: Bool,
        localizedPrice: String? = nil,
        isEquipped: Bool = false
    ) {
        self.product = product
        self.purchaseState = purchaseState
        self.isWorking = isWorking
        self.localizedPrice = localizedPrice
        self.isEquipped = isEquipped
    }

    var id: String { product.id }
    var formattedPrice: String { localizedPrice ?? product.formattedPrice }

    func priceLabel(for availability: StoreAvailability) -> String {
        guard availability.usesAppStore else { return formattedPrice }
        if let localizedPrice { return localizedPrice }
        switch priceLoadState {
        case .loading: return "가격 확인 중"
        case .notRequested: return "가격 확인 필요"
        case .available, .unavailable, .failed: return "가격 확인 불가"
        }
    }
}

enum CommercePurchaseState: Equatable, Sendable {
    case available
    case openingCheckout
    case confirming
    case owned
    case error(String)
    case unavailable
    case refunded

    var canStartPurchase: Bool { self == .available || self == .refunded }

    var label: String {
        switch self {
        case .available: "구매 가능"
        case .openingCheckout: "결제창 여는 중"
        case .confirming: "확인 중"
        case .owned: "보유 중"
        case .error: "오류"
        case .unavailable: "현재 구매 불가"
        case .refunded: "환불됨"
        }
    }
}

struct CommerceState: Equatable, Sendable {
    let product: CommerceProduct
    let googleConnected: Bool
    let entitlementStatus: String?
    let latestOrderStatus: String?
    let isEquipped: Bool

    init(
        product: CommerceProduct,
        googleConnected: Bool,
        entitlementStatus: String?,
        latestOrderStatus: String?,
        isEquipped: Bool = false
    ) {
        self.product = product
        self.googleConnected = googleConnected
        self.entitlementStatus = entitlementStatus
        self.latestOrderStatus = latestOrderStatus
        self.isEquipped = isEquipped
    }

    var purchaseState: CommercePurchaseState {
        if entitlementStatus == "active" { return .owned }
        if entitlementStatus == "refunded" || latestOrderStatus == "refunded" { return .refunded }
        return .available
    }
}

enum StoreAvailability: Equatable {
    case comingSoon
    case appStore

    var allowsCommerceActions: Bool { self != .comingSoon }
    var allowsCosmeticEquipment: Bool { true }
    var usesAppStore: Bool { self == .appStore }

    var unavailableDetailMessage: String? {
        self == .comingSoon
            ? "상점은 준비 중입니다. 빠른 시일 내에 만나요."
            : nil
    }
}
