import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import SIDEYAppStore

@MainActor
final class StorePreviewTests: XCTestCase {
    func testCharacterScenariosThrowTheirKeepsakeWhenTheFriendIsClicked() throws {
        for product in CommerceCatalog.characterProducts {
            let scenario = StorePreviewScenario.make(product: product)
            let characterID = try XCTUnwrap(product.characterID)
            XCTAssertEqual(scenario.members.map(\.nickname), ["모카", "두부"])
            XCTAssertEqual(scenario.members.map(\.characterID), [characterID, "pixel_cat"])
            XCTAssertTrue(scenario.members.allSatisfy { $0.presence == .online })
            XCTAssertTrue(scenario.bubbles.isEmpty)
            XCTAssertTrue(scenario.fixedTrackFractions.isEmpty)
            XCTAssertEqual(scenario.initialTrackFractions[StorePreviewScenario.mokaID], 0.22)
            XCTAssertEqual(scenario.initialTrackFractions[StorePreviewScenario.dubuID], 0.78)
            XCTAssertNil(scenario.bubbleSequence)
            XCTAssertNil(scenario.throwSequence)

            let interaction = try XCTUnwrap(scenario.characterThrowInteraction)
            XCTAssertNil(interaction.event(targetMemberID: StorePreviewScenario.mokaID))
            let event = try XCTUnwrap(
                interaction.event(targetMemberID: StorePreviewScenario.dubuID)
            )
            XCTAssertEqual(event.actorUserID, StorePreviewScenario.mokaID)
            XCTAssertEqual(event.targetUserID, StorePreviewScenario.dubuID)
            XCTAssertEqual(event.sourceCharacterID, characterID)
            XCTAssertEqual(
                event.throwableID,
                CommerceCatalog.keepsake(for: product.id)?.renderAssetID
            )

            let scene = makeScene(for: product)
            let view = StorePreviewSKView(
                frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size)
            )
            view.presentScene(scene)
            let coordinator = StorePreviewPlaybackCoordinator()
            coordinator.configure(
                view: view,
                scene: scene,
                scenario: scenario,
                isPlaying: true
            )
            let targetPosition = try XCTUnwrap(
                scene.agentStates.first { $0.id == StorePreviewScenario.dubuID }?.trackPosition
            )
            XCTAssertTrue(
                view.playCharacterThrow(at: scene.trackGeometry.point(for: targetPosition))
            )
            XCTAssertEqual(scene.renderedThrowCount(for: StorePreviewScenario.mokaID), 1)
            XCTAssertEqual(scene.activeProjectileCount, 1)
            coordinator.stop(detachingScene: true)
        }
    }

    func testBubbleScenariosAlternateTwoMembersWithTheActualThemeAndDecoration() throws {
        for product in CommerceCatalog.cosmeticProducts where product.kind == .bubble {
            let scenario = StorePreviewScenario.make(product: product)
            XCTAssertEqual(scenario.members.map(\.nickname), ["모카", "두부"])
            XCTAssertEqual(scenario.members.map(\.characterID), ["pixel_hamster", "pixel_cat"])
            XCTAssertTrue(scenario.members.allSatisfy { $0.presence == .online })

            let sequence = try XCTUnwrap(scenario.bubbleSequence)
            XCTAssertEqual(sequence.scheduledOffset(for: 0), 0)
            XCTAssertEqual(sequence.scheduledOffset(for: 1), 1)
            XCTAssertEqual(sequence.scheduledOffset(for: 2), 3)
            XCTAssertEqual(sequence.scheduledOffset(for: 3), 4)
            XCTAssertEqual(sequence.scheduledOffset(for: 4), 6)
            let presentations = (0..<5).map { sequence.presentation(at: $0) }
            XCTAssertEqual(presentations.map(\.senderID), [
                StorePreviewScenario.mokaID,
                StorePreviewScenario.mokaID,
                StorePreviewScenario.dubuID,
                StorePreviewScenario.dubuID,
                StorePreviewScenario.mokaID
            ])
            XCTAssertEqual(presentations.map(\.isTyping), [true, false, true, false, true])
            XCTAssertEqual(presentations.map { $0.bubble?.body }, [
                nil,
                "저메추좀 해줘",
                nil,
                "곱도리탕 어때?",
                nil
            ])
            XCTAssertTrue(
                presentations.compactMap(\.bubble).allSatisfy {
                    $0.bubbleStyleID == product.catalogItemID
                }
            )
            XCTAssertEqual(PixelBubbleTheme.resolve(product.catalogItemID).id, product.catalogItemID)
            XCTAssertNil(scenario.throwSequence)
            XCTAssertNil(scenario.characterThrowInteraction)

            let scene = makeScene(for: product)
            XCTAssertTrue(scene.renderedBubbleIsTyping(for: StorePreviewScenario.mokaID))
            XCTAssertEqual(
                scene.renderedBubbleDecorationCount(for: StorePreviewScenario.mokaID),
                1
            )
            StorePreviewSceneConfiguration.apply(
                scenario,
                bubblePresentation: sequence.presentation(at: 2),
                to: scene
            )
            XCTAssertTrue(scene.renderedBubbleIsTyping(for: StorePreviewScenario.dubuID))
            XCTAssertEqual(
                scene.renderedBubbleDecorationCount(for: StorePreviewScenario.mokaID),
                0
            )
            XCTAssertEqual(
                scene.renderedBubbleDecorationCount(for: StorePreviewScenario.dubuID),
                1
            )
        }
    }

    func testThrowableScenariosFixMembersAndAlternateEverySecond() throws {
        for product in CommerceCatalog.cosmeticProducts where product.kind == .throwable {
            let scenario = StorePreviewScenario.make(product: product)
            XCTAssertEqual(scenario.members.map(\.nickname), ["모카", "두부"])
            XCTAssertEqual(scenario.members.map(\.characterID), ["pixel_hamster", "pixel_cat"])
            XCTAssertTrue(scenario.members.allSatisfy { $0.presence == .online })
            XCTAssertEqual(scenario.fixedTrackFractions[StorePreviewScenario.mokaID], 0.22)
            XCTAssertEqual(scenario.fixedTrackFractions[StorePreviewScenario.dubuID], 0.78)
            XCTAssertNil(scenario.bubbleSequence)
            XCTAssertNil(scenario.characterThrowInteraction)

            let sequence = try XCTUnwrap(scenario.throwSequence)
            XCTAssertEqual(sequence.scheduledOffset(for: 0), 0.35, accuracy: 0.001)
            XCTAssertEqual(sequence.scheduledOffset(for: 1), 1.35, accuracy: 0.001)
            XCTAssertEqual(sequence.scheduledOffset(for: 2), 2.35, accuracy: 0.001)
            let events = (0..<3).map { sequence.event(at: $0) }
            XCTAssertEqual(events.map(\.actorUserID), [
                StorePreviewScenario.mokaID,
                StorePreviewScenario.dubuID,
                StorePreviewScenario.mokaID
            ])
            XCTAssertEqual(events.map(\.targetUserID), [
                StorePreviewScenario.dubuID,
                StorePreviewScenario.mokaID,
                StorePreviewScenario.dubuID
            ])
            XCTAssertTrue(events.allSatisfy { $0.throwableID == product.catalogItemID })
        }
    }

    func testPreviewPulseUsesThreeTimesScaleAndOneSecondCooldownWhileLiveStaysSeven() {
        let member = StorePreviewScenario.make(product: .guineaPig).members[0]
        let live = PixelWorldScene(size: StorePreviewStageLayout.size)
        live.apply(
            roomID: StorePreviewScenario.roomID,
            members: [member],
            bubbles: [],
            edge: .bottom,
            installationSeed: 1,
            characterPulse: CharacterPulseEvent(
                id: UUID(), roomID: StorePreviewScenario.roomID, userID: member.id
            )
        )
        XCTAssertEqual(live.renderedPulsePeakScale(for: member.id), 7)
        XCTAssertFalse(live.playLocalPreviewPulse(memberID: member.id, at: 10))

        let preview = makeScene(for: .guineaPig)
        XCTAssertTrue(preview.playLocalPreviewPulse(memberID: member.id, at: 10))
        XCTAssertEqual(preview.renderedPulsePeakScale(for: member.id), 3)
        XCTAssertFalse(preview.playLocalPreviewPulse(memberID: member.id, at: 10.99))
        XCTAssertTrue(preview.playLocalPreviewPulse(memberID: member.id, at: 11))
        XCTAssertEqual(preview.renderedPulseCount(for: member.id), 2)
        XCTAssertEqual(PixelCharacterPulseStyle.peakScale, 7)
    }

    func testCharacterAndBubblePreviewWalkWhileThrowableMembersStayFixed() throws {
        for product in [CommerceProduct.guineaPig, .bunnyPinkBubble] {
            let scene = makeScene(for: product)
            let initial = try XCTUnwrap(scene.agentStates.first?.trackPosition)
            advance(scene, seconds: 4)
            XCTAssertNotEqual(scene.agentStates.first?.trackPosition, initial, product.id)
        }

        let throwable = StorePreviewScenario.make(product: .bouncyHeart)
        let scene = makeScene(for: .bouncyHeart)
        advance(scene, seconds: 4)
        let positions = Dictionary(uniqueKeysWithValues: scene.agentStates.map { ($0.id, $0.trackPosition) })
        XCTAssertEqual(
            try XCTUnwrap(positions[StorePreviewScenario.mokaID]),
            StorePreviewStageLayout.size.width * 0.22,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(positions[StorePreviewScenario.dubuID]),
            StorePreviewStageLayout.size.width * 0.78,
            accuracy: 0.001
        )
        XCTAssertEqual(Set(positions.keys), Set(throwable.members.map(\.id)))
    }

    func testNormalAndCannonPreviewReuseThrowProjectileImpactHitOrder() throws {
        for product in [CommerceProduct.bouncyHeart, .toyCannon] {
            let scenario = StorePreviewScenario.make(product: product)
            let sequence = try XCTUnwrap(scenario.throwSequence)
            let scene = makeScene(for: product)
            let event = sequence.event(at: 0)
            scene.playLocalPreviewThrow(event)
            XCTAssertEqual(scene.activeProjectileCount, 1)
            scene.update(ProcessInfo.processInfo.systemUptime + 2)
            XCTAssertEqual(scene.activeProjectileCount, 0)
            XCTAssertEqual(scene.previewRenderEvents, [
                .throwStarted(event.actorUserID),
                .projectileReleased(event.actorUserID),
                .impact(event.targetUserID),
                .hit(event.targetUserID)
            ], product.id)
            XCTAssertEqual(scene.renderedThrowCount(for: event.actorUserID), 1)
            XCTAssertEqual(scene.renderedHitCount(for: event.targetUserID), 1)
        }
    }

    func testPlaybackCoordinatorCancelsThrowTaskAndDetachesScene() throws {
        let scenario = StorePreviewScenario.make(product: .bouncyHeart)
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        let scene = makeScene(for: .bouncyHeart)
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()

        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertTrue(coordinator.hasActiveThrowTask)
        XCTAssertFalse(coordinator.hasActiveBubbleTask)
        scene.playLocalPreviewThrow(try XCTUnwrap(scenario.throwSequence).event(at: 0))
        XCTAssertEqual(scene.activeProjectileCount, 1)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: false)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertTrue(coordinator.hasActiveThrowTask)
        coordinator.stop(detachingScene: true)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertFalse(coordinator.hasActiveBubbleTask)
        XCTAssertNil(view.scene)
        XCTAssertTrue(view.isPaused)
    }

    func testDujjonkuImpactRetainsTheStretchPoseAndClearsOnPreviewClose() throws {
        for product in [CommerceProduct.dujjonku, .wakkuball, .bouncyHeart] {
            let scenario = StorePreviewScenario.make(product: product)
            let scene = makeScene(for: product)
            scene.playLocalPreviewThrow(try XCTUnwrap(scenario.throwSequence).event(at: 0))
            scene.update(ProcessInfo.processInfo.systemUptime + 2)
            let impact = try XCTUnwrap(scene.childNode(withName: "throwable-impact"))
            let animation = try XCTUnwrap(impact.action(forKey: "impact-frames"))
            if product.id == CommerceProduct.dujjonku.id {
                XCTAssertEqual(animation.duration, 0.58, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(
                    PixelCharacterThrowStyle.impactFrameDurations(for: product.id)[2],
                    8.0 / 30.0
                )
            } else {
                XCTAssertEqual(animation.duration, 0.24, accuracy: 0.001)
            }
            scene.cancelLocalPreviewPlayback()
            XCTAssertNil(scene.childNode(withName: "throwable-impact"))
        }
    }

    func testBubblePlaybackCoordinatorOwnsAndCancelsAlternationTask() {
        let scenario = StorePreviewScenario.make(product: .bunnyPinkBubble)
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        let scene = makeScene(for: .bunnyPinkBubble)
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()

        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertTrue(coordinator.hasActiveBubbleTask)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: false)
        XCTAssertFalse(coordinator.hasActiveBubbleTask)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertTrue(view.isPaused)
        XCTAssertTrue(scene.renderedBubbleIsTyping(for: StorePreviewScenario.mokaID))
        coordinator.stop(detachingScene: true)
        XCTAssertNil(view.scene)
    }

    func testBubbleDecorationOverlapsTopLeftCornerWithoutChangingBodySize() throws {
        let layout = PixelBubbleLayout.make(
            text: "저메추좀 해줘",
            isTyping: false,
            tangentPosition: 270,
            tangentLength: 540,
            edge: .bottom
        )
        let node = PixelBubbleNode(
            body: "저메추좀 해줘",
            isTyping: false,
            layout: layout,
            bubbleStyleID: CommerceProduct.bunnyPinkBubble.catalogItemID
        )
        let decorationFrame = try XCTUnwrap(node.decorationFrame)
        let bubbleFrame = CGRect(
            x: -layout.size.width / 2,
            y: -layout.size.height / 2,
            width: layout.size.width,
            height: layout.size.height
        )

        XCTAssertEqual(
            decorationFrame.midX,
            bubbleFrame.minX + PixelBubbleStyle.decorationCornerInset,
            accuracy: 0.001
        )
        XCTAssertEqual(decorationFrame.midY, bubbleFrame.maxY, accuracy: 0.001)
        XCTAssertLessThan(decorationFrame.minX, bubbleFrame.minX)
        XCTAssertGreaterThan(decorationFrame.maxY, bubbleFrame.maxY)

        let edgeLayout = PixelBubbleLayout.make(
            text: "저메추좀 해줘",
            isTyping: false,
            tangentPosition: 0,
            tangentLength: 540,
            edge: .bottom,
            leadingDecorationOverflow: PixelBubbleStyle.decorationLeadingOverflow
        )
        XCTAssertEqual(edgeLayout.size, layout.size)
        XCTAssertGreaterThanOrEqual(
            edgeLayout.bodyFrame.minX - PixelBubbleStyle.decorationLeadingOverflow,
            4
        )
    }

    func testStageLayoutLeavesRoomForPlatformAndThreeTimesPulse() {
        XCTAssertEqual(StorePreviewStageLayout.size, CGSize(width: 540, height: 280))
        XCTAssertEqual(StorePreviewStageLayout.platformHeight, 24)
        XCTAssertEqual(StorePreviewStageLayout.platformPixelSize, 4)
        XCTAssertGreaterThanOrEqual(
            StorePreviewStageLayout.size.height - StorePreviewStageLayout.platformHeight,
            EdgeTrackGeometry.characterPointSize * 3
        )
    }

    func testDetailSheetUsesBoundedScrollableViewport() {
        for availability in [StoreAvailability.comingSoon, .appStore] {
            for product in CommerceCatalog.characterProducts + [.bunnyPinkBubble] {
                let state = CommerceProductState(
                    product: product,
                    purchaseState: .available,
                    isWorking: false
                )
                let hostingView = NSHostingView(rootView: StoreProductDetailSheet(
                    productState: state,
                    actions: .empty,
                    availability: availability,
                    onClose: {}
                ))
                let fittingSize = hostingView.fittingSize

                XCTAssertEqual(fittingSize.width, 600, accuracy: 0.001, product.id)
                XCTAssertGreaterThan(
                    fittingSize.height,
                    StorePreviewStageLayout.size.height,
                    product.id
                )
                XCTAssertLessThanOrEqual(fittingSize.height, 720, product.id)
            }
        }
    }

    func testEveryStoreProductPresentationAssetShipsInTheAppBundle() throws {
        for product in CommerceCatalog.characterProducts {
            let characterID = try XCTUnwrap(product.characterID)
            let definition = PixelCharacterCatalog.definition(for: characterID)
            XCTAssertNotNil(definition.assetURL(), product.id)
            XCTAssertNotNil(PixelCharacterThrowCatalog.actionAssetURL(for: characterID), product.id)
            XCTAssertNotNil(
                PixelCharacterThrowCatalog.objectAssetURL(
                    for: try XCTUnwrap(CommerceCatalog.keepsake(for: product.id)?.renderAssetID)
                ),
                product.id
            )
        }

        for product in CommerceCatalog.cosmeticProducts {
            switch product.kind {
            case .bubble:
                let resourceName = try XCTUnwrap(
                    PixelBubbleTheme.resolve(product.catalogItemID).decorationAssetName
                )
                XCTAssertNotNil(
                    Bundle.main.url(
                        forResource: resourceName,
                        withExtension: "png",
                        subdirectory: "Bubbles"
                    ) ?? Bundle.main.url(forResource: resourceName, withExtension: "png"),
                    product.id
                )
            case .throwable:
                XCTAssertNotNil(
                    PixelCharacterThrowCatalog.objectAssetURL(for: product.catalogItemID),
                    product.id
                )
                if product.catalogItemID == PixelCharacterThrowCatalog.cannonObjectID {
                    XCTAssertNotNil(
                        PixelCharacterThrowCatalog.emitterAssetURL(for: product.catalogItemID),
                        product.id
                    )
                }
            case .character:
                XCTFail("cosmetic catalog must not contain character products")
            }
        }
    }

    func testStageRendersOneSpriteKitViewForProductsInLightAndDarkModes() throws {
        let snapshotSentinel = "/private/tmp/sidey-store-preview-snapshots"
        let outputDirectory = ProcessInfo.processInfo.environment["SIDEY_STORE_PREVIEW_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (FileManager.default.fileExists(atPath: snapshotSentinel)
                ? URL(fileURLWithPath: snapshotSentinel, isDirectory: true)
                : nil)
        if let outputDirectory {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }
        for product in [
            CommerceProduct.guineaPig,
            .bunnyPinkBubble,
            .bouncyHeart,
            .toyCannon
        ] {
            for scheme in [ColorScheme.light, .dark] {
                let root = StorePreviewStage(product: product)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 540, height: 320)
                let hostingView = NSHostingView(rootView: root)
                hostingView.frame = CGRect(x: 0, y: 0, width: 540, height: 320)
                let window = NSWindow(
                    contentRect: hostingView.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()

                let spriteViews = descendants(of: SKView.self, in: hostingView)
                XCTAssertEqual(spriteViews.count, 1)
                let bitmap = try XCTUnwrap(
                    hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
                )
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(data.count, 5_000, "\(product.id) \(scheme)")
                XCTAssertTrue(descendants(of: NSButton.self, in: hostingView).isEmpty)

                let spriteView = try XCTUnwrap(spriteViews.first)
                let scene = try XCTUnwrap(spriteView.scene)
                let sceneTexture = try XCTUnwrap(spriteView.texture(from: scene))
                let sceneBitmap = NSBitmapImageRep(cgImage: sceneTexture.cgImage())
                let sceneData = try XCTUnwrap(
                    sceneBitmap.representation(using: .png, properties: [:])
                )
                XCTAssertGreaterThan(sceneData.count, 5_000, "\(product.id) scene \(scheme)")
                if let outputDirectory {
                    let mode = scheme == .light ? "light" : "dark"
                    try sceneData.write(
                        to: outputDirectory.appending(path: "\(product.id)-\(mode).png")
                    )
                    if product.kind == .bubble,
                       let previewScene = scene as? PixelWorldScene,
                       let sequence = StorePreviewScenario.make(product: product).bubbleSequence {
                        StorePreviewSceneConfiguration.apply(
                            StorePreviewScenario.make(product: product),
                            bubblePresentation: sequence.presentation(at: 1),
                            to: previewScene
                        )
                        let messageTexture = try XCTUnwrap(spriteView.texture(from: previewScene))
                        let messageBitmap = NSBitmapImageRep(cgImage: messageTexture.cgImage())
                        let messageData = try XCTUnwrap(
                            messageBitmap.representation(using: .png, properties: [:])
                        )
                        try messageData.write(
                            to: outputDirectory.appending(
                                path: "\(product.id)-message-\(mode).png"
                            )
                        )
                    }
                }
            }
        }
    }

    func testProductionLockedStoreDefersPreviewSceneUntilSelection() {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = true
        let model = AppModel(
            preferences: preferences,
            commerceProducts: CommerceCatalog.products
        )
        let hostingView = NSHostingView(rootView: StoreView(
            model: model,
            actions: .empty,
            availability: .comingSoon
        ))
        hostingView.frame = CGRect(x: 0, y: 0, width: 1_000, height: 760)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        XCTAssertTrue(descendants(of: SKView.self, in: hostingView).isEmpty)
    }

    func testProductionDetailCreatesPreviewWithoutCommerceButton() {
        let state = CommerceProductState(
            product: .guineaPig,
            purchaseState: .available,
            isWorking: false
        )
        let productionView = NSHostingView(rootView: StoreProductDetailSheet(
            productState: state,
            actions: .empty,
            availability: .comingSoon,
            onClose: {}
        ))
        productionView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 600, height: productionView.fittingSize.height)
        )
        productionView.layoutSubtreeIfNeeded()
        productionView.displayIfNeeded()

        XCTAssertEqual(descendants(of: SKView.self, in: productionView).count, 1)
        XCTAssertFalse(StoreProductDetailSheet(
            productState: state,
            actions: .empty,
            availability: .comingSoon,
            onClose: {}
        ).displaysCommerceAction)
        XCTAssertTrue(StoreProductDetailSheet(
            productState: state,
            actions: .empty,
            availability: .appStore,
            onClose: {}
        ).displaysCommerceAction)
    }

    func testRepeatedPreviewTeardownReleasesSceneAndView() {
        weak var releasedScene: PixelWorldScene?
        weak var releasedView: StorePreviewSKView?

        for index in 0..<20 {
            autoreleasepool {
                let product = index.isMultiple(of: 2)
                    ? CommerceProduct.bouncyHeart
                    : CommerceProduct.bunnyPinkBubble
                let scenario = StorePreviewScenario.make(product: product)
                let view = StorePreviewSKView(
                    frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size)
                )
                let scene = makeScene(for: product)
                let coordinator = StorePreviewPlaybackCoordinator()
                view.presentScene(scene)
                coordinator.configure(
                    view: view,
                    scene: scene,
                    scenario: scenario,
                    isPlaying: true
                )
                coordinator.stop(detachingScene: true)
                releasedScene = scene
                releasedView = view
            }
            XCTAssertNil(releasedScene)
            XCTAssertNil(releasedView)
        }
    }

    private func makeScene(for product: CommerceProduct) -> PixelWorldScene {
        let scenario = StorePreviewScenario.make(product: product)
        let scene = PixelWorldScene(
            size: StorePreviewStageLayout.size,
            renderingConfiguration: .storePreview(
                initialTrackFractions: scenario.initialTrackFractions,
                fixedTrackFractions: scenario.fixedTrackFractions
            )
        )
        StorePreviewSceneConfiguration.apply(scenario, to: scene)
        return scene
    }

    private func advance(_ scene: PixelWorldScene, seconds: TimeInterval) {
        let start = ProcessInfo.processInfo.systemUptime
        let ticks = Int(seconds * 30)
        for tick in 0...ticks {
            scene.update(start + Double(tick) / 30)
        }
    }

    private func descendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        root.subviews.flatMap { subview -> [T] in
            let current = (subview as? T).map { [$0] } ?? []
            return current + descendants(of: type, in: subview)
        }
    }
}
