import Foundation

struct BackendSnapshot: Equatable, Sendable {
    var profile: Profile?
    var rooms: [Room]
    var activeEntitlementKeys: Set<String> = []
}

struct BackendReconciliation: Equatable, Sendable {
    let snapshot: BackendSnapshot
    let activeRoomID: UUID?
    let activeMessages: [ChatMessage]
}

struct BackendConnectionStatus: Equatable, Sendable {
    let transportConnected: Bool
    let recoveryReconciled: Bool
    let activeRoomTransportConnected: Bool

    init(
        transportConnected: Bool,
        recoveryReconciled: Bool,
        activeRoomTransportConnected: Bool? = nil
    ) {
        self.transportConnected = transportConnected
        self.recoveryReconciled = recoveryReconciled
        self.activeRoomTransportConnected = activeRoomTransportConnected ?? transportConnected
    }

    var isReady: Bool {
        transportConnected && recoveryReconciled
    }
}

enum RealtimeConnectionStatusPolicy {
    static func resolve(
        pathAvailable: Bool,
        socketAvailable: Bool,
        recoveryTaskRunning: Bool,
        rebuildingChannels: Bool,
        allRoomsSubscribed: Bool,
        recoveryReconciled: Bool,
        hasActiveRoom: Bool,
        activeRoomSubscribed: Bool
    ) -> BackendConnectionStatus {
        let aggregateTransportConnected = pathAvailable
            && socketAvailable
            && !recoveryTaskRunning
            && !rebuildingChannels
            && allRoomsSubscribed
        let activeTransportConnected = hasActiveRoom
            ? pathAvailable && socketAvailable && activeRoomSubscribed
            : aggregateTransportConnected
        return BackendConnectionStatus(
            transportConnected: aggregateTransportConnected,
            recoveryReconciled: recoveryReconciled,
            activeRoomTransportConnected: activeTransportConnected
        )
    }
}

struct MessageHistoryCursor: Equatable, Sendable {
    let rawCreatedAt: String
    let id: UUID
}

struct MessageHistoryPage: Equatable, Sendable {
    let messages: [ChatMessage]
    let nextCursor: MessageHistoryCursor?
}

enum BackendEvent: Sendable {
    case snapshot(BackendSnapshot)
    case reconciliation(BackendReconciliation)
    case message(ChatMessage)
    case messageDeleted(roomID: UUID, messageID: UUID)
    case messagesInvalidated(roomID: UUID)
    case messagesReplaced(roomID: UUID, messages: [ChatMessage])
    case presence(roomID: UUID, userID: UUID, state: PresenceState)
    case typing(roomID: UUID, userID: UUID, active: Bool)
    case characterPulse(CharacterPulseEvent)
    case characterThrow(CharacterThrowEvent)
    case connection(BackendConnectionStatus)
    case technicalError(String)
}

struct CreatedRoom: Equatable, Sendable {
    let roomID: UUID
    let inviteCode: String
    let storedInKeychain: Bool
}

struct JoinedRoom: Equatable, Sendable {
    let roomID: UUID
    let storedInKeychain: Bool
}

enum BackendConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case online
    case failed(String)

    var label: String {
        switch self {
        case .idle: "대기 중"
        case .connecting: "연결 중"
        case .online: "연결됨"
        case .failed: "연결 오류"
        }
    }
}

struct DatabaseProfile: Codable, Sendable {
    let id: UUID
    let nickname: String
    let characterID: String
    let equippedBubbleStyleID: String?
    let equippedThrowableID: String?
    var treeMovementPaused: Bool? = nil
    var treeMovementRevision: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case characterID = "character_id"
        case equippedBubbleStyleID = "equipped_bubble_style_id"
        case equippedThrowableID = "equipped_throwable_id"
        case treeMovementPaused = "tree_movement_paused"
        case treeMovementRevision = "tree_movement_revision"
    }

    var domain: Profile {
        Profile(
            id: id,
            nickname: nickname,
            characterID: PixelCharacterCatalog.canonicalID(for: characterID),
            equippedBubbleStyleID: equippedBubbleStyleID,
            equippedThrowableID: equippedThrowableID,
            treeMovementPaused: treeMovementPaused ?? false,
            treeMovementRevision: treeMovementRevision
        )
    }
}

