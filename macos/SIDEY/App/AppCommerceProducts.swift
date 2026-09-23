import Foundation
import Observation

@MainActor
@Observable
final class AppCommerceProducts {
    private(set) var commerceProducts: [CommerceProductState]

    init(products: [CommerceProduct]) {
        commerceProducts = products.map {
            CommerceProductState(product: $0, purchaseState: .confirming, isWorking: false)
        }
    }

    func apply(_ state: CommerceState) -> Bool {
        guard let index = commerceProducts.firstIndex(where: { $0.id == state.product.id }) else { return false }
        commerceProducts[index].purchaseState = state.purchaseState
        commerceProducts[index].isEquipped = state.isEquipped
        return true
    }

    func updateEquipment(characterID: String, bubbleID: String?, throwableID: String?) {
        for index in commerceProducts.indices {
            let product = commerceProducts[index].product
            commerceProducts[index].isEquipped = switch product.kind {
            case .character: product.characterID == characterID
            case .bubble: product.catalogItemID == bubbleID
            case .throwable: product.catalogItemID == throwableID
            }
        }
    }

    func setCommerceWorking(_ isWorking: Bool, productID: String) {
        guard let index = commerceProducts.firstIndex(where: { $0.id == productID }) else { return }
        commerceProducts[index].isWorking = isWorking
    }

    func setCommercePurchaseState(_ state: CommercePurchaseState, productID: String) {
        guard let index = commerceProducts.firstIndex(where: { $0.id == productID }) else { return }
        commerceProducts[index].purchaseState = state
    }

    func beginCommercePriceLoading() {
        for index in commerceProducts.indices {
            commerceProducts[index].priceLoadState = .loading
        }
    }

    func failCommercePriceLoading() {
        for index in commerceProducts.indices {
            commerceProducts[index].storefrontMetadata = nil
            commerceProducts[index].localizedPrice = nil
            commerceProducts[index].priceLoadState = .failed
        }
    }

    func setCommerceStorefrontMetadata(_ metadata: [String: StorefrontProductMetadata]) {
        for index in commerceProducts.indices {
            let productMetadata = metadata[commerceProducts[index].id]
            commerceProducts[index].storefrontMetadata = productMetadata
            commerceProducts[index].localizedPrice = productMetadata?.displayPrice
            commerceProducts[index].priceLoadState = productMetadata == nil
                ? .unavailable : .available
        }
    }

}
