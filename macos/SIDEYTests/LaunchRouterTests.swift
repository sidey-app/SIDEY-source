import XCTest
@testable import SIDEYAppStore

final class LaunchRouterTests: XCTestCase {
    func testFirstRunWinsEvenWhenStartedByStaleLoginItem() {
        XCTAssertEqual(
            LaunchRouter.reason(hasShownNativeLanding: false, arguments: [LaunchRouter.loginItemArgument]),
            .firstRun
        )
    }

    func testSubsequentManualLaunchOpensSettings() {
        XCTAssertEqual(LaunchRouter.reason(hasShownNativeLanding: true, arguments: []), .manual)
    }

    func testLoginItemLaunchStaysQuiet() {
        XCTAssertEqual(
            LaunchRouter.reason(hasShownNativeLanding: true, arguments: [LaunchRouter.loginItemArgument]),
            .loginItem
        )
    }

    func testManualReopenDoesNotOpenSettingsWhileComposerIsVisible() {
        XCTAssertFalse(ManualReopenPolicy.shouldOpenSettings(
            hasShownNativeLanding: true,
            composerVisible: true
        ))
        XCTAssertTrue(ManualReopenPolicy.shouldOpenSettings(
            hasShownNativeLanding: true,
            composerVisible: false
        ))
        XCTAssertFalse(ManualReopenPolicy.shouldOpenSettings(
            hasShownNativeLanding: false,
            composerVisible: false
        ))
        XCTAssertFalse(ManualReopenPolicy.shouldOpenSettings(
            hasShownNativeLanding: true,
            composerVisible: false,
            originatesFromOverlayInteraction: true
        ))
    }

    func testExistingUserWaitsForBackendBeforeOpeningOverlay() {
        XCTAssertEqual(
            FirstRunTransition.destination(
                landingCompleted: true,
                onboardingComplete: true,
                backendState: .pending
            ),
            .waiting
        )
        XCTAssertEqual(
            FirstRunTransition.destination(
                landingCompleted: true,
                onboardingComplete: true,
                backendState: .ready
            ),
            .overlay
        )
    }

    func testExistingUserGetsRecoveryUIWhenBackendRestoreFails() {
        XCTAssertEqual(
            FirstRunTransition.destination(
                landingCompleted: true,
                onboardingComplete: true,
                backendState: .failed
            ),
            .recovery
        )
    }

    func testNewUserCanEnterOnboardingWithoutWaitingForBackend() {
        XCTAssertEqual(
            FirstRunTransition.destination(
                landingCompleted: true,
                onboardingComplete: false,
                backendState: .pending
            ),
            .onboarding
        )
    }

    func testOverlayCannotAppearUntilOnboardingAndSessionRestoreAreBothComplete() {
        XCTAssertFalse(OverlayRevealPolicy.isVisible(
            requested: true,
            onboardingComplete: false,
            backendState: .ready
        ))
        XCTAssertFalse(OverlayRevealPolicy.isVisible(
            requested: true,
            onboardingComplete: true,
            backendState: .pending
        ))
        XCTAssertFalse(OverlayRevealPolicy.isVisible(
            requested: true,
            onboardingComplete: true,
            backendState: .failed
        ))
        XCTAssertTrue(OverlayRevealPolicy.isVisible(
            requested: true,
            onboardingComplete: true,
            backendState: .ready
        ))
        XCTAssertFalse(OverlayRevealPolicy.isVisible(
            requested: false,
            onboardingComplete: true,
            backendState: .ready
        ))
    }

    @MainActor
    func testOverlayVisibilityIsIndependentExplicitState() {
        var preferences = AppPreferences.defaults
        preferences.overlayVisible = false
        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.overlayVisibility, .hidden)
        model.setOverlayVisibility(.visible)
        XCTAssertTrue(model.overlayVisible)
        XCTAssertTrue(model.preferences.overlayVisible)
    }
}
