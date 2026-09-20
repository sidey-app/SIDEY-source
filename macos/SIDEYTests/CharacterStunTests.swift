import AppKit
import SpriteKit
import XCTest
@testable import SIDEYAppStore

@MainActor
final class CharacterStunTests: XCTestCase {
    func testInclusiveWindowAndIndependentTargets() {
        let state = CharacterStunState()
        let target = UUID(), other = UUID()
        for _ in 0..<9 { XCTAssertFalse(state.recordHit(target, at: 100)) }
        XCTAssertFalse(state.recordHit(other, at: 110))
        XCTAssertTrue(state.recordHit(target, at: 110))
        XCTAssertTrue(state.isStunned(target, at: 115.999))
        XCTAssertFalse(state.isStunned(target, at: 116))
        XCTAssertFalse(state.isStunned(other, at: 110))
        state.reset()
        for _ in 0..<9 { state.recordHit(target, at: 100) }
        XCTAssertFalse(state.recordHit(target, at: 110.001))
    }

    func testStunnedHitsNeitherExtendNorAccumulateAndRecoveryHasNoProtection() {
        var now: TimeInterval = 100
        let state = CharacterStunState(now: { now })
        let target = UUID()
        for _ in 0..<10 { state.recordHit(target, at: now) }
        for _ in 0..<100 { XCTAssertFalse(state.recordHit(target, at: 105.999)) }
        XCTAssertEqual(state.startedAt[target], 100)
        now = 106
        XCTAssertFalse(state.isStunned(target))
        for _ in 0..<9 { XCTAssertFalse(state.recordHit(target, at: now)) }
        XCTAssertTrue(state.recordHit(target, at: now))
        XCTAssertEqual(state.startedAt[target], 106)
    }

    func testExpiredHitsAndRemovedTargetsAreDiscarded() {
        let state = CharacterStunState()
        let id = UUID()
        for _ in 0..<9 { state.recordHit(id, at: 0) }
        state.advance(to: 11)
        XCTAssertFalse(state.recordHit(id, at: 11))
        state.remove(id)
        for _ in 0..<9 { XCTAssertFalse(state.recordHit(id, at: 11)) }
        XCTAssertTrue(state.recordHit(id, at: 11))
        state.reset()
        XCTAssertFalse(state.isStunned(id, at: 11))
    }

