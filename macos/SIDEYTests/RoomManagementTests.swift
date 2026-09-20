import XCTest
@testable import SIDEY

final class RoomManagementTests: XCTestCase {
    func testProductLimitsMatchRoomAndMessagePolicies() {
        XCTAssertEqual(ProductLimits.maximumRoomMembers, 12)
        XCTAssertEqual(ProductLimits.messageRetentionDays, 3)
        XCTAssertEqual(
            SideyBackendError.memberLimitReached.localizedDescription,
            "이 그룹은 이미 12명으로 가득 찼습니다."
        )
    }

    func testRoomNameValidatorNormalizesAndLimitsSingleLineNames() {
        XCTAssertEqual(RoomNameValidator.normalized("  친구 방  "), "친구 방")
        XCTAssertTrue(RoomNameValidator.isValid("친구 방"))
        XCTAssertTrue(RoomNameValidator.isValid(String(repeating: "가", count: 20)))
        XCTAssertFalse(RoomNameValidator.isValid("   "))
        XCTAssertFalse(RoomNameValidator.isValid(String(repeating: "가", count: 21)))
        XCTAssertFalse(RoomNameValidator.isValid("친구\n방"))
        XCTAssertFalse(RoomNameValidator.isValid("친구\t방"))
        XCTAssertEqual(
            RoomNameValidator.limitedDraft(String(repeating: "가", count: 21) + "\n"),
            String(repeating: "가", count: 20)
        )
        XCTAssertEqual(RoomNameValidator.limitedDraft("  친구 방  "), "  친구 방  ")
    }

    func testRoomManagementUsesOwnerUUIDAndNeverNickname() {
        let ownerID = UUID()
        let memberID = UUID()
        let owner = RoomMember(
            userID: ownerID,
            nickname: "같은 이름",
            characterID: "pixel_hamster",
            presence: .online
        )
        let member = RoomMember(
            userID: memberID,
            nickname: "같은 이름",
            characterID: "pixel_hamster",
            presence: .online
        )
        let room = Room(
            id: UUID(),
            name: "친구들",
            ownerID: ownerID,
            members: [owner, member],
            inviteCodeHint: "••••-••AA",
            inviteVersion: 1
        )

        XCTAssertTrue(RoomManagementPolicy.isOwner(owner, in: room))
        XCTAssertFalse(RoomManagementPolicy.isOwner(member, in: room))
        XCTAssertTrue(RoomManagementPolicy.canManage(room, currentUserID: ownerID))
        XCTAssertFalse(RoomManagementPolicy.canManage(room, currentUserID: memberID))
        XCTAssertFalse(RoomManagementPolicy.canRemove(owner, from: room, currentUserID: ownerID))
        XCTAssertTrue(RoomManagementPolicy.canRemove(member, from: room, currentUserID: ownerID))
        XCTAssertFalse(RoomManagementPolicy.canRemove(owner, from: room, currentUserID: memberID))
    }

    func testLeaveConfirmationExplainsMemberOwnerAndLastOwnerConsequences() {
        let ownerID = UUID()
        let memberID = UUID()
        let owner = RoomMember(
            userID: ownerID,
            nickname: "방장",
            characterID: "pixel_hamster",
            presence: .online
        )
        let member = RoomMember(
            userID: memberID,
            nickname: "멤버",
            characterID: "pixel_cat",
            presence: .online
        )
        let sharedRoom = Room(
            id: UUID(),
            name: "함께",
            ownerID: ownerID,
            members: [owner, member],
            inviteCodeHint: "••••-••AA"
        )
        let soloRoom = Room(
            id: UUID(),
            name: "혼자",
            ownerID: ownerID,
            members: [owner],
            inviteCodeHint: "••••-••BB"
        )

        XCTAssertEqual(RoomLeaveConfirmation.resolve(
            room: sharedRoom,
            currentUserID: memberID
        ), .member)
        XCTAssertEqual(RoomLeaveConfirmation.resolve(
            room: sharedRoom,
            currentUserID: ownerID
        ), .ownerWithRemainingMembers)
        XCTAssertEqual(RoomLeaveConfirmation.resolve(
            room: soloRoom,
            currentUserID: ownerID
        ), .lastOwner)
        XCTAssertTrue(RoomLeaveConfirmation.ownerWithRemainingMembers.message.contains("방장이 이전"))
        XCTAssertTrue(RoomLeaveConfirmation.lastOwner.message.contains("영구 삭제"))
    }

