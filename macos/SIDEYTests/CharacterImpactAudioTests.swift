import AppKit
import AVFoundation
import CryptoKit
import SpriteKit
import XCTest
@testable import SIDEYAppStore

@MainActor
final class CharacterImpactAudioTests: XCTestCase {
    func testAdmissionDropsExcessWithoutQueuingAndResets() {
        var gate = CharacterImpactAdmission()
        XCTAssertTrue(gate.accept(at: 0, activeVoices: 0, enabled: true))
        XCTAssertFalse(gate.accept(at: 0.079, activeVoices: 1, enabled: true))
        XCTAssertTrue(gate.accept(at: 0.080, activeVoices: 1, enabled: true))
        XCTAssertFalse(gate.accept(at: 1, activeVoices: 4, enabled: true))
        XCTAssertTrue(gate.accept(at: 1, activeVoices: 3, enabled: true))
        XCTAssertFalse(gate.accept(at: 2, activeVoices: 0, enabled: false))
        XCTAssertTrue(gate.accept(at: 2, activeVoices: 0, enabled: true))
        XCTAssertFalse(gate.accept(at: .nan, activeVoices: 0, enabled: true))
        gate.reset()
        XCTAssertTrue(gate.accept(at: 0, activeVoices: 0, enabled: true))
    }