struct DatabaseRoom: Codable, Sendable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let inviteCodeHint: String
    let inviteCodeReady: Bool
    let realtimeEpoch: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case inviteCodeHint = "invite_code_hint"
        case inviteCodeReady = "invite_code_ready"
        case realtimeEpoch = "realtime_epoch"
        case createdAt = "created_at"
    }
}

struct DatabaseMembership: Codable, Sendable {
    let roomID: UUID
    let userID: UUID
    let joinedAt: String

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

struct DatabaseCommerceEntitlement: Codable, Sendable {
    let entitlementKey: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case entitlementKey = "entitlement_key"
    }
}

enum CommerceEntitlementSnapshotPolicy {
    static func resolvedKeys(
        remoteKeys: Set<String>?,
        profileCharacterID: String?
    ) -> Set<String> {
        if let remoteKeys { return remoteKeys }
        guard let profileCharacterID,
              let entitlementKey = PixelCharacterCatalog
                .definition(for: profileCharacterID)
                .entitlementKey
        else { return [] }
        return [entitlementKey]
    }
}

struct DatabaseCommerceState: Codable, Sendable {
    let productID: String
    let displayName: String
    let productDescription: String
    let productKind: CommerceProductKind
    let catalogItemID: String
    let characterID: String?
    let entitlementKey: String
    let sortOrder: Int
    let amountKRW: Int
    let currency: String
    let taxInclusive: Bool
    let googleConnected: Bool
    let entitlementStatus: String?
    let latestOrderStatus: String?
    let isEquipped: Bool

    enum CodingKeys: String, CodingKey {
        case currency
        case productID = "product_id"
        case displayName = "display_name"
        case productDescription = "product_description"
        case productKind = "product_kind"
        case catalogItemID = "catalog_item_id"
        case characterID = "character_id"
        case entitlementKey = "entitlement_key"
        case sortOrder = "sort_order"
        case amountKRW = "amount_krw"
        case taxInclusive = "tax_inclusive"
        case googleConnected = "google_connected"
        case entitlementStatus = "entitlement_status"
        case latestOrderStatus = "latest_order_status"
        case isEquipped = "is_equipped"
    }

    var domain: CommerceState {
        CommerceState(
            product: CommerceProduct(
                id: productID,
                displayName: displayName,
                description: productDescription,
                kind: productKind,
                catalogItemID: catalogItemID,
                characterID: characterID,
                entitlementKey: entitlementKey,
                sortOrder: sortOrder,
                amountKRW: amountKRW,
                currency: currency,
                taxInclusive: taxInclusive
            ),
            googleConnected: googleConnected,
            entitlementStatus: entitlementStatus,
            latestOrderStatus: latestOrderStatus,
            isEquipped: isEquipped
        )
    }
}

struct DatabaseMessage: Codable, Sendable {
    let id: UUID
    let roomID: UUID
    let senderID: UUID
    let body: String
    let createdAt: String
    let bubbleStyleID: String?

    init(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        createdAt: String,
        bubbleStyleID: String? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.body = body
        self.createdAt = createdAt
        self.bubbleStyleID = bubbleStyleID
    }

    enum CodingKeys: String, CodingKey {
        case id, body
        case roomID = "room_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
        case bubbleStyleID = "bubble_style_id"
    }

    var domain: ChatMessage {
        get throws {
            ChatMessage(
                id: id,
                roomID: roomID,
                senderID: senderID,
                body: body,
                createdAt: try PostgresTimestampDecoder.decode(createdAt),
                bubbleStyleID: bubbleStyleID
            )
        }
    }
}

