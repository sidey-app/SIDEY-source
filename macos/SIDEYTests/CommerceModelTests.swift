import XCTest
@testable import SIDEYAppStore

@MainActor
final class CommerceModelTests: XCTestCase {
    func testCatalogProvidesRenderableProductsInDisplayOrder() throws {
        XCTAssertEqual(
            CommerceCatalog.products.map(\.id),
            [
                CommerceCatalog.starlightUpalupaProductID,
                CommerceCatalog.guineaPigProductID,
                CommerceCatalog.monkeyProductID,
                CommerceCatalog.chinchillaProductID,
                "character_otter", "character_pig", "character_tree",
                "character_shiba", "character_duck", "character_poop", "character_tteokbokki", "character_quokka",
                "bubble_bunny_pink",
                "bubble_butter_chick",
                "bubble_starry_cat",
                "throwable_bouncy_heart",
                "throwable_toy_cannon",
                "throwable_squeaky_duck",
            "throwable_snowflake", "throwable_baseball", "throwable_wakkuball", "throwable_dujjonku",
            "throwable_mini_paprika", "throwable_banana", "throwable_dust_bath_pouch", "throwable_starlight_orb", "throwable_clam", "throwable_pork", "throwable_timber",
            "throwable_tennis_ball", "throwable_tissue_ball", "throwable_fish_cake_skewer", "throwable_leaf",
            ]
        )
        for product in CommerceCatalog.characterProducts {
            let characterID = try XCTUnwrap(product.characterID)
            XCTAssertEqual(PixelCharacterCatalog.definition(for: characterID).id, characterID)
            XCTAssertEqual(
                PixelCharacterCatalog.definition(for: characterID).entitlementKey,
                product.entitlementKey
            )
        }
    }

    func testCosmeticCatalogKeepsApprovedKindsPricesAndOrdering() throws {
        XCTAssertEqual(CommerceCatalog.cosmeticProducts.map(\.kind), [
            .bubble, .bubble, .bubble, .throwable, .throwable, .throwable,
            .throwable, .throwable, .throwable, .throwable,
            .throwable, .throwable, .throwable, .throwable, .throwable, .throwable, .throwable,
            .throwable, .throwable, .throwable, .throwable,
        ])
        XCTAssertEqual(CommerceCatalog.cosmeticProducts.map(\.catalogItemID), [
            "bubble_bunny_pink",
            "bubble_butter_chick",
            "bubble_starry_cat",
            "throwable_bouncy_heart",
            "throwable_toy_cannon",
            "throwable_squeaky_duck",
            "throwable_snowflake", "throwable_baseball", "throwable_wakkuball", "throwable_dujjonku",
            "throwable_mini_paprika", "throwable_banana", "throwable_dust_bath_pouch", "throwable_starlight_orb", "throwable_clam", "throwable_pork", "throwable_timber",
            "throwable_tennis_ball", "throwable_tissue_ball", "throwable_fish_cake_skewer", "throwable_leaf",
        ])
        XCTAssertEqual(CommerceProduct.bunnyPinkBubble.amountKRW, 2_200)
        XCTAssertEqual(CommerceProduct.butterChickBubble.amountKRW, 2_200)
        XCTAssertEqual(CommerceProduct.starryCatBubble.amountKRW, 2_200)
        XCTAssertEqual(CommerceProduct.bouncyHeart.amountKRW, 1_100)
        XCTAssertEqual(CommerceProduct.toyCannon.amountKRW, 3_300)
        XCTAssertEqual(CommerceProduct.squeakyDuck.amountKRW, 1_100)
        XCTAssertTrue(CommerceCatalog.products.map(\.sortOrder).elementsEqual(
            CommerceCatalog.products.map(\.sortOrder).sorted()
        ))
        XCTAssertTrue(CommerceCatalog.cosmeticProducts.allSatisfy { $0.characterID == nil })
    }

