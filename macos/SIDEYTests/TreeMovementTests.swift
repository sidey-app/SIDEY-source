import XCTest
@testable import SIDEYAppStore

@MainActor
final class TreeMovementTests: XCTestCase {
    func testDatabaseProfilesDecodeBothPreMigrationAndInt64Revisions() throws {
        let id = UUID()
        let old = Data("{\"id\":\"\(id)\",\"nickname\":\"나무\",\"character_id\":\"pixel_tree\"}".utf8)
        let decoded = try JSONDecoder().decode(DatabaseProfile.self, from: old).domain
        XCTAssertFalse(decoded.treeMovementPaused)
        XCTAssertNil(decoded.treeMovementRevision)
        let current = Data("{\"id\":\"\(id)\",\"nickname\":\"나무\",\"character_id\":\"pixel_tree\",\"tree_movement_paused\":true,\"tree_movement_revision\":4294967297}".utf8)
        let profile = try JSONDecoder().decode(DatabaseProfile.self, from: current).domain
        XCTAssertTrue(profile.treeMovementPaused)
        XCTAssertEqual(profile.treeMovementRevision, 4_294_967_297)
    }

    func testMissingServerCapabilityNeverStartsMigrationOrRemoteWrites() {
        let state = TreeMovementState(), id = UUID()
        state.accept(userID: id, paused: false, revision: nil)
        XCTAssertNil(state.begin(userID: id, paused: true, migrating: true))
        XCTAssertNil(state.begin(userID: id, paused: true))
        state.accept(userID: id, paused: false, revision: 0)
        XCTAssertNotNil(state.begin(userID: id, paused: true, migrating: true))
        state.accept(userID: id, paused: false, revision: 3)
        XCTAssertEqual(state.accept(userID: id, paused: true, revision: nil).revision, 3)
        XCTAssertEqual(state.confirmed[id]?.paused, false)
    }

    func testPendingRequestBlocksRepeatedClicksAndFailurePreservesConfirmedState() throws {
        let state = TreeMovementState(), id = UUID()
        state.accept(userID: id, paused: true, revision: 2)
        let request = try XCTUnwrap(state.begin(userID: id, paused: false))
        XCTAssertEqual(request.expectedRevision, 2)
        XCTAssertNil(state.begin(userID: id, paused: false))
        XCTAssertEqual(state.confirmed[id]?.paused, true)
        XCTAssertTrue(state.finish(request))
        XCTAssertEqual(state.confirmed[id]?.paused, true)
        XCTAssertNotNil(state.begin(userID: id, paused: false))
    }

    func testMigrationOnlyUsesUninitializedRevisionAndDoesNotLoopOnFailure() throws {
        let state = TreeMovementState(), id = UUID()
        state.accept(userID: id, paused: false, revision: 0)
        let request = try XCTUnwrap(state.begin(userID: id, paused: false, migrating: true))
        XCTAssertEqual(request.expectedRevision, 0)
        XCTAssertTrue(state.finish(request))
        XCTAssertNil(state.begin(userID: id, paused: true, migrating: true))
        state.reset()
        state.accept(userID: id, paused: true, revision: 1)
        XCTAssertNil(state.begin(userID: id, paused: false, migrating: true))
    }

    func testOlderRPCAndSnapshotsCannotUndoNewerProfileAcrossRooms() {
        let me = UUID(), friend = UUID(), first = UUID(), second = UUID()
        let model = AppModel(preferences: .defaults)
        func snapshot(_ revision: Int64, paused: Bool, rooms: [UUID]) -> BackendSnapshot {
            BackendSnapshot(profile: Profile(id: me, nickname: "나무", characterID: "pixel_tree",
                treeMovementPaused: paused, treeMovementRevision: revision), rooms: rooms.map { room in
                    Room(id: room, name: "그룹", ownerID: me, members: [
                        RoomMember(userID: me, nickname: "나무", characterID: "pixel_tree", presence: .online,
                            treeMovementPaused: paused, treeMovementRevision: revision),
                        RoomMember(userID: friend, nickname: "친구", characterID: "pixel_tree", presence: .online,
                            treeMovementPaused: paused, treeMovementRevision: revision)
                    ], inviteCodeHint: "AB••••")
                }, activeEntitlementKeys: ["character:pixel_tree"])
        }
        model.apply(snapshot: snapshot(4, paused: true, rooms: [first, second]), currentUserID: me)
        model.applyTreeMovement(profile: Profile(id: me, nickname: "나무", characterID: "pixel_tree",
            treeMovementPaused: false, treeMovementRevision: 3))
        model.apply(snapshot: snapshot(2, paused: false, rooms: [second]), currentUserID: me)
        XCTAssertTrue(model.rooms.flatMap(\.members).allSatisfy(\.treeMovementPaused))
        XCTAssertTrue(model.pixelWorldMembers.allSatisfy(\.treeMovementPaused))
        model.apply(snapshot: snapshot(5, paused: false, rooms: [second, first]), currentUserID: me)
        XCTAssertTrue(model.rooms.flatMap(\.members).allSatisfy { !$0.treeMovementPaused })
    }

