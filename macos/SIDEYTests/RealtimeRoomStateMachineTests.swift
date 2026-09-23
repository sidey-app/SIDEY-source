import XCTest
@testable import SIDEY

final class RealtimeRoomStateMachineTests: XCTestCase {
    func testActiveRoomKeepsCommittedRoomUntilLatestRequestCommits() {
        let firstRoomID = UUID()
        let secondRoomID = UUID()
        var state = RealtimeActiveRoomState()

        let first = state.request(firstRoomID)
        XCTAssertTrue(state.commit(first))
        let second = state.request(secondRoomID)

        XCTAssertEqual(state.desiredActiveRoomID, secondRoomID)
        XCTAssertEqual(state.committedRealtimeActiveRoomID, firstRoomID)
        XCTAssertTrue(state.commit(second))
        XCTAssertEqual(state.committedRealtimeActiveRoomID, secondRoomID)
    }

    func testActiveRoomLatestRequestWinsAgainstOutOfOrderCompletion() {
        let firstRoomID = UUID()
        let secondRoomID = UUID()
        var state = RealtimeActiveRoomState()

        let first = state.request(firstRoomID)
        let second = state.request(secondRoomID)

        XCTAssertFalse(state.commit(first))
        XCTAssertTrue(state.commit(second))
        XCTAssertEqual(state.committedRealtimeActiveRoomID, secondRoomID)
    }

    func testLogoutAndMatchingKickOrDeleteInvalidatePendingOperations() {
        let roomID = UUID()
        var state = RealtimeActiveRoomState()
        let pending = state.request(roomID)

        XCTAssertTrue(state.invalidate(roomID: roomID))
        XCTAssertFalse(state.commit(pending))
        XCTAssertNil(state.desiredActiveRoomID)
        XCTAssertNil(state.committedRealtimeActiveRoomID)

        let replacement = state.request(UUID())
        state.invalidateAll()
        XCTAssertFalse(state.commit(replacement))
        XCTAssertNil(state.desiredActiveRoomID)
        XCTAssertNil(state.committedRealtimeActiveRoomID)
    }

    func testUnrelatedRoomInvalidationDoesNotCancelActiveRequest() {
        let roomID = UUID()
        var state = RealtimeActiveRoomState()
        let pending = state.request(roomID)

        XCTAssertFalse(state.invalidate(roomID: UUID()))
        XCTAssertTrue(state.commit(pending))
    }

    func testListenerPlanKeepsAtMostOneInboxAndOneLiveListener() {
        let firstIdentity = listenerIdentity(generation: 1)
        let secondIdentity = listenerIdentity(generation: 2)
        let firstRoomID = UUID()
        let secondRoomID = UUID()
        let current = RealtimeListenerResources(
            inbox: firstIdentity,
            live: RealtimeLiveListenerIdentity(owner: firstIdentity, roomID: firstRoomID)
        )

        let plan = RealtimeListenerResourcePlan.make(
            current: current,
            desiredIdentity: secondIdentity,
            desiredActiveRoomID: secondRoomID
        )

        XCTAssertEqual(plan.stopInbox, firstIdentity)
        XCTAssertEqual(plan.startInbox, secondIdentity)
        XCTAssertEqual(plan.stopLive?.roomID, firstRoomID)
        XCTAssertEqual(plan.startLive?.roomID, secondRoomID)
        XCTAssertEqual(plan.result.inbox, secondIdentity)
        XCTAssertEqual(plan.result.live?.owner, secondIdentity)
    }

    func testListenerPlanStopsEverythingOnLogoutAndNeverStartsLiveWithoutInboxUser() {
        let identity = listenerIdentity(generation: 1)
        let roomID = UUID()
        let current = RealtimeListenerResources(
            inbox: identity,
            live: RealtimeLiveListenerIdentity(owner: identity, roomID: roomID)
        )

        let logout = RealtimeListenerResourcePlan.make(
            current: current,
            desiredIdentity: nil,
            desiredActiveRoomID: roomID
        )

        XCTAssertEqual(logout.stopInbox, identity)
        XCTAssertEqual(logout.stopLive?.roomID, roomID)
        XCTAssertNil(logout.startInbox)
        XCTAssertNil(logout.startLive)
        XCTAssertEqual(logout.result, .empty)
    }

    func testListenerPlanRestartsBothListenersWhenOnlySessionOrGenerationChanges() {
        let accountID = UUID()
        let roomID = UUID()
        let first = RealtimeListenerIdentity(accountID: accountID, sessionID: UUID(), generation: 4)
        let nextSession = RealtimeListenerIdentity(accountID: accountID, sessionID: UUID(), generation: 5)
        let current = RealtimeListenerResources(
            inbox: first,
            live: RealtimeLiveListenerIdentity(owner: first, roomID: roomID)
        )

        let plan = RealtimeListenerResourcePlan.make(
            current: current,
            desiredIdentity: nextSession,
            desiredActiveRoomID: roomID
        )

        XCTAssertEqual(plan.stopInbox, first)
        XCTAssertEqual(plan.startInbox, nextSession)
        XCTAssertEqual(plan.stopLive?.owner, first)
        XCTAssertEqual(plan.startLive?.owner, nextSession)
        XCTAssertEqual(plan.startLive?.roomID, roomID)
    }

