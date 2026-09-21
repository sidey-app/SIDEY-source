import Foundation

/// A server may publish fewer products than the client knows during a staged rollout.
/// Returned known products must still have unambiguous, matching identities.
enum StoreCatalogResponse {
    enum ValidationError: Error, Equatable {
        case duplicateProduct(String)
        case mismatchedProduct(String)
    }

    static func validatedStates(_ rows: [DatabaseCommerceState]) throws -> [CommerceState] {
        var seen: Set<String> = []
        let states = try rows.compactMap { row -> CommerceState? in
            guard let registered = CommerceCatalog.product(id: row.productID) else { return nil }
            guard seen.insert(row.productID).inserted else {
                throw ValidationError.duplicateProduct(row.productID)
            }
            guard row.productKind == registered.kind,
                  row.catalogItemID == registered.catalogItemID,
                  row.characterID == registered.characterID,
                  row.entitlementKey == registered.entitlementKey,
                  row.sortOrder == registered.sortOrder,
                  row.characterID.map({ PixelCharacterCatalog.definition(for: $0).id == $0 }) ?? true
            else {
                throw ValidationError.mismatchedProduct(row.productID)
            }
            // The backend owns sale and entitlement state, not localized product copy.
            // Always retain the bundled product definition so remote Korean or stale
            // descriptions cannot replace the user's locale.
            return CommerceState(
                product: registered,
                googleConnected: row.googleConnected,
                entitlementStatus: row.entitlementStatus,
                latestOrderStatus: row.latestOrderStatus,
                isEquipped: row.isEquipped
            )
        }
        return states.sorted { $0.product.sortOrder < $1.product.sortOrder }
    }
}
