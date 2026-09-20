import XCTest
@testable import SIDEYAppStore

@MainActor
final class SessionOwnershipTests: XCTestCase {
    func testRoomCancellationDoesNotCancelCommerceAndCommerceClearsEquipment() {
        let room = RoomSessionLifetime()
        let commerce = CommerceSession()
        let model = AppModel(preferences: .defaults)
        let roomTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        let purchaseTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        let equipmentTask = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        room.bootstrapTask = roomTask
        commerce.productTasks["product"] = purchaseTask
        commerce.equipmentTasks[.bubble] = equipmentTask
        XCTAssertTrue(model.beginCosmeticEquipmentRequest(kind: .bubble, catalogItemID: "bubble_bunny_pink"))

        room.cancel()
        XCTAssertTrue(roomTask.isCancelled)
        XCTAssertNil(room.bootstrapTask)
        XCTAssertFalse(purchaseTask.isCancelled)
        XCTAssertFalse(equipmentTask.isCancelled)
        XCTAssertNotNil(model.cosmeticEquipmentRequest(for: .bubble))

        commerce.cancel(model: model)
        XCTAssertTrue(purchaseTask.isCancelled)
        XCTAssertTrue(equipmentTask.isCancelled)
        XCTAssertTrue(commerce.productTasks.isEmpty)
        XCTAssertTrue(commerce.equipmentTasks.isEmpty)
        XCTAssertNil(model.cosmeticEquipmentRequest(for: .bubble))
        commerce.cancel(model: model)
        room.cancel()
    }
}