    func testAppStoreAndStagingPreserveAuthenticationAndIsolateStorage() {
        for channel in [AppReleaseChannel.appStore, .staging] {
            XCTAssertTrue(channel.storeAvailability.usesAppStore)
            XCTAssertTrue(channel.requiresAppleAuthentication)
            XCTAssertEqual(channel.loginItemMode, .mainApp)
        }
        XCTAssertEqual(AppReleaseChannel.appStore.keychainService, "com.sidey.desktop.appstore")
        XCTAssertEqual(AppReleaseChannel.appStore.preferencesSuiteName, "app.sidey.desktop.appstore")
        XCTAssertNotEqual(AppReleaseChannel.appStore.keychainService, AppReleaseChannel.staging.keychainService)
        XCTAssertNotEqual(AppReleaseChannel.appStore.preferencesSuiteName, AppReleaseChannel.staging.preferencesSuiteName)
    }

    func testProfileCosmeticsUseOnlySnapshotEntitlementsAndKeepCatalogOrder() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)

        model.apply(commerceState: CommerceState(
            product: .starryCatBubble,
            googleConnected: true,
            entitlementStatus: "active",
            latestOrderStatus: "approved"
        ))
        XCTAssertTrue(model.ownedProfileCosmeticProducts(for: .bubble).isEmpty)

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "꾸미기친구",
                    characterID: PixelCharacterCatalog.pixelHamsterID
                ),
                rooms: [],
                activeEntitlementKeys: [
                    CommerceProduct.butterChickBubble.entitlementKey,
                    CommerceProduct.bunnyPinkBubble.entitlementKey,
                    CommerceProduct.squeakyDuck.entitlementKey,
                ]
            ),
            currentUserID: userID
        )

        XCTAssertEqual(model.ownedProfileCosmeticProducts(for: .bubble).map(\.catalogItemID), [
            CommerceProduct.bunnyPinkBubble.catalogItemID,
            CommerceProduct.butterChickBubble.catalogItemID,
        ])
        XCTAssertEqual(model.ownedProfileCosmeticProducts(for: .throwable).map(\.catalogItemID), [
            CommerceProduct.squeakyDuck.catalogItemID,
        ])
        XCTAssertTrue(model.ownedProfileCosmeticProducts(for: .character).isEmpty)

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "꾸미기친구",
                    characterID: PixelCharacterCatalog.pixelHamsterID
                ),
                rooms: [],
                activeEntitlementKeys: [CommerceProduct.squeakyDuck.entitlementKey]
            ),
            currentUserID: userID
        )
        XCTAssertTrue(model.ownedProfileCosmeticProducts(for: .bubble).isEmpty)
    }

    func testProfileCosmeticVisibilityShowsDefaultsInEveryDistribution() {
        XCTAssertTrue(ProfileCosmeticEquipmentPolicy.shouldShow(
            availability: .comingSoon
        ))
        XCTAssertTrue(ProfileCosmeticEquipmentPolicy.shouldShow(
            availability: .appStore
        ))
        XCTAssertTrue(ProfileCosmeticEquipmentPolicy.shouldShow(
            availability: .appStore
        ))
    }

    func testOnlyFreshCosmeticPurchasesRequestAutomaticEquipment() {
        XCTAssertNil(CommerceProduct.starlightUpalupa.automaticEquipmentAfterFreshPurchase)
        XCTAssertEqual(
            CommerceProduct.bunnyPinkBubble.automaticEquipmentAfterFreshPurchase,
            CosmeticEquipmentRequest(
                kind: .bubble,
                catalogItemID: CommerceProduct.bunnyPinkBubble.catalogItemID
            )
        )
        XCTAssertEqual(
            CommerceProduct.squeakyDuck.automaticEquipmentAfterFreshPurchase,
            CosmeticEquipmentRequest(
                kind: .throwable,
                catalogItemID: CommerceProduct.squeakyDuck.catalogItemID
            )
        )
    }

    func testCosmeticEquipmentRPCAlwaysEncodesExplicitNullCatalogKey() throws {
        let data = try JSONEncoder().encode(SetEquippedCosmeticParameters(
            productKind: .bubble,
            catalogItemID: nil
        ))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["p_product_kind"] as? String, "bubble")
        XCTAssertTrue(object.keys.contains("p_catalog_item_id"))
        XCTAssertTrue(object["p_catalog_item_id"] is NSNull)
    }

    func testCosmeticEquipmentSuccessCopyUsesCompletedEquipmentWording() {
        XCTAssertEqual(
            CosmeticEquipmentFeedback.successMessage(kind: .bubble, product: nil),
            "기본 말풍선을 장착했습니다."
        )
        XCTAssertEqual(
            CosmeticEquipmentFeedback.successMessage(kind: .bubble, product: .bunnyPinkBubble),
            "핑크 토끼 말풍선 장착했습니다."
        )
    }

    func testStoreSortingUsesStableCatalogAndPriceTieBreakers() {
        let states = [
            CommerceProductState(product: .toyCannon, purchaseState: .available, isWorking: false),
            CommerceProductState(product: .squeakyDuck, purchaseState: .available, isWorking: false),
            CommerceProductState(product: .bouncyHeart, purchaseState: .available, isWorking: false),
        ]

        XCTAssertEqual(StoreProductFilter.apply(
            states,
            kind: .throwable,
            sortOrder: .catalog,
            hidesOwned: false,
            activeEntitlementKeys: []
        ).map(\.id), [
            CommerceProduct.bouncyHeart.id,
            CommerceProduct.toyCannon.id,
            CommerceProduct.squeakyDuck.id,
        ])
        XCTAssertEqual(StoreProductFilter.apply(
            states,
            kind: .throwable,
            sortOrder: .priceAscending,
            hidesOwned: false,
            activeEntitlementKeys: []
        ).map(\.id), [
            CommerceProduct.bouncyHeart.id,
            CommerceProduct.squeakyDuck.id,
            CommerceProduct.toyCannon.id,
        ])
        XCTAssertEqual(StoreProductFilter.apply(
            states,
            kind: .throwable,
            sortOrder: .priceDescending,
            hidesOwned: false,
            activeEntitlementKeys: []
        ).map(\.id), [
            CommerceProduct.toyCannon.id,
            CommerceProduct.bouncyHeart.id,
            CommerceProduct.squeakyDuck.id,
        ])
    }

    func testStoreOwnedFilterUsesSnapshotEntitlementAndTreatsEquippedAsOwned() {
        let states = [
            CommerceProductState(product: .bouncyHeart, purchaseState: .available, isWorking: false),
            CommerceProductState(
                product: .toyCannon,
                purchaseState: .available,
                isWorking: false,
                isEquipped: true
            ),
            CommerceProductState(product: .squeakyDuck, purchaseState: .owned, isWorking: false),
        ]

        let visible = StoreProductFilter.apply(
            states,
            kind: .throwable,
            sortOrder: .catalog,
            hidesOwned: true,
            activeEntitlementKeys: [CommerceProduct.bouncyHeart.entitlementKey]
        )

        XCTAssertEqual(visible.map(\.id), [CommerceProduct.squeakyDuck.id])
    }

    func testCosmeticEquipmentRequestsBlockOnlyTheSameKindAndDoNotOptimisticallySelect() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "꾸미기친구",
                    characterID: PixelCharacterCatalog.pixelHamsterID,
                    equippedBubbleStyleID: CommerceProduct.bunnyPinkBubble.catalogItemID
                ),
                rooms: [],
                activeEntitlementKeys: [CommerceProduct.bunnyPinkBubble.entitlementKey]
            ),
            currentUserID: userID
        )

        XCTAssertTrue(model.beginCosmeticEquipmentRequest(kind: .bubble, catalogItemID: nil))
        XCTAssertFalse(model.beginCosmeticEquipmentRequest(
            kind: .bubble,
            catalogItemID: CommerceProduct.bunnyPinkBubble.catalogItemID
        ))
        XCTAssertTrue(model.beginCosmeticEquipmentRequest(
            kind: .throwable,
            catalogItemID: CommerceProduct.squeakyDuck.catalogItemID
        ))
        XCTAssertEqual(model.equippedBubbleStyleID, CommerceProduct.bunnyPinkBubble.catalogItemID)
        XCTAssertNil(model.equippedThrowableID)

        model.endCosmeticEquipmentRequest(kind: .bubble)
        model.apply(profile: Profile(
            id: userID,
            nickname: "꾸미기친구",
            characterID: PixelCharacterCatalog.pixelHamsterID,
            equippedBubbleStyleID: nil
        ))
        XCTAssertNil(model.equippedBubbleStyleID)

        model.endCosmeticEquipmentRequest(kind: .throwable)
        XCTAssertNil(model.cosmeticEquipmentRequest(for: .bubble))
        XCTAssertNil(model.cosmeticEquipmentRequest(for: .throwable))
    }

    func testTwoProductsKeepOrderAndUpdateStateIndependently() throws {
        let first = Self.fixtureProduct(id: "fixture_first", characterID: "pixel_hamster")
        let second = Self.fixtureProduct(id: "fixture_second", characterID: "pixel_cat")
        let model = AppModel(preferences: .defaults, commerceProducts: [second, first])

        XCTAssertEqual(model.commerceProducts.map(\.id), [second.id, first.id])

        model.apply(commerceState: CommerceState(
            product: first,
            googleConnected: true,
            entitlementStatus: "active",
            latestOrderStatus: "approved"
        ))
        model.setCommerceWorking(true, productID: second.id)
        model.setCommercePurchaseState(.error("두 번째 상품만 실패"), productID: second.id)

        XCTAssertEqual(model.commerceProducts.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.commerceProduct(id: first.id)?.purchaseState, .owned)
        XCTAssertFalse(try XCTUnwrap(model.commerceProduct(id: first.id)).isWorking)
        XCTAssertEqual(
            model.commerceProduct(id: second.id)?.purchaseState,
            .error("두 번째 상품만 실패")
        )
        XCTAssertTrue(try XCTUnwrap(model.commerceProduct(id: second.id)).isWorking)
    }

    func testStoreProductCardForwardsItsOwnProductIDForPurchase() {
        let product = Self.fixtureProduct(id: "fixture_selected", characterID: "pixel_rabbit")
        let state = CommerceProductState(product: product, purchaseState: .available, isWorking: false)
        var purchasedProductID: String?
        var actions = SettingsActions.empty
        actions.onPurchase = { purchasedProductID = $0 }

        StoreProductCard(productState: state, actions: actions).requestPurchase()

        XCTAssertEqual(purchasedProductID, product.id)
    }

    func testProductionLockedCardStillOpensProductPreview() {
        let product = Self.fixtureProduct(id: "fixture_locked", characterID: "pixel_rabbit")
        let state = CommerceProductState(product: product, purchaseState: .available, isWorking: false)
        var selectedProductID: String?

        StoreLockedProductCard(productState: state) {
            selectedProductID = state.id
        }.requestPreview()

        XCTAssertEqual(selectedProductID, product.id)
    }

    func testStoreKitLocalizedPriceOverridesDirectPrice() {
        let product = Self.fixtureProduct(id: "fixture_localized", characterID: "pixel_rabbit")
        let state = CommerceProductState(
            product: product,
            purchaseState: .available,
            isWorking: false,
            localizedPrice: "$0.99"
        )

        XCTAssertEqual(state.formattedPrice, "$0.99")
    }

    func testMissingApplePriceNeverDisplaysServerDirectPrice() {
        let state = CommerceProductState(product: .snowflake, purchaseState: .available, isWorking: false)
        XCTAssertEqual(state.priceLabel(for: .appStore), "가격 확인 필요")
        XCTAssertNotEqual(state.priceLabel(for: .appStore), state.product.formattedPrice)
    }

    func testPartialApplePriceResponseFinishesLoadingAndRetryRecoversMissingProduct() throws {
        let model = AppModel(preferences: .defaults, commerceProducts: [.snowflake, .baseball])
        model.setCommercePurchaseState(.owned, productID: CommerceProduct.baseball.id)
        model.beginCommercePriceLoading()
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.snowflake.id)?.priceLabel(for: .appStore), "가격 확인 중")
        model.setCommerceLocalizedPrices([CommerceProduct.baseball.id: "₩1,100"])
        let unavailable = try XCTUnwrap(model.commerceProduct(id: CommerceProduct.snowflake.id))
        XCTAssertEqual(unavailable.priceLoadState, .unavailable)
        XCTAssertEqual(unavailable.priceLabel(for: .appStore), "가격 확인 불가")
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.baseball.id)?.purchaseState, .owned)

        model.beginCommercePriceLoading()
        model.setCommerceLocalizedPrices([CommerceProduct.baseball.id: "₩1,100", CommerceProduct.snowflake.id: "₩1,100"])
        let recovered = try XCTUnwrap(model.commerceProduct(id: CommerceProduct.snowflake.id))
        XCTAssertEqual(recovered.priceLoadState, .available)
        XCTAssertEqual(recovered.priceLabel(for: .appStore), "₩1,100")
        XCTAssertEqual(model.commerceProduct(id: CommerceProduct.baseball.id)?.purchaseState, .owned)
    }

    func testFailedApplePriceRequestStopsLoadingWithoutInventingPrice() throws {
        let model = AppModel(preferences: .defaults, commerceProducts: [.snowflake])
        model.beginCommercePriceLoading()
        model.failCommercePriceLoading()
        let failed = try XCTUnwrap(model.commerceProduct(id: CommerceProduct.snowflake.id))
        XCTAssertEqual(failed.priceLoadState, .failed)
        XCTAssertNil(failed.localizedPrice)
        XCTAssertEqual(failed.priceLabel(for: .appStore), "가격 확인 불가")
    }

    func testStoreReactionPreviewFitsInsideItsCardWithoutUsingWorldScale() {
        XCTAssertEqual(StoreReactionPreviewStyle.peakScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(StoreReactionPreviewStyle.maximumRenderedCharacterSize, 139.2, accuracy: 0.001)
        XCTAssertLessThan(
            StoreReactionPreviewStyle.maximumRenderedCharacterSize,
            StoreCardLayout.minimumPreviewHeight
        )
        XCTAssertEqual(StoreCardLayout.aspectRatio, 1)
        XCTAssertGreaterThan(StoreCardLayout.footerMinimumSpacing, 0)
        XCTAssertNotEqual(StoreReactionPreviewStyle.peakScale, PixelCharacterPulseStyle.peakScale)
    }

    func testCosmeticGridFitsSixFiveAndFourColumnsAtResponsiveBodyWidths() {
        func columnCount(_ width: CGFloat) -> Int {
            Int((width + StoreCardLayout.spacing)
                / (StoreCardLayout.minimumWidth + StoreCardLayout.spacing))
        }

        XCTAssertEqual(columnCount(760), 6)
        XCTAssertEqual(columnCount(620), 5)
        XCTAssertEqual(columnCount(500), 4)
        XCTAssertEqual(StoreCardLayout.maximumWidth, 118)
        XCTAssertEqual(StoreCardLayout.cornerRadius, 18)
    }

    func testPurchaseStateRequiresGoogleAndReflectsOwnershipAndRefund() {
        let product = CommerceProduct.starlightUpalupa

        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: false,
            entitlementStatus: nil,
            latestOrderStatus: nil
        ).purchaseState, .available)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: nil,
            latestOrderStatus: nil
        ).purchaseState, .available)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: "active",
            latestOrderStatus: "approved"
        ).purchaseState, .owned)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded"
        ).purchaseState, .refunded)
    }

    func testCoreSnapshotDoesNotDependOnCommerceSchemaAvailability() {
        let ownedKey = CommerceCatalog.starlightUpalupaEntitlementKey

        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: [ownedKey],
                profileCharacterID: PixelCharacterCatalog.pixelHamsterID
            ),
            [ownedKey]
        )
        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: nil,
                profileCharacterID: PixelCharacterCatalog.pixelStarlightUpalupaID
            ),
            [ownedKey]
        )
        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: nil,
                profileCharacterID: PixelCharacterCatalog.pixelHamsterID
            ),
            []
        )
    }

    func testPaidCharacterAppearsOnlyWithActiveEntitlementAndRefundFallsBack() {
        let userID = UUID()
        let roomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        XCTAssertEqual(model.selectableCharacters.map(\.id), PixelCharacterCatalog.free.map(\.id))

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "별빛친구",
                    characterID: PixelCharacterCatalog.pixelStarlightUpalupaID
                ),
                rooms: [Room(
                    id: roomID,
                    name: "별빛방",
                    ownerID: userID,
                    members: [RoomMember(
                        userID: userID,
                        nickname: "별빛친구",
                        characterID: PixelCharacterCatalog.pixelStarlightUpalupaID,
                        presence: .online
                    )],
                    inviteCodeHint: "ST••••"
                )],
                activeEntitlementKeys: [CommerceCatalog.starlightUpalupaEntitlementKey]
            ),
            currentUserID: userID
        )
        XCTAssertTrue(model.selectableCharacters.contains {
            $0.id == PixelCharacterCatalog.pixelStarlightUpalupaID
        })
        XCTAssertEqual(
            model.pixelWorldMembers.first?.characterID,
            PixelCharacterCatalog.pixelStarlightUpalupaID
        )

        model.apply(commerceState: CommerceState(
            product: .starlightUpalupa,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded"
        ))
        XCTAssertEqual(model.selectedCharacterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertEqual(model.pixelWorldMembers.first?.characterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertEqual(model.selectableCharacters.map(\.id), PixelCharacterCatalog.free.map(\.id))
    }

    func testRevokedOrServerUnequippedCosmeticsImmediatelyFallBackToDefaults() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "꾸미기친구",
                    characterID: PixelCharacterCatalog.pixelHamsterID,
                    equippedBubbleStyleID: CommerceProduct.bunnyPinkBubble.catalogItemID,
                    equippedThrowableID: CommerceProduct.toyCannon.catalogItemID
                ),
                rooms: [],
                activeEntitlementKeys: [
                    CommerceProduct.bunnyPinkBubble.entitlementKey,
                    CommerceProduct.toyCannon.entitlementKey,
                ]
            ),
            currentUserID: userID
        )
        XCTAssertEqual(model.equippedBubbleStyleID, "bubble_bunny_pink")
        XCTAssertEqual(model.equippedThrowableID, "throwable_toy_cannon")

        model.apply(commerceState: CommerceState(
            product: .toyCannon,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded",
            isEquipped: false
        ))
        XCTAssertNil(model.equippedThrowableID)

        model.apply(commerceStates: [
            CommerceState(
                product: .bunnyPinkBubble,
                googleConnected: true,
                entitlementStatus: "active",
                latestOrderStatus: "approved",
                isEquipped: false
            ),
            CommerceState(
                product: .butterChickBubble,
                googleConnected: true,
                entitlementStatus: nil,
                latestOrderStatus: nil,
                isEquipped: false
            ),
            CommerceState(
                product: .starryCatBubble,
                googleConnected: true,
                entitlementStatus: nil,
                latestOrderStatus: nil,
                isEquipped: false
            ),
        ])
        XCTAssertNil(model.equippedBubbleStyleID)
    }

    private static func fixtureProduct(id: String, characterID: String) -> CommerceProduct {
        CommerceProduct(
            id: id,
            displayName: "테스트 캐릭터 \(id)",
            description: "카드 순서와 독립 상태를 확인하는 테스트 상품입니다.",
            characterID: characterID,
            entitlementKey: "character:\(characterID):\(id)",
            amountKRW: 1_200,
            currency: "KRW",
            taxInclusive: true
        )
    }
}
