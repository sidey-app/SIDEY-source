import Foundation

enum FirebaseV2GrantContractError: Error, Equatable {
    case missingRoomID
    case missingAccessRevision
}

struct FirebaseV2CreatedRoomGrant: Equatable, Sendable {
    let room: CreatedRoom
    let accessRevision: RealtimeRevision
}

struct FirebaseV2JoinedRoomGrant: Equatable, Sendable {
    let room: JoinedRoom
    let accessRevision: RealtimeRevision
}

struct FirebaseV2EquippedCosmeticGrant: Sendable {
    let profile: Profile
    let accessRevision: RealtimeRevision
}

struct FirebaseV2CreateRoomGrantRow: Decodable, Sendable {
    let roomID: UUID
    let inviteCode: String
    let accessRevision: RealtimeRevision

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case inviteCode = "invite_code"
        case accessRevision
    }
}

struct FirebaseV2JoinRoomGrant: Equatable, Sendable {
    let roomID: UUID
    let accessRevision: RealtimeRevision
}

struct FirebaseV2JoinRoomGrantRow: Decodable, Sendable {
    let roomID: UUID?
    let errorCode: String?
    let accessRevision: RealtimeRevision?

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case errorCode = "error_code"
        case accessRevision
    }

    func validatedGrant() throws -> FirebaseV2JoinRoomGrant {
        guard let roomID else { throw FirebaseV2GrantContractError.missingRoomID }
        guard let accessRevision else {
            throw FirebaseV2GrantContractError.missingAccessRevision
        }
        return FirebaseV2JoinRoomGrant(roomID: roomID, accessRevision: accessRevision)
    }
}

struct FirebaseV2EquipCosmeticGrantRow: Decodable, Sendable {
    let profile: DatabaseProfile
    let accessRevision: RealtimeRevision
}

struct FirebaseV2StoreWireItem: Decodable, Equatable, Sendable {
    let productKind: CommerceProductKind
    let catalogItemID: String
    let wireCode: FirebaseV2WireCode?

    private enum CodingKeys: String, CodingKey {
        case productKind = "product_kind"
        case catalogItemID = "catalog_item_id"
        case wireCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productKind = try container.decode(CommerceProductKind.self, forKey: .productKind)
        catalogItemID = try container.decode(String.self, forKey: .catalogItemID)
        guard let numericCode = try container.decodeIfPresent(Int.self, forKey: .wireCode) else {
            wireCode = nil
            return
        }
        guard let code = FirebaseV2WireCode(rawValue: String(numericCode)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .wireCode,
                in: container,
                debugDescription: "Wire code must be an integer from 0 through 999999."
            )
        }
        wireCode = code
    }
}