    func testBackendBusinessErrorsUseUserFacingKoreanMessages() {
        let cases: [(String, SideyBackendError)] = [
            ("owner_required", .ownerRequired),
            ("member_not_found", .memberNotFound),
            ("membership_required", .membershipRequired),
            ("owner_must_leave", .ownerCannotRemoveSelf),
            ("invalid_room_name", .invalidRoomName)
        ]

        for (code, expected) in cases {
            let remote = NSError(
                domain: "PostgREST",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "database error: \(code)"]
            )
            let normalized = SideyBackendError.normalized(remote)
            XCTAssertEqual(normalized, expected)
            XCTAssertFalse(normalized.localizedDescription.contains(code))
        }
    }

    @MainActor
    func testDeletedActiveRoomFallsBackToOldestRemainingRoom() {
        let userID = UUID()
        let deletedRoom = makeRoom(name: "삭제", ownerID: userID)
        let oldestRemaining = makeRoom(name: "오래된 방", ownerID: UUID())
        let newerRemaining = makeRoom(name: "새 방", ownerID: UUID())
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = deletedRoom.id
        let model = AppModel(preferences: preferences)

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_cat"),
                rooms: [deletedRoom, oldestRemaining, newerRemaining]
            ),
            currentUserID: userID
        )
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_cat"),
                rooms: [oldestRemaining, newerRemaining]
            ),
            currentUserID: userID
        )

        XCTAssertEqual(model.activeRoom?.id, oldestRemaining.id)
        XCTAssertEqual(model.preferences.activeRoomID, oldestRemaining.id)
        XCTAssertTrue(model.preferences.onboardingComplete)
    }

    @MainActor
    func testDeletingInactiveRoomKeepsActiveRoom() {
        let userID = UUID()
        let activeRoom = makeRoom(name: "활성", ownerID: userID)
        let deletedRoom = makeRoom(name: "삭제", ownerID: userID)
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = activeRoom.id
        let model = AppModel(preferences: preferences)

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_cat"),
                rooms: [activeRoom, deletedRoom]
            ),
            currentUserID: userID
        )
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_cat"),
                rooms: [activeRoom]
            ),
            currentUserID: userID
        )

        XCTAssertEqual(model.activeRoom?.id, activeRoom.id)
        XCTAssertFalse(model.rooms.contains(where: { $0.id == deletedRoom.id }))
    }

    @MainActor
    func testDeletingLastRoomReturnsToGroupOnboardingWithoutDroppingProfile() {
        let userID = UUID()
        let room = makeRoom(name: "마지막", ownerID: userID)
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = room.id
        let model = AppModel(preferences: preferences)
        let profile = Profile(id: userID, nickname: "나", characterID: "pixel_rabbit")

        model.apply(
            snapshot: BackendSnapshot(profile: profile, rooms: [room]),
            currentUserID: userID
        )
        model.apply(
            snapshot: BackendSnapshot(profile: profile, rooms: []),
            currentUserID: userID
        )

        XCTAssertNil(model.activeRoom)
        XCTAssertNil(model.preferences.activeRoomID)
        XCTAssertFalse(model.preferences.onboardingComplete)
        XCTAssertTrue(model.hasProfile)
        XCTAssertEqual(model.nickname, "나")
        XCTAssertEqual(model.selectedCharacterID, "pixel_rabbit")
    }

    private func makeRoom(name: String, ownerID: UUID) -> Room {
        Room(
            id: UUID(),
            name: name,
            ownerID: ownerID,
            members: [],
            inviteCodeHint: "••••-••AA",
            inviteVersion: 1
        )
    }
}