    func testEmptyPresenceFirstSyncCommitsMembersAsOffline() throws {
        let members = Set((0..<8).map { _ in UUID() })
        let identifier = presenceIdentifier(epoch: 1, revision: "snapshot-1", members: members)
        var state = PresenceGenerationState()
        let token = state.prepare(identifier)

        for memberID in members {
            _ = state.receiveFirstSync(for: memberID, state: nil, token: token)
        }
        XCTAssertEqual(
            state.markSelfTracked(token: token),
            .accepted(readyToCommit: true)
        )
        XCTAssertEqual(state.commit(token: token)?.activated, identifier)
        for userID in members {
            XCTAssertEqual(state.presenceState(for: userID), .offline)
        }
    }

    func testPresenceCommitRequiresFirstSyncAndSelfTrackInEitherOrder() {
        let memberID = UUID()
        let identifier = presenceIdentifier(epoch: 1, revision: "snapshot-1", members: [memberID])
        var state = PresenceGenerationState()
        let token = state.prepare(identifier)

        XCTAssertEqual(state.markSelfTracked(token: token), .accepted(readyToCommit: false))
        XCTAssertNil(state.commit(token: token))
        XCTAssertEqual(
            state.receiveFirstSync(for: memberID, state: .online, token: token),
            .accepted(readyToCommit: true)
        )
        XCTAssertNotNil(state.commit(token: token))
        XCTAssertEqual(state.presenceState(for: memberID), .online)
    }

    func testEpochRotationKeepsOldGenerationUntilNewOneCommitsAndRejectsStaleCallbacks() throws {
        let roomID = UUID()
        let members = Set((0..<12).map { _ in UUID() })
        var state = PresenceGenerationState()
        let oldIdentifier = presenceIdentifier(
            roomID: roomID,
            epoch: 7,
            revision: "snapshot-7",
            members: members
        )
        let oldToken = state.prepare(oldIdentifier)
        for memberID in members {
            _ = state.receiveFirstSync(for: memberID, state: .online, token: oldToken)
        }
        _ = state.markSelfTracked(token: oldToken)
        XCTAssertNotNil(state.commit(token: oldToken))

        let newIdentifier = presenceIdentifier(
            roomID: roomID,
            epoch: 8,
            revision: "snapshot-8",
            members: members
        )
        let newToken = state.prepare(newIdentifier)
        let orderedMembers = Array(members)
        XCTAssertEqual(state.committedIdentifier, oldIdentifier)

        XCTAssertEqual(
            state.receiveFirstSync(for: try XCTUnwrap(members.first), state: nil, token: oldToken),
            .stale
        )
        XCTAssertEqual(state.markSelfTracked(token: newToken), .accepted(readyToCommit: false))
        for memberID in orderedMembers.dropLast() {
            XCTAssertEqual(
                state.receiveFirstSync(for: memberID, state: nil, token: newToken),
                .accepted(readyToCommit: false)
            )
        }
        XCTAssertEqual(
            state.receiveFirstSync(for: try XCTUnwrap(orderedMembers.last), state: nil, token: newToken),
            .accepted(readyToCommit: true)
        )
        let transition = try XCTUnwrap(state.commit(token: newToken))

        XCTAssertEqual(transition.activated, newIdentifier)
        XCTAssertEqual(transition.retired, oldIdentifier)
        XCTAssertEqual(state.committedIdentifier, newIdentifier)
        XCTAssertEqual(
            state.apply(userID: try XCTUnwrap(members.first), state: .online, token: oldToken),
            .stale
        )
    }

    func testMemberRemovalPurgesPresenceAndRejectsLateCallback() {
        let keptMemberID = UUID()
        let removedMemberID = UUID()
        var state = PresenceGenerationState()
        let token = state.prepare(presenceIdentifier(
            epoch: 1,
            revision: "snapshot-1",
            members: [keptMemberID, removedMemberID]
        ))
        _ = state.receiveFirstSync(for: keptMemberID, state: .online, token: token)
        _ = state.receiveFirstSync(for: removedMemberID, state: .away, token: token)
        _ = state.markSelfTracked(token: token)
        _ = state.commit(token: token)

        state.purgeMember(removedMemberID)

        XCTAssertNil(state.presenceState(for: removedMemberID))
        XCTAssertEqual(state.presenceState(for: keptMemberID), .online)
        XCTAssertEqual(
            state.apply(userID: removedMemberID, state: .online, token: token),
            .stale
        )
    }