enum MessageHistoryPageMapper {
    static func page(
        from orderedRows: [DatabaseMessage],
        pageSize: Int
    ) throws -> MessageHistoryPage {
        let boundedPageSize = min(max(pageSize, 1), 50)
        let visibleRows = Array(orderedRows.prefix(boundedPageSize))
        let messages = try visibleRows.map { try $0.domain }
        let nextCursor = orderedRows.count > boundedPageSize
            ? visibleRows.last.map {
                MessageHistoryCursor(rawCreatedAt: $0.createdAt, id: $0.id)
            }
            : nil
        return MessageHistoryPage(messages: messages, nextCursor: nextCursor)
    }
}

enum PostgresTimestampDecoder {
    private static let shape = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$"#
    )

    static func decode(_ value: String) throws -> Date {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let bytes = Array(value.utf8)
        guard shape.firstMatch(in: value, range: range)?.range == range,
              bytes.count >= 20,
              let year = integer(bytes, 0..<4),
              let month = integer(bytes, 5..<7),
              let day = integer(bytes, 8..<10),
              let hour = integer(bytes, 11..<13),
              let minute = integer(bytes, 14..<16),
              let second = integer(bytes, 17..<19)
        else {
            throw SideyBackendError.invalidTimestamp
        }

        var suffixIndex = 19
        var fractionalSeconds = 0.0
        if bytes[suffixIndex] == Character(".").asciiValue! {
            let fractionStart = suffixIndex + 1
            suffixIndex = fractionStart
            while suffixIndex < bytes.count,
                  bytes[suffixIndex] >= Character("0").asciiValue!,
                  bytes[suffixIndex] <= Character("9").asciiValue! {
                suffixIndex += 1
            }
            guard let fraction = integer(bytes, fractionStart..<suffixIndex) else {
                throw SideyBackendError.invalidTimestamp
            }
            fractionalSeconds = Double(fraction)
                / pow(10, Double(suffixIndex - fractionStart))
        }

        let offsetSeconds: TimeInterval
        if bytes[suffixIndex] == Character("Z").asciiValue! {
            offsetSeconds = 0
        } else {
            guard suffixIndex + 6 == bytes.count,
                  let offsetHour = integer(bytes, (suffixIndex + 1)..<(suffixIndex + 3)),
                  let offsetMinute = integer(bytes, (suffixIndex + 4)..<(suffixIndex + 6)),
                  offsetHour <= 23,
                  offsetMinute <= 59
            else {
                throw SideyBackendError.invalidTimestamp
            }
            let direction = bytes[suffixIndex] == Character("+").asciiValue! ? 1.0 : -1.0
            offsetSeconds = direction * TimeInterval((offsetHour * 60 + offsetMinute) * 60)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let wholeSeconds = calendar.date(from: components) else {
            throw SideyBackendError.invalidTimestamp
        }
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wholeSeconds
        )
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day,
              roundTrip.hour == hour,
              roundTrip.minute == minute,
              roundTrip.second == second
        else {
            throw SideyBackendError.invalidTimestamp
        }
        return wholeSeconds.addingTimeInterval(fractionalSeconds - offsetSeconds)
    }

    private static func integer(_ bytes: [UInt8], _ range: Range<Int>) -> Int? {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= bytes.count else {
            return nil
        }
        var result = 0
        for index in range {
            let byte = bytes[index]
            guard byte >= Character("0").asciiValue!,
                  byte <= Character("9").asciiValue!
            else { return nil }
            result = (result * 10) + Int(byte - Character("0").asciiValue!)
        }
        return result
    }
}

enum PostgresTimestampEncoder {
    static func encode(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }
}

struct UpsertProfileParameters: Encodable, Sendable {
    let nickname: String
    let characterID: String

    enum CodingKeys: String, CodingKey {
        case nickname = "p_nickname"
        case characterID = "p_character_id"
    }
}

struct CreateRoomParameters: Encodable, Sendable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "p_name" }
}

