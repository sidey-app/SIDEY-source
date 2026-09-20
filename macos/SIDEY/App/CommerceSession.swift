import Foundation

@MainActor
final class CommerceSession {
    let purchaseController = AppStorePurchaseController()
    let accountClient = AppStoreAccountClient()
    var productTasks: [String: Task<Void, Never>] = [:]
    var equipmentTasks: [CommerceProductKind: Task<Void, Never>] = [:]
    var characterTask: Task<Void, Never>?

    func cancel(model: AppModel) {
        productTasks.values.forEach { $0.cancel() }
        productTasks.removeAll()
        equipmentTasks.values.forEach { $0.cancel() }
        for kind in equipmentTasks.keys { model.endCosmeticEquipmentRequest(kind: kind) }
        equipmentTasks.removeAll()
        characterTask?.cancel()
        characterTask = nil
        model.endCharacterEquipmentRequest()
        purchaseController.stopObserving()
    }
}