    func testCommittedGenerationIgnoresLatePreparationDeadline() {
        let memberID = UUID()
        var state = PresenceGenerationState()
        let token = state.prepare(presenceIdentifier(
            epoch: 1,
            revision: "snapshot-1",
            members: [memberID]
        ))
        _ = state.receiveFirstSync(for: memberID, state: .online, token: token)
        _ = state.markSelfTracked(token: token)
        _ = state.commit(token: token)

        XCTAssertFalse(state.deadlineExceeded(token: token))
        XCTAssertNotNil(state.committedIdentifier)
        XCTAssertEqual(state.presenceState(for: memberID), .online)
        XCTAssertEqual(
            state.apply(userID: memberID, state: .away, token: token),
            .accepted(readyToCommit: true)
        )
    }

    func testPreparingGenerationDeadlineAlsoPurgesPreviouslyCommittedOnlineState() {
        let roomID = UUID()
        let memberID = UUID()
        var state = PresenceGenerationState()
        let committedToken = state.prepare(presenceIdentifier(
            roomID: roomID,
            epoch: 1,
            revision: "snapshot-1",
            members: [memberID]
        ))
        _ = state.receiveFirstSync(for: memberID, state: .online, token: committedToken)
        _ = state.markSelfTracked(token: committedToken)
        _ = state.commit(token: committedToken)

        let preparingToken = state.prepare(presenceIdentifier(
            roomID: roomID,
            epoch: 2,
            revision: "snapshot-2",
            members: [memberID]
        ))

        XCTAssertTrue(state.deadlineExceeded(token: preparingToken))
        XCTAssertNil(state.preparingIdentifier)
        XCTAssertNil(state.committedIdentifier)
        XCTAssertNil(state.presenceState(for: memberID))
        XCTAssertEqual(
            state.apply(userID: memberID, state: .online, token: committedToken),
            .stale
        )
    }

    func testGrantBarrierRequiresRequestedRevisionAndAuthoritativeValidity() throws {
        var barrier = RealtimeGrantBarrier()
        barrier.request(revision: try revision(10), requiresEntitlement: true)

        barrier.acknowledge(revision: try revision(9), membershipValid: true, entitlementValid: true)
        XCTAssertFalse(barrier.isOpen)
        barrier.acknowledge(revision: try revision(10), membershipValid: true, entitlementValid: false)
        XCTAssertFalse(barrier.isOpen)
        barrier.acknowledge(revision: try revision(11), membershipValid: true, entitlementValid: true)
        XCTAssertTrue(barrier.isOpen)
    }

    func testGrantBarrierRevocationClosesImmediatelyAndFreshRequestCanReopen() throws {
        var barrier = RealtimeGrantBarrier()
        barrier.request(revision: try revision(1), requiresEntitlement: true)
        barrier.acknowledge(revision: try revision(1), membershipValid: true, entitlementValid: true)
        XCTAssertTrue(barrier.isOpen)

        barrier.revokeEntitlement()
        XCTAssertFalse(barrier.isOpen)
        barrier.acknowledge(revision: try revision(2), membershipValid: true, entitlementValid: true)
        XCTAssertFalse(barrier.isOpen)

        barrier.request(revision: try revision(3), requiresEntitlement: true)
        barrier.acknowledge(revision: try revision(3), membershipValid: true, entitlementValid: true)
        XCTAssertTrue(barrier.isOpen)
        barrier.revokeMembership()
        XCTAssertFalse(barrier.isOpen)
    }

    func testGrantBarrierCanIgnoreEntitlementForMembershipOnlyFeature() throws {
        var barrier = RealtimeGrantBarrier()
        barrier.request(revision: try revision(4), requiresEntitlement: false)
        barrier.acknowledge(revision: try revision(4), membershipValid: true, entitlementValid: false)

        XCTAssertTrue(barrier.isOpen)
    }

    private func presenceIdentifier(
        roomID: UUID = UUID(),
        epoch: Int,
        revision: String,
        members: Set<UUID>
    ) -> PresenceGenerationIdentifier {
        PresenceGenerationIdentifier(
            roomID: roomID,
            realtimeEpoch: epoch,
            snapshotRevision: PresenceSnapshotRevision(rawValue: revision),
            memberUserIDs: members
        )
    }

    private func listenerIdentity(generation: UInt64) -> RealtimeListenerIdentity {
        RealtimeListenerIdentity(
            accountID: UUID(),
            sessionID: UUID(),
            generation: generation
        )
    }

    private func revision(_ value: Int) throws -> RealtimeRevision {
        try XCTUnwrap(RealtimeRevision(rawValue: String(format: "%020d", value)))
    }
}
