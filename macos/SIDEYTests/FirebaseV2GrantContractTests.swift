import XCTest
@testable import SIDEY

final class FirebaseV2GrantContractTests: XCTestCase {
    func testOnlyEquippedThrowablesRequireFirebaseWireEntitlementConvergence() {
        XCTAssertTrue(FirebaseV2CommerceGrantPolicy.requiresEntitlement(
            kind: .throwable,
            catalogItemID: "throwable_leaf"
        ))
        XCTAssertFalse(FirebaseV2CommerceGrantPolicy.requiresEntitlement(
            kind: .bubble,
            catalogItemID: "bubble_bunny_pink"
        ))
        XCTAssertFalse(FirebaseV2CommerceGrantPolicy.requiresEntitlement(
            kind: .throwable,
            catalogItemID: nil
        ))
    }

    func testCreateRoomGrantDecodesExactRevision() throws {
        let row = try JSONDecoder().decode(
            FirebaseV2CreateRoomGrantRow.self,
            from: Data("""
            {
                "room_id":"11111111-1111-4111-8111-111111111111",
                "invite_code":"SIDEY123",
                "accessRevision":"00000000000000000042"
            }
            """.utf8)
        )

        XCTAssertEqual(row.inviteCode, "SIDEY123")
        XCTAssertEqual(row.accessRevision.rawValue, "00000000000000000042")
    }

    func testJoinFailureMayOmitRevisionButSuccessRequiresItDuringValidation() throws {
        let failure = try JSONDecoder().decode(
            FirebaseV2JoinRoomGrantRow.self,
            from: Data(#"{"room_id":null,"error_code":"invalid_invite_code","accessRevision":null}"#.utf8)
        )
        XCTAssertEqual(failure.errorCode, "invalid_invite_code")
        XCTAssertNil(failure.accessRevision)

        let malformedSuccess = try JSONDecoder().decode(
            FirebaseV2JoinRoomGrantRow.self,
            from: Data("""
            {
                "room_id":"11111111-1111-4111-8111-111111111111",
                "error_code":null,
                "accessRevision":null
            }
            """.utf8)
        )
        XCTAssertThrowsError(try malformedSuccess.validatedGrant()) { error in
            XCTAssertEqual(error as? FirebaseV2GrantContractError, .missingAccessRevision)
        }
    }

    func testEquipGrantDecodesProfileAndRevision() throws {
        let row = try JSONDecoder().decode(
            FirebaseV2EquipCosmeticGrantRow.self,
            from: Data("""
            {
                "profile":{
                    "id":"22222222-2222-4222-8222-222222222222",
                    "nickname":"사이디",
                    "character_id":"pixel_hamster",
                    "equipped_bubble_style_id":null,
                    "equipped_throwable_id":"throwable_leaf",
                    "tree_movement_paused":false,
                    "tree_movement_revision":3
                },
                "accessRevision":"00000000000000000043"
            }
            """.utf8)
        )

        XCTAssertEqual(row.profile.equippedThrowableID, "throwable_leaf")
        XCTAssertEqual(row.accessRevision.rawValue, "00000000000000000043")
    }

    func testStoreWireCodeNormalizesPostgresIntegerToCanonicalWireString() throws {
        let item = try JSONDecoder().decode(
            FirebaseV2StoreWireItem.self,
            from: Data("""
            {
                "product_kind":"throwable",
                "catalog_item_id":"throwable_leaf",
                "wireCode":18
            }
            """.utf8)
        )

        XCTAssertEqual(item.wireCode?.rawValue, "18")
        XCTAssertEqual(item.catalogItemID, "throwable_leaf")
    }

    func testStoreWireCodeRejectsOutOfContractValues() {
        for wireCode in [-1, 1_000_000] {
            let body = """
            {
                "product_kind":"throwable",
                "catalog_item_id":"throwable_leaf",
                "wireCode":\(wireCode)
            }
            """
            XCTAssertThrowsError(try JSONDecoder().decode(
                FirebaseV2StoreWireItem.self,
                from: Data(body.utf8)
            ))
        }
    }
}
