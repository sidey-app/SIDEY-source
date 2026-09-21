import AppKit
import SpriteKit
import SwiftUI

enum StorePreviewStageLayout {
    static let size = CGSize(width: 540, height: 280)
    static let platformHeight: CGFloat = 24
    static let platformPixelSize: CGFloat = 4
}

struct StorePreviewStage: View {
    let product: CommerceProduct
    var onCharacterImpact: (String, TimeInterval) -> Void = { _, _ in }
    var onStopCharacterSounds: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scenario: StorePreviewScenario {
        StorePreviewScenario.make(product: product)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.035))
            StorePreviewPlatform()
            StorePreviewSceneView(scenario: scenario, isPlaying: !reduceMotion, onCharacterImpact: onCharacterImpact, onStopCharacterSounds: onStopCharacterSounds)
                .accessibilityLabel(L10n.format("store.preview.accessibility", product.displayName))
                .accessibilityHint(reduceMotion
                                   ? L10n.text("store.preview.reduce_motion_hint")
                                   : previewAccessibilityHint)
        }
        .frame(width: StorePreviewStageLayout.size.width, height: StorePreviewStageLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var previewAccessibilityHint: String {
        if product.kind == .character {
            let objectName = CommerceCatalog.keepsake(for: product.id)?.displayName
                ?? L10n.text("store.preview.default_throwable")
            return L10n.format("store.preview.character_interaction_hint", objectName)
        }
        return L10n.text("store.preview.double_click_hint")
    }
}

private struct StorePreviewPlatform: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let pixel = StorePreviewStageLayout.platformPixelSize
            let base = colorScheme == .dark
                ? Color(red: 0.20, green: 0.21, blue: 0.23)
                : Color(red: 0.72, green: 0.73, blue: 0.75)
            let alternate = colorScheme == .dark
                ? Color(red: 0.25, green: 0.26, blue: 0.28)
                : Color(red: 0.80, green: 0.81, blue: 0.83)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            let columns = Int(ceil(size.width / pixel))
            let rows = Int(ceil(size.height / pixel))
            for row in 0..<rows where row.isMultiple(of: 2) {
                for column in 0..<columns where column.isMultiple(of: 2) == row.isMultiple(of: 4) {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * pixel,
                            y: CGFloat(row) * pixel,
                            width: pixel,
                            height: pixel
                        )),
                        with: .color(alternate)
                    )
                }
            }
        }
        .frame(height: StorePreviewStageLayout.platformHeight)
        .accessibilityHidden(true)
    }
}

private struct StorePreviewSceneView: NSViewRepresentable {
    let scenario: StorePreviewScenario
    let isPlaying: Bool
    let onCharacterImpact: (String, TimeInterval) -> Void
    let onStopCharacterSounds: () -> Void

    func makeCoordinator() -> StorePreviewPlaybackCoordinator {
        StorePreviewPlaybackCoordinator()
    }

    func makeNSView(context: Context) -> StorePreviewSKView {
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        PixelWorldRendererPolicy.apply(to: view)
        let scene = PixelWorldScene(
            size: StorePreviewStageLayout.size,
            renderingConfiguration: .storePreview(
                initialTrackFractions: scenario.initialTrackFractions,
                fixedTrackFractions: scenario.fixedTrackFractions
            )
        )
        scene.onCharacterImpact = onCharacterImpact
        scene.onStopCharacterSounds = onStopCharacterSounds
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        context.coordinator.configure(
            view: view,
            scene: scene,
            scenario: scenario,
            isPlaying: isPlaying
        )
        return view
    }

    func updateNSView(_ view: StorePreviewSKView, context: Context) {
        guard let scene = view.scene as? PixelWorldScene else { return }
        scene.onCharacterImpact = onCharacterImpact
        scene.onStopCharacterSounds = onStopCharacterSounds
        context.coordinator.configure(
            view: view,
            scene: scene,
            scenario: scenario,
            isPlaying: isPlaying
        )
    }

    static func dismantleNSView(
        _ view: StorePreviewSKView,
        coordinator: StorePreviewPlaybackCoordinator
    ) {
        coordinator.stop(detachingScene: true)
    }
}

@MainActor
enum StorePreviewSceneConfiguration {
    static func apply(
        _ scenario: StorePreviewScenario,
        bubblePresentation: StorePreviewBubblePresentation? = nil,
        to scene: PixelWorldScene
    ) {
        let presentation = bubblePresentation ?? scenario.bubbleSequence?.presentation(at: 0)
        let members: [PixelWorldMember]
        let bubbles: [ActiveBubble]
        if let sequence = scenario.bubbleSequence, let presentation {
            members = scenario.members.map { member in
                PixelWorldMember(
                    id: member.id,
                    nickname: member.nickname,
                    characterID: member.characterID,
                    presence: member.presence,
                    isTyping: presentation.isTyping && member.id == presentation.senderID,
                    isCurrentUser: member.isCurrentUser,
                    equippedBubbleStyleID: member.id == presentation.senderID
                        ? sequence.bubbleStyleID
                        : nil
                )
            }
            bubbles = presentation.bubble.map { [$0] } ?? []
        } else {
            members = scenario.members
            bubbles = scenario.bubbles
        }
        scene.apply(
            roomID: StorePreviewScenario.roomID,
            members: members,
            bubbles: bubbles,
            edge: .bottom,
            activityFrame: CGRect(
                x: 0,
                y: StorePreviewStageLayout.platformHeight,
                width: StorePreviewStageLayout.size.width,
                height: StorePreviewStageLayout.size.height - StorePreviewStageLayout.platformHeight
            ),
            installationSeed: 0x51_DE_59,
            onCharacterFramesChanged: { _ in }
        )
    }
}