    func testUninitializedMigrationKeepsLegacyPauseDuringPendingAndFailure() throws {
        let state = TreeMovementState(), me = UUID(), peer = UUID()
        func effective(_ id: UUID) -> Bool {
            state.effectivePaused(userID: id, currentUserID: me, legacyPaused: true)
        }
        XCTAssertTrue(effective(me))
        XCTAssertFalse(effective(peer))
        state.accept(userID: me, paused: false, revision: 0)
        state.accept(userID: peer, paused: false, revision: 0)
        let migration = try XCTUnwrap(state.begin(userID: me, paused: true, migrating: true))
        XCTAssertTrue(effective(me), "Receiving revision zero must not restart the local tree")
        XCTAssertFalse(effective(peer), "Local preferences never affect another user's tree")
        XCTAssertTrue(state.finish(migration)) // failed request: confirmed server data stays untouched
        XCTAssertTrue(effective(me))
        let retry = try XCTUnwrap(state.begin(userID: me, paused: !effective(me)))
        XCTAssertFalse(retry.paused, "Clicking the still-paused tree must request movement")
        XCTAssertEqual(retry.expectedRevision, 0)
        XCTAssertTrue(state.finish(retry))
        state.accept(userID: me, paused: false, revision: 1)
        XCTAssertFalse(effective(me), "Confirmed server state overrides the old local preference")
        state.accept(userID: peer, paused: true, revision: 2)
        XCTAssertTrue(effective(peer))
    }

    func testNewSessionRejectsPriorPendingCompletion() throws {
        let model = AppModel(preferences: .defaults), me = UUID(), next = UUID()
        model.currentUserID = me
        model.treeMovement.accept(userID: me, paused: false, revision: 0)
        let request = try XCTUnwrap(model.treeMovement.begin(userID: me, paused: true))
        model.currentUserID = next
        model.treeMovement.accept(userID: next, paused: false, revision: 2)
        let current = try XCTUnwrap(model.treeMovement.begin(userID: next, paused: true))
        XCTAssertFalse(model.treeMovement.finish(request))
        XCTAssertEqual(model.treeMovement.pending, current)
        XCTAssertNil(model.treeMovement.confirmed[me])
    }

    func testAuthenticationTransitionCancelsAndDrainsOldRequestWithoutClearingNewOne() async throws {
        let coordinator = AppCoordinator(
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .staging, arguments: [])
        let me = UUID()
        coordinator.model.currentUserID = me
        coordinator.model.treeMovement.accept(userID: me, paused: true, revision: 3)
        let previous = try XCTUnwrap(coordinator.model.treeMovement.begin(userID: me, paused: false))
        coordinator.treeMovementTask = Task { try? await Task.sleep(for: .seconds(60)) }
        let draining = try XCTUnwrap(coordinator.cancelTreeMovementRequests())
        XCTAssertTrue(draining.isCancelled)
        XCTAssertNil(coordinator.treeMovementTask)
        XCTAssertNil(coordinator.model.treeMovement.pending)
        XCTAssertEqual(coordinator.model.treeMovement.confirmed[me]?.paused, true)
        let next = try XCTUnwrap(coordinator.model.treeMovement.begin(userID: me, paused: false))
        await draining.value
        XCTAssertFalse(coordinator.model.treeMovement.finish(previous))
        XCTAssertEqual(coordinator.model.treeMovement.pending, next)
        coordinator.model.accountOperationInProgress = true
        coordinator.model.selectedCharacterID = "pixel_tree"
        coordinator.toggleTreeMovement()
        XCTAssertEqual(coordinator.model.treeMovement.pending, next)
        coordinator.cancelTreeMovementRequests()
    }

    #if APP_STORE
    func testAppStoreHostRetainsBundleIdentityWithSIDEYProductName() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.sidey.desktop.appstore")
        XCTAssertEqual(Bundle.main.bundleURL.lastPathComponent, "SIDEY.app")
        XCTAssertEqual(Bundle.main.executableURL?.lastPathComponent, "SIDEY")
    }
    #endif
}