struct CreateRoomRow: Decodable, Sendable {
    let roomID: UUID
    let inviteCode: String
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case inviteCode = "invite_code"
    }
}

struct JoinRoomParameters: Encodable, Sendable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case inviteCode = "p_invite_code" }
}

struct JoinRoomRow: Decodable, Sendable {
    let roomID: UUID?
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case errorCode = "error_code"
    }
}

struct LeaveRoomParameters: Encodable, Sendable {
    let roomID: UUID
    enum CodingKeys: String, CodingKey { case roomID = "p_room_id" }
}

struct RenameRoomParameters: Encodable, Sendable {
    let roomID: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case roomID = "p_room_id"
        case name = "p_name"
    }
}

struct RemoveRoomMemberParameters: Encodable, Sendable {
    let roomID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case roomID = "p_room_id"
        case userID = "p_user_id"
    }
}

struct DeleteRoomParameters: Encodable, Sendable {
    let roomID: UUID
    enum CodingKeys: String, CodingKey { case roomID = "p_room_id" }
}

struct SendMessageParameters: Encodable, Sendable {
    let id: UUID
    let roomID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case roomID = "p_room_id"
        case body = "p_body"
    }
}

struct PresencePayload: Codable, Sendable {
    let userID: UUID
    let state: PresenceState
    let onlineAt: String

    enum CodingKeys: String, CodingKey {
        case state
        case userID = "user_id"
        case onlineAt = "online_at"
    }
}

struct PresencePublicationIntent: Equatable, Sendable {
    let activeRoomID: UUID?
    let localPresence: PresenceState
}

struct TypingPayload: Codable, Sendable {
    let roomID: UUID
    let userID: UUID
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case userID = "user_id"
    }
}

struct CharacterPulsePayload: Codable, Sendable {
    let roomID: UUID
    let userID: UUID
    let eventID: UUID

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case userID = "user_id"
        case eventID = "event_id"
    }
}

struct CharacterThrowPayload: Codable, Sendable {
    let schemaVersion: Int
    let roomID: UUID
    let eventID: UUID
    let actorUserID: UUID
    let targetUserID: UUID
    let sourceCharacterID: String
    let throwableID: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case roomID = "room_id"
        case eventID = "event_id"
        case actorUserID = "actor_user_id"
        case targetUserID = "target_user_id"
        case sourceCharacterID = "source_character_id"
        case throwableID = "throwable_id"
    }
}

struct DatabaseChangePayload: Codable, Sendable {
    let roomID: UUID
    let operation: String?
    let messageID: UUID?
    let entity: String?
    let realtimeEpoch: Int?

    enum CodingKeys: String, CodingKey {
        case operation, entity
        case roomID = "room_id"
        case messageID = "message_id"
        case realtimeEpoch = "realtime_epoch"
    }
}

struct BroadcastRoomEventParameters: Encodable, Sendable {
    let roomID: UUID
    let realtimeEpoch: Int
    let event: String
    let eventID: UUID?

    enum CodingKeys: String, CodingKey {
        case roomID = "p_room_id"
        case realtimeEpoch = "p_realtime_epoch"
        case event = "p_event"
        case eventID = "p_event_id"
    }
}

struct BroadcastCharacterThrowParameters: Encodable, Sendable {
    let roomID: UUID
    let realtimeEpoch: Int
    let eventID: UUID
    let targetUserID: UUID

    enum CodingKeys: String, CodingKey {
        case roomID = "p_room_id"
        case realtimeEpoch = "p_realtime_epoch"
        case eventID = "p_event_id"
        case targetUserID = "p_target_user_id"
    }
}

struct SetEquippedCosmeticParameters: Encodable, Sendable {
    let productKind: CommerceProductKind
    let catalogItemID: String?