    func testAllBundledSoundsMatchApprovedBytesAndDecode() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "approved-impact-sounds", withExtension: "json"))
        let sounds = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        XCTAssertEqual(Set(sounds.compactMap { $0["object_id"] as? String }), Set(CharacterImpactAudio.objectIDs))
        for sound in sounds {
            let id = try XCTUnwrap(sound["object_id"] as? String)
            let url = try XCTUnwrap(Bundle.main.url(forResource: "impact-\(id)", withExtension: "wav"))
            let data = try Data(contentsOf: url)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, sound["sha256"] as? String, id)
            let audio = try AVAudioFile(forReading: url)
            XCTAssertEqual(audio.fileFormat.sampleRate, 48_000)
            XCTAssertEqual(audio.fileFormat.channelCount, 1)
            XCTAssertGreaterThan(audio.length, 0)
            XCTAssertLessThanOrEqual(Double(audio.length) / 48_000, 0.8)
        }
        let audio = CharacterImpactAudio()
        XCTAssertTrue(audio.resourceErrors.isEmpty)
        audio.isEnabled = false
        XCTAssertFalse(audio.play(objectID: "throwable_bouncy_heart", at: 100))
        XCTAssertEqual(audio.activeVoiceCount, 0)
        XCTAssertEqual(audio.playCount, 0)
    }

    func testVersionEightDefaultsSoundOnAndOffSurvivesRoundTrip() throws {
        let json = #"{"schemaVersion":8,"quietModeEnabled":true,"nickname":"콩이"}"#
        var preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        XCTAssertEqual(preferences.schemaVersion, 9)
        XCTAssertTrue(preferences.characterSoundEffectsEnabled)
        XCTAssertTrue(preferences.quietModeEnabled)
        preferences.characterSoundEffectsEnabled = false
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(restored.characterSoundEffectsEnabled)
        XCTAssertEqual(restored.nickname, "콩이")
    }

    func testCollisionSoundsOnceWithResolvedObjectAndExplicitMuteIsRespected() {
        var now: TimeInterval = 100
        let actor = UUID(), target = UUID(), room = UUID()
        let scene = makeScene(actor: actor, target: target, room: room, now: { now })
        var played: [String] = []
        scene.onCharacterImpact = { id, _ in played.append(id) }
        func hit(_ id: String, audible: Bool = true) {
            let event = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
                targetUserID: target, sourceCharacterID: "pixel_hamster", throwableID: id)
            scene.playLocalPreviewThrow(event, playsSound: audible)
            scene.playLocalPreviewThrow(event, playsSound: audible)
            let before = played.count
            XCTAssertEqual(scene.activeProjectileCount, 1)
            now += 0.8; scene.update(now)
            XCTAssertEqual(played.count, before + (audible ? 1 : 0))
        }
        let originalIDs = Array(CharacterImpactAudio.objectIDs.prefix(8))
        for id in originalIDs { hit(id) }
        XCTAssertEqual(played, originalIDs)
        hit("patch_soft_ball", audible: false)
        hit("throwable_bouncy_heart")
        XCTAssertTrue(scene.stunState.isStunned(target, at: now))
        hit("throwable_bouncy_heart")
        XCTAssertEqual(played.count, 10)
        XCTAssertEqual(scene.renderedHitCount(for: target), 9)
    }

    func testEveryReceivedProductAndAssetIDResolvesSheetAndCollisionSound() throws {
        let products = CommerceCatalog.products.filter { $0.kind == .throwable }
        var cases: [(String?, String)] = [(nil, "patch_soft_ball"), ("unregistered-object", "patch_soft_ball")]
        for product in products {
            cases.append((product.catalogItemID, product.renderAssetID))
            cases.append((product.renderAssetID, product.renderAssetID))
        }
        for (receivedID, expectedID) in cases {
            var now: TimeInterval = 100
            let actor = UUID(), target = UUID(), room = UUID()
            var raw: [String: Any] = ["schema_version": 1, "room_id": room.uuidString,
                "event_id": UUID().uuidString, "actor_user_id": actor.uuidString,
                "target_user_id": target.uuidString, "source_character_id": "pixel_hamster"]
            if let receivedID { raw["throwable_id"] = receivedID }
            let payload = try JSONDecoder().decode(CharacterThrowPayload.self,
                from: JSONSerialization.data(withJSONObject: raw))
            let event = CharacterThrowEvent(id: payload.eventID, roomID: payload.roomID,
                actorUserID: payload.actorUserID, targetUserID: payload.targetUserID,
                sourceCharacterID: payload.sourceCharacterID, throwableID: payload.throwableID)
            let textures = PixelCharacterThrowTextureStore.shared.textures(
                for: event.sourceCharacterID, throwableID: event.throwableID)
            XCTAssertEqual(textures.objectID, expectedID, receivedID ?? "missing")
            XCTAssertEqual(PixelCharacterThrowCatalog.objectAssetURL(for: receivedID ?? ""),
                           PixelCharacterThrowCatalog.objectAssetURL(for: expectedID))
            XCTAssertTrue(CharacterImpactAudio.objectIDs.contains(expectedID))
            let scene = makeScene(actor: actor, target: target, room: room, now: { now })
            var sounds: [String] = []
            scene.onCharacterImpact = { id, _ in sounds.append(id) }
            scene.playLocalPreviewThrow(event)
            now += 0.8
            scene.update(now)
            XCTAssertEqual(sounds, [expectedID], receivedID ?? "missing")
        }
    }

    func testStoreAutomaticSequenceAndManualHitBothPlaySound() async throws {
        var now: TimeInterval = 100
        let scenario = StorePreviewScenario.make(product: .bouncyHeart)
        let scene = PixelWorldScene(size: StorePreviewStageLayout.size,
            renderingConfiguration: .storePreview(fixedTrackFractions: scenario.fixedTrackFractions), clock: { now })
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: scene.size))
        let coordinator = StorePreviewPlaybackCoordinator()
        defer { coordinator.stop(detachingScene: true) }
        var plays = 0
        scene.onCharacterImpact = { _, _ in plays += 1 }
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(scene.activeProjectileCount, 1)
        now += 0.8; scene.update(now)
        XCTAssertEqual(plays, 1)
        coordinator.stop(detachingScene: false)
        scene.playLocalPreviewThrow(try XCTUnwrap(scenario.throwSequence).event(at: 0))
        now += 0.8; scene.update(now)
        XCTAssertEqual(plays, 2)
    }

    func testSuspensionDiscardsInFlightHitAndStunWithoutReplay() {
        var now: TimeInterval = 100
        let actor = UUID(), target = UUID(), room = UUID()
        let scene = makeScene(actor: actor, target: target, room: room, now: { now })
        var plays = 0, stops = 0
        scene.onCharacterImpact = { _, _ in plays += 1 }
        scene.onStopCharacterSounds = { stops += 1 }
        for _ in 0..<10 { scene.stunState.recordHit(target, at: now) }
        let event = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
            targetUserID: target, sourceCharacterID: "pixel_hamster")
        scene.playLocalPreviewThrow(event)
        scene.setSuspended(true, reason: "lock")
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(scene.stunState.isStunned(target, at: now))
        XCTAssertEqual(scene.activeProjectileCount, 0)
        let whileLocked = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
            targetUserID: target, sourceCharacterID: "pixel_hamster")
        scene.playLocalPreviewThrow(whileLocked)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        scene.setSuspended(false, reason: "lock")
        scene.playLocalPreviewThrow(whileLocked)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        now += 20; scene.update(now)
        XCTAssertEqual(plays, 0)
        let next = CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
            targetUserID: target, sourceCharacterID: "pixel_hamster")
        scene.playLocalPreviewThrow(next)
        now += 0.8; scene.update(now)
        XCTAssertEqual(plays, 1)
        scene.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: room, actorUserID: actor,
            targetUserID: target, sourceCharacterID: "pixel_hamster"))
        now += 20; scene.update(now)
        XCTAssertEqual(plays, 1, "Overdue frames must not replay stale sounds")
    }

    #if DEBUG
    func testDebugRoomProvidesRealProjectileControlsAndAllChoices() throws {
        let room = CharacterFeedbackDebugRoom()
        defer { room.close() }
        let view = try XCTUnwrap(room.window?.contentView)
        let pickers = view.subviews.compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(pickers.first?.numberOfItems, 20)
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        try XCTUnwrap(buttons.first { $0.title == "친구 때리기 (Space)" }).performClick(nil)
        XCTAssertEqual(room.world.activeProjectileCount, 1)
        try XCTUnwrap(buttons.first { $0.title == "초기화" }).performClick(nil)
        XCTAssertEqual(room.world.activeProjectileCount, 0)
        let sprite = try XCTUnwrap(view.subviews.compactMap { $0 as? SKView }.first)
        sprite.isPaused = true
        let texture = try XCTUnwrap(sprite.texture(from: room.world))
        let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        try png.write(to: output)
    }
    #endif

    private func makeScene(actor: UUID, target: UUID, room: UUID, now: @escaping () -> TimeInterval) -> PixelWorldScene {
        let scene = PixelWorldScene(size: CGSize(width: 540, height: 240),
            renderingConfiguration: .storePreview(fixedTrackFractions: [actor: 0.25, target: 0.75]), clock: now)
        scene.apply(roomID: room, members: [
            PixelWorldMember(id: actor, nickname: "나", characterID: "pixel_hamster", presence: .online, isTyping: false, isCurrentUser: true),
            PixelWorldMember(id: target, nickname: "콩이", characterID: "pixel_cat", presence: .online, isTyping: false, isCurrentUser: false)
        ], bubbles: [], edge: .bottom, activityFrame: CGRect(x: 30, y: 30, width: 480, height: 180), installationSeed: 1)
        return scene
    }
}