@MainActor
final class StorePreviewPlaybackCoordinator {
    private weak var view: StorePreviewSKView?
    private weak var scene: PixelWorldScene?
    private var productID: String?
    private(set) var throwTask: Task<Void, Never>?
    private(set) var bubbleTask: Task<Void, Never>?

    var hasActiveThrowTask: Bool { throwTask != nil }
    var hasActiveBubbleTask: Bool { bubbleTask != nil }

    func configure(
        view: StorePreviewSKView,
        scene: PixelWorldScene,
        scenario: StorePreviewScenario,
        isPlaying: Bool
    ) {
        let changedScene = self.scene !== scene || productID != scenario.productID
        if changedScene {
            stop(detachingScene: false)
            self.view = view
            self.scene = scene
            productID = scenario.productID
            StorePreviewSceneConfiguration.apply(scenario, to: scene)
        }
        view.characterThrowInteraction = scenario.characterThrowInteraction
        view.isPaused = !isPlaying
        guard isPlaying else {
            cancelSequenceTasks()
            scene.cancelLocalPreviewPlayback()
            StorePreviewSceneConfiguration.apply(scenario, to: scene)
            return
        }

        configureThrowSequence(scenario.throwSequence, scene: scene)
        configureBubbleSequence(scenario.bubbleSequence, scenario: scenario, scene: scene)
    }

    private func configureThrowSequence(
        _ sequence: StorePreviewThrowSequence?,
        scene: PixelWorldScene
    ) {
        guard let sequence else {
            cancelThrowTask()
            return
        }
        guard throwTask == nil else { return }
        throwTask = Task { @MainActor [weak scene] in
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                var index = 0
                while !Task.isCancelled {
                    let deadline = startedAt + sequence.scheduledOffset(for: index)
                    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                    try await Task.sleep(for: .seconds(delay))
                    scene?.playLocalPreviewThrow(sequence.event(at: index))
                    index += 1
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func configureBubbleSequence(
        _ sequence: StorePreviewBubbleSequence?,
        scenario: StorePreviewScenario,
        scene: PixelWorldScene
    ) {
        guard let sequence else {
            cancelBubbleTask()
            return
        }
        guard bubbleTask == nil else { return }
        bubbleTask = Task { @MainActor [weak scene] in
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                var index = 1
                while !Task.isCancelled {
                    let deadline = startedAt + sequence.scheduledOffset(for: index)
                    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                    try await Task.sleep(for: .seconds(delay))
                    guard let scene else { return }
                    StorePreviewSceneConfiguration.apply(
                        scenario,
                        bubblePresentation: sequence.presentation(at: index),
                        to: scene
                    )
                    index += 1
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func stop(detachingScene: Bool) {
        cancelSequenceTasks()
        scene?.cancelLocalPreviewPlayback()
        if detachingScene {
            view?.presentScene(nil)
            view?.isPaused = true
            view?.characterThrowInteraction = nil
            view = nil
            scene = nil
            productID = nil
        } else {
            view?.isPaused = true
        }
    }

    private func cancelThrowTask() {
        throwTask?.cancel()
        throwTask = nil
    }

    private func cancelBubbleTask() {
        bubbleTask?.cancel()
        bubbleTask = nil
    }

    private func cancelSequenceTasks() {
        cancelThrowTask()
        cancelBubbleTask()
    }

    deinit {
        throwTask?.cancel()
        bubbleTask?.cancel()
    }
}

final class StorePreviewSKView: SKView {
    var characterThrowInteraction: StorePreviewCharacterThrowInteraction?

    @discardableResult
    func playCharacterThrow(at scenePoint: CGPoint) -> Bool {
        guard !isPaused,
              let scene = scene as? PixelWorldScene,
              let targetMemberID = scene.memberID(at: scenePoint),
              let event = characterThrowInteraction?.event(targetMemberID: targetMemberID)
        else { return false }
        scene.playLocalPreviewThrow(event)
        return true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard event.clickCount == 1, !isPaused, let scene = scene as? PixelWorldScene else { return }
        let point = scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        if let id = scene.memberID(at: point) { _ = scene.toggleTreeMovement(for: id) }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isPaused, let scene = scene as? PixelWorldScene else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let scenePoint = scene.convertPoint(fromView: viewPoint)
        if event.clickCount == 2 {
            _ = scene.playLocalPreviewPulse(at: scenePoint)
            return
        }
        if event.clickCount == 1, playCharacterThrow(at: scenePoint) {
            return
        }
        super.mouseDown(with: event)
    }
}