    enum CodingKeys: String, CodingKey {
        case productKind = "p_product_kind"
        case catalogItemID = "p_catalog_item_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(productKind, forKey: .productKind)
        // PostgREST distinguishes an omitted RPC argument from an explicit
        // SQL NULL. Always include the key so both client/server versions can
        // reliably return to the default cosmetic.
        try container.encode(catalogItemID, forKey: .catalogItemID)
    }
}

struct RotateInviteCodeParameters: Encodable, Sendable {
    let roomID: UUID
    enum CodingKeys: String, CodingKey { case roomID = "p_room_id" }
}

enum SideyBackendError: LocalizedError, Equatable {
    case invalidProfile
    case invalidRoomName
    case invalidInviteCode
    case inviteRateLimited
    case roomLimitReached
    case memberLimitReached
    case alreadyMember
    case profileRequired
    case ownerRequired
    case memberNotFound
    case membershipRequired
    case ownerCannotRemoveSelf
    case noActiveRoom
    case malformedResponse
    case invalidTimestamp
    case sessionRecoveryFailed
    case realtimeUnavailable
    case staleRealtimeEpoch
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile: "닉네임은 줄바꿈 없이 2~8자로 입력해 주세요."
        case .invalidRoomName: "그룹 이름은 줄바꿈 없이 1~20자로 입력해 주세요."
        case .invalidInviteCode: "초대 코드를 다시 확인해 주세요."
        case .inviteRateLimited: "초대 코드 시도가 너무 많습니다. 10분 뒤 다시 시도해 주세요."
        case .roomLimitReached: "한 사용자는 그룹을 최대 5개까지 사용할 수 있습니다."
        case .memberLimitReached: "이 그룹은 이미 \(ProductLimits.maximumRoomMembers)명으로 가득 찼습니다."
        case .alreadyMember: "이미 참여 중인 그룹입니다."
        case .profileRequired: "프로필을 먼저 저장해 주세요."
        case .ownerRequired: "방장만 이 작업을 할 수 있습니다."
        case .memberNotFound: "내보낼 멤버를 찾지 못했습니다."
        case .membershipRequired: "이 그룹의 멤버만 이 작업을 할 수 있습니다."
        case .ownerCannotRemoveSelf: "방장 본인은 내보낼 수 없습니다."
        case .noActiveRoom: "메시지를 보낼 그룹이 없습니다."
        case .malformedResponse: "서버 응답 형식을 해석하지 못했습니다."
        case .invalidTimestamp: "서버 메시지 시각을 해석하지 못했습니다."
        case .sessionRecoveryFailed: "기존 로그인 세션을 복구하지 못했습니다. 새 계정은 만들지 않았으니 다시 로그인하거나 지원을 요청해 주세요."
        case .realtimeUnavailable: "실시간 연결이 준비되지 않았습니다."
        case .staleRealtimeEpoch: "그룹 권한이 변경되어 실시간 연결을 새로 고쳐야 합니다."
        case .remote(let message): message
        }
    }

    static func business(code: String) -> Self {
        switch code {
        case "invalid_invite_code": .invalidInviteCode
        case "invite_rate_limited": .inviteRateLimited
        case "room_limit_reached": .roomLimitReached
        case "member_limit_reached": .memberLimitReached
        case "already_a_member": .alreadyMember
        case "profile_required": .profileRequired
        case "owner_required": .ownerRequired
        case "member_not_found": .memberNotFound
        case "membership_required": .membershipRequired
        case "owner_must_leave": .ownerCannotRemoveSelf
        case "invalid_room_name": .invalidRoomName
        case "stale_realtime_epoch": .staleRealtimeEpoch
        default: .remote(code)
        }
    }

    static func normalized(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        let description = error.localizedDescription
        let diagnostic = description + " " + String(reflecting: error)
        let knownCodes = [
            "invalid_room_name",
            "owner_required",
            "member_not_found",
            "membership_required",
            "owner_must_leave"
        ]
        if let code = knownCodes.first(where: { diagnostic.contains($0) }) {
            return business(code: code)
        }
        return .remote(description)
    }
}