    func testActualCollisionsDeduplicateAndSuppressLocalActionsUntilRecovery() throws {
        var now: TimeInterval = 100
        let actor = UUID(), target = UUID(), room = UUID()
        let scene = makeScene(actor: actor, target: target, now: { now })
        apply(scene, actor: actor, target: target, room: room)
        var lastEvent: CharacterThrowEvent?
        for _ in 0..<10 {
            let event = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
                targetUserID: target, sourceCharacterID: "pixel_hamster")
            scene.playLocalPreviewThrow(event)
            scene.playLocalPreviewThrow(event)
            XCTAssertEqual(scene.activeProjectileCount, 1)
            now += 0.8
            scene.update(now)
            lastEvent = event
        }
        XCTAssertTrue(scene.stunState.isStunned(target, at: now))
        XCTAssertEqual(scene.renderedHitCount(for: target), 9)
        XCTAssertEqual(scene.renderedStunStarCount(for: target), 3)
        XCTAssertEqual(scene.renderedVisualState(for: target)?.motion, .offline)
        XCTAssertFalse(scene.playLocalPreviewPulse(memberID: target, at: now))
        let response = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: target,
            targetUserID: actor, sourceCharacterID: "pixel_hamster")
        scene.playLocalPreviewThrow(response)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        scene.playLocalPreviewThrow(try XCTUnwrap(lastEvent))
        XCTAssertEqual(scene.activeProjectileCount, 0)
        let started = try XCTUnwrap(scene.stunState.startedAt[target])
        scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
            targetUserID: target, sourceCharacterID: "pixel_hamster"))
        now += 0.8
        scene.update(now)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        XCTAssertEqual(scene.stunState.startedAt[target], started)
        XCTAssertEqual(scene.renderedHitCount(for: target), 9)
        now = started + 6
        scene.update(now)
        XCTAssertEqual(scene.renderedStunStarCount(for: target), 0)
        XCTAssertTrue(scene.playLocalPreviewPulse(memberID: target, at: now))
        scene.playLocalPreviewThrow(response)
        XCTAssertEqual(scene.activeProjectileCount, 1)
    }

    func testActualHitsStopRoamingTreeAndRecoveryPreservesServerPause() throws {
        for paused in [false, true] {
            var now: TimeInterval = 100
            let actor = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let target = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            let room = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            let scene = PixelWorldScene(size: CGSize(width: 540, height: 240),
                renderingConfiguration: .storePreview(initialTrackFractions: [target: 0.7],
                    fixedTrackFractions: [actor: 0.25]), clock: { now })
            apply(scene, actor: actor, target: target, room: room, character: "pixel_tree")
            scene.update(now)
            let initial = try XCTUnwrap(scene.agentStates.first { $0.id == target }).trackPosition
            var movedBeforeHits = false
            for _ in 0..<120 {
                now += 1.0 / 30
                scene.update(now)
                let position = try XCTUnwrap(scene.agentStates.first { $0.id == target }).trackPosition
                movedBeforeHits = movedBeforeHits || abs(position - initial) > 1
            }
            XCTAssertTrue(movedBeforeHits, "The target must actually roam before testing stun")
            apply(scene, actor: actor, target: target, room: room, character: "pixel_tree",
                  pausedTreeUserIDs: paused ? [target] : [])
            for hit in 1...10 {
                scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room,
                    actorUserID: actor, targetUserID: target, sourceCharacterID: "pixel_cat"))
                for _ in 0..<24 {
                    now += 1.0 / 30
                    scene.update(now)
                    if scene.stunState.isStunned(target, at: now) { break }
                }
                XCTAssertEqual(scene.activeProjectileCount, 0)
                XCTAssertEqual(scene.stunState.isStunned(target, at: now), hit == 10)
            }
            let started = try XCTUnwrap(scene.stunState.startedAt[target])
            let stopped = try XCTUnwrap(scene.agentStates.first { $0.id == target }).trackPosition
            for frame in 1..<180 {
                now = started + Double(frame) / 30
                scene.update(now)
                let agent = try XCTUnwrap(scene.agentStates.first { $0.id == target })
                XCTAssertEqual(agent.trackPosition, stopped, accuracy: 0.001)
                XCTAssertEqual(agent.velocity, 0)
            }
            now = started + 6
            scene.update(now)
            XCTAssertFalse(scene.stunState.isStunned(target, at: now))
            XCTAssertEqual(scene.renderedStunStarCount(for: target), 0)
            XCTAssertEqual(scene.isTreeMovementPaused(for: target), paused)
            var movedAfterRecovery = false
            for frame in 1...120 {
                now = started + 6 + Double(frame) / 30
                scene.update(now)
                let position = try XCTUnwrap(scene.agentStates.first { $0.id == target }).trackPosition
                movedAfterRecovery = movedAfterRecovery || abs(position - stopped) > 1
                if paused { XCTAssertEqual(position, stopped, accuracy: 0.001) }
            }
            XCTAssertEqual(movedAfterRecovery, !paused)
        }
    }

    func testStunPreservesReleasedProjectileAndChatWhileBlockingNewThrows() throws {
        var now: TimeInterval = 100
        let actor = UUID(), target = UUID(), distantFriend = UUID(), room = UUID()
        let scene = PixelWorldScene(size: CGSize(width: 1_000, height: 240),
            renderingConfiguration: .storePreview(fixedTrackFractions: [
                actor: 0.2, target: 0.3, distantFriend: 0.9]), clock: { now })
        let members = [
            PixelWorldMember(id: actor, nickname: "친구", characterID: "pixel_cat",
                presence: .online, isTyping: false, isCurrentUser: false),
            PixelWorldMember(id: target, nickname: "나", characterID: "pixel_tree",
                presence: .online, isTyping: true, isCurrentUser: true),
            PixelWorldMember(id: distantFriend, nickname: "멀리 있는 친구", characterID: "pixel_hamster",
                presence: .online, isTyping: false, isCurrentUser: false)
        ]
        scene.apply(roomID: room, members: members, bubbles: [ActiveBubble(senderID: target, messageID: UUID(), body: "계속 채팅 중",
            expiresAt: Date().addingTimeInterval(3_600))], edge: .bottom,
            activityFrame: CGRect(x: 0, y: 0, width: 1_000, height: 240), installationSeed: 1)
        scene.update(now)
        for _ in 0..<9 {
            scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room,
                actorUserID: actor, targetUserID: target, sourceCharacterID: "pixel_cat"))
            now += 0.8
            scene.update(now)
        }
        XCTAssertEqual(scene.stunState.recentHitCount(target, at: now), 9)
        scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room,
            actorUserID: actor, targetUserID: target, sourceCharacterID: "pixel_cat"))
        now += 0.3
        scene.update(now)
        scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room,
            actorUserID: target, targetUserID: distantFriend, sourceCharacterID: "pixel_tree"))
        now += 0.4
        scene.update(now)
        XCTAssertTrue(scene.previewRenderEvents.contains(.projectileReleased(target)))
        XCTAssertTrue(scene.stunState.isStunned(target, at: now))
        XCTAssertEqual(scene.activeProjectileCount, 1)
        XCTAssertEqual(scene.renderedHitCount(for: distantFriend), 0)
        XCTAssertTrue(scene.renderedBubbleBodies(for: target).contains("계속 채팅 중"))
        XCTAssertFalse(scene.renderedBubbleIsTyping(for: target), "A visible message takes priority over typing")
        scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room,
            actorUserID: target, targetUserID: actor, sourceCharacterID: "pixel_tree"))
        XCTAssertEqual(scene.activeProjectileCount, 1, "A new throw must not join the released projectile")
        now += 1
        scene.update(now)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        XCTAssertEqual(scene.renderedHitCount(for: distantFriend), 1)
        XCTAssertTrue(scene.previewRenderEvents.contains(.impact(distantFriend)))
        XCTAssertTrue(scene.stunState.isStunned(target, at: now))
        XCTAssertTrue(scene.renderedBubbleBodies(for: target).contains("계속 채팅 중"))
        scene.apply(roomID: room, members: members, bubbles: [], edge: .bottom,
            activityFrame: CGRect(x: 0, y: 0, width: 1_000, height: 240), installationSeed: 1)
        XCTAssertTrue(scene.stunState.isStunned(target, at: now))
        XCTAssertTrue(scene.renderedBubbleIsTyping(for: target), "Typing returns when the message is removed during stun")
    }

    func testAllCharactersEdgesAndPresenceKeepStylingAndTypingWhileStunned() throws {
        for definition in PixelCharacterCatalog.all {
            for edge in OverlayEdge.allCases {
                for presence in [PresenceState.online, .typing, .away, .offline, .reconnecting] {
                    let actor = UUID(), target = UUID(), room = UUID()
                    let scene = makeScene(actor: actor, target: target, now: { 100 })
                    apply(scene, actor: actor, target: target, room: room,
                          character: definition.id, presence: presence, edge: edge)
                    for _ in 0..<10 { scene.stunState.recordHit(target, at: 100) }
                    scene.update(100)
                    let visual = try XCTUnwrap(scene.renderedVisualState(for: target))
                    XCTAssertEqual(visual.motion, .offline)
                    XCTAssertFalse(visual.showsDozeLabel)
                    XCTAssertEqual(visual.alpha, presence == .offline ? 0.75 : 1)
                    XCTAssertEqual(visual.colorBlendFactor, presence == .offline ? 0.58 : 0, accuracy: 0.0001)
                    XCTAssertTrue(scene.renderedBubbleIsTyping(for: target))
                    XCTAssertEqual(scene.renderedStunStarCount(for: target), 3)
                    scene.update(106)
                    XCTAssertEqual(scene.renderedStunStarCount(for: target), 0)
                    XCTAssertEqual(scene.renderedVisualState(for: target)?.showsDozeLabel, presence == .away)
                }
            }
        }
    }

    func testAppearanceChangePreservesStunButRoomRemovalAndReconnectClearIt() {
        let actor = UUID(), target = UUID(), room = UUID()
        let state = CharacterStunState(now: { 100 })
        let scene = makeScene(actor: actor, target: target, now: { 100 })
        scene.useStunState(state, realtimeAvailable: true)
        apply(scene, actor: actor, target: target, room: room)
        for _ in 0..<10 { state.recordHit(target, at: 100) }
        scene.update(100)
        apply(scene, actor: actor, target: target, room: room, character: "pixel_cat")
        XCTAssertTrue(state.isStunned(target))
        scene.useStunState(state, realtimeAvailable: false)
        XCTAssertFalse(state.isStunned(target))
        for _ in 0..<10 { state.recordHit(target, at: 100) }
        let nextRoom = UUID()
        apply(scene, actor: actor, target: target, room: nextRoom)
        XCTAssertFalse(state.isStunned(target))
        for _ in 0..<10 { state.recordHit(target, at: 100) }
        scene.apply(roomID: nextRoom, members: [], bubbles: [], edge: .bottom, installationSeed: 1)
        XCTAssertFalse(state.isStunned(target))
    }

    func testLocalCoordinatorBlocksBeforeCooldownAndLeavesChatDraftIntact() {
        let coordinator = AppCoordinator(
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .staging, arguments: [])
        let user = UUID(), friend = UUID(), room = UUID()
        coordinator.model.apply(snapshot: BackendSnapshot(
            profile: Profile(id: user, nickname: "나", characterID: "pixel_hamster"),
            rooms: [Room(id: room, name: "검증", ownerID: user, members: [
                RoomMember(userID: user, nickname: "나", characterID: "pixel_hamster", presence: .online),
                RoomMember(userID: friend, nickname: "친구", characterID: "pixel_cat", presence: .online)
            ], inviteCodeHint: "AB••••", inviteVersion: 1)]), currentUserID: user)
        coordinator.model.preferences.activeRoomID = room
        coordinator.model.connectionState = .online
        coordinator.model.draft = "기절해도 채팅 중"
        let now = ProcessInfo.processInfo.systemUptime
        for _ in 0..<10 { coordinator.model.characterStunState.recordHit(user, at: now) }
        coordinator.characterDoubleClicked()
        coordinator.characterThrowRequested(targetUserID: friend)
        XCTAssertTrue(coordinator.roomSession.pulseCooldown.accept(roomID: room, userID: user, uptime: now))
        XCTAssertTrue(coordinator.roomSession.throwCooldown.accept(actorUserID: user, uptime: now))
        XCTAssertEqual(coordinator.model.draft, "기절해도 채팅 중")
        coordinator.model.setActiveRoomRealtimeConnected(true)
        XCTAssertFalse(coordinator.model.characterStunState.isStunned(user))
    }

    func testReducedMotionFreezesOrbitAndNativeSceneRendersApprovedAssets() throws {
        let effect = PixelCharacterStunEffect()
        effect.update(elapsed: 0, reduceMotion: true)
        let positions = effect.children.map(\.position)
        effect.update(elapsed: 0.6, reduceMotion: true)
        XCTAssertEqual(effect.children.map(\.position), positions)
        effect.update(elapsed: 0.6, reduceMotion: false)
        XCTAssertNotEqual(effect.children.map(\.position), positions)
        let actor = UUID(), target = UUID(), room = UUID()
        let scene = makeScene(actor: actor, target: target, now: { 100 })
        apply(scene, actor: actor, target: target, room: room)
        for _ in 0..<10 { scene.stunState.recordHit(target, at: 100) }
        scene.update(100)
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        PixelWorldRendererPolicy.apply(to: view)
        view.presentScene(scene)
        view.isPaused = true
        let texture = try XCTUnwrap(view.texture(from: scene))
        let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 500)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "native-stun-scene"; attachment.lifetime = .keepAlways
        add(attachment)
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("sidey-stun-native.png"))
        view.presentScene(nil)
    }

    private func makeScene(actor: UUID, target: UUID, now: @escaping () -> TimeInterval) -> PixelWorldScene {
        PixelWorldScene(size: CGSize(width: 540, height: 240),
            renderingConfiguration: .storePreview(fixedTrackFractions: [actor: 0.25, target: 0.75]), clock: now)
    }

    private func apply(_ scene: PixelWorldScene, actor: UUID, target: UUID, room: UUID,
                       character: String = "pixel_hamster", presence: PresenceState = .online,
                       edge: OverlayEdge = .bottom, pausedTreeUserIDs: Set<UUID>? = nil) {
        scene.apply(roomID: room, members: [
            PixelWorldMember(id: actor, nickname: "친구", characterID: "pixel_cat", presence: .online, isTyping: false, isCurrentUser: false),
            PixelWorldMember(id: target, nickname: "기절", characterID: character, presence: presence, isTyping: true, isCurrentUser: true)
        ], bubbles: [], edge: edge, activityFrame: CGRect(x: 30, y: 30, width: 480, height: 180),
           installationSeed: 1, pausedTreeUserIDs: pausedTreeUserIDs)
    }
}
