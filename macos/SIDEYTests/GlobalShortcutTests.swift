import AppKit
import Carbon
import XCTest
@testable import SIDEYAppStore

@MainActor
final class GlobalShortcutTests: XCTestCase {
    func testShortcutDefinitionsRequireControlOptionCommandFourKeyChords() {
        XCTAssertEqual(
            GlobalShortcutAction.modifierMask,
            UInt32(controlKey | optionKey | cmdKey)
        )
        XCTAssertEqual(GlobalShortcutAction.toggleQuietMode.displayShortcut, "⌃⌥⌘M")
        XCTAssertEqual(GlobalShortcutAction.toggleComposer.displayShortcut, "⌃⌥⌘I")
        XCTAssertEqual(GlobalShortcutAction.openHistory.displayShortcut, "⌃⌥⌘R")
        XCTAssertEqual(
            GlobalShortcutAction.allCases.map(\.descriptiveShortcut),
            [
                "Control + Option + Command + M",
                "Control + Option + Command + I",
                "Control + Option + Command + R"
            ]
        )
    }

    func testHoldingShortcutRunsOnceUntilReleaseAndDifferentShortcutsRemainIndependent() {
        let registrar = FakeGlobalShortcutRegistrar()
        var actions: [GlobalShortcutAction] = []
        let controller = GlobalShortcutController(registrar: registrar, onAction: { actions.append($0) })
        controller.install()

        registrar.send(.toggleComposer, pressed: true)
        registrar.send(.toggleComposer, pressed: true)
        registrar.send(.toggleQuietMode, pressed: true)
        registrar.send(.toggleComposer, pressed: true)
        registrar.send(.toggleComposer, pressed: false)
        registrar.send(.toggleComposer, pressed: true)

        XCTAssertEqual(actions, [.toggleComposer, .toggleQuietMode, .toggleComposer])
        controller.uninstall()
    }

    func testConflictOnlyDisablesItsOwnShortcutAndPublishesActionableNotice() {
        let registrar = FakeGlobalShortcutRegistrar()
        registrar.registrationResults[.toggleQuietMode] = OSStatus(eventHotKeyExistsErr)
        var actions: [GlobalShortcutAction] = []
        var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
        let controller = GlobalShortcutController(
            registrar: registrar, onAction: { actions.append($0) }, onStatusChanged: { statuses = $0 }
        )
        controller.install()
        registrar.send(.toggleQuietMode, pressed: true)
        registrar.send(.openHistory, pressed: true)

        XCTAssertEqual(actions, [.openHistory])
        XCTAssertEqual(statuses[.toggleQuietMode], .unavailable(OSStatus(eventHotKeyExistsErr)))
        XCTAssertTrue(statuses[.toggleQuietMode]?.notice?.contains("다른 앱") == true)
        XCTAssertEqual(statuses[.toggleComposer], .registered)
        XCTAssertEqual(statuses[.openHistory], .registered)
        controller.uninstall()
    }

    func testHandlerFailureReportsEveryShortcutWithoutAttemptingRegistrations() {
        let registrar = FakeGlobalShortcutRegistrar()
        registrar.handlerResult = OSStatus(eventInternalErr)
        var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
        let controller = GlobalShortcutController(
            registrar: registrar, onAction: { _ in XCTFail("실패한 등록에서 실행됨") },
            onStatusChanged: { statuses = $0 }
        )
        controller.install()
        registrar.send(.openHistory, pressed: true)

        XCTAssertTrue(registrar.registered.isEmpty)
        XCTAssertEqual(statuses.count, 3)
        XCTAssertTrue(statuses.values.allSatisfy { $0 == .unavailable(OSStatus(eventInternalErr)) })
        XCTAssertTrue(statuses.values.allSatisfy { $0.notice?.contains("등록하지 못했습니다") == true })
        controller.uninstall()
    }

    func testInstallIsIdempotentAndUninstallIgnoresLateEventsAndResetsHeldKey() {
        let registrar = FakeGlobalShortcutRegistrar()
        var actions: [GlobalShortcutAction] = []
        var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
        let controller = GlobalShortcutController(
            registrar: registrar, onAction: { actions.append($0) }, onStatusChanged: { statuses = $0 }
        )
        controller.install()
        controller.install()
        XCTAssertEqual(registrar.registered, GlobalShortcutAction.allCases)
        registrar.send(.toggleComposer, pressed: true)
        controller.uninstall()
        controller.uninstall()
        registrar.send(.toggleComposer, pressed: false)
        registrar.send(.toggleComposer, pressed: true)
        XCTAssertEqual(registrar.unregisterCount, 1)
        XCTAssertTrue(statuses.isEmpty)
        XCTAssertEqual(actions, [.toggleComposer])

        controller.install()
        registrar.send(.toggleComposer, pressed: true)
        XCTAssertEqual(actions, [.toggleComposer, .toggleComposer])
        controller.uninstall()
    }

    func testReleasingControllerUnregistersNativeResources() {
        let registrar = FakeGlobalShortcutRegistrar()
        var controller: GlobalShortcutController? = GlobalShortcutController(
            registrar: registrar, onAction: { _ in XCTFail("종료한 컨트롤러에서 실행됨") }
        )
        controller?.install()
        controller = nil
        XCTAssertEqual(registrar.unregisterCount, 1)
        registrar.send(.toggleComposer, pressed: true)
    }

    func testMenuShowsShortcutAndConflictWithoutAnotherKeyDispatchPath() throws {
        let controller = StatusItemController(onToggleOverlay: {}, onOpenSettings: {}, onQuit: {})
        controller.update(overlayVisible: true, globalShortcutStatuses: [
            .toggleQuietMode: .unavailable(OSStatus(eventHotKeyExistsErr)),
            .toggleComposer: .registered,
            .openHistory: .registered
        ])
        let menu = controller.makeMenu()
        for (title, action) in [
            ("메시지 작성…", GlobalShortcutAction.toggleComposer),
            ("조용히 모드", .toggleQuietMode),
            ("최근 기록…", .openHistory)
        ] {
            let item = try XCTUnwrap(menu.item(withTitle: title))
            XCTAssertEqual(item.keyEquivalent, "")
            XCTAssertTrue(item.attributedTitle?.string.contains(action.displayShortcut) == true)
        }
        let quiet = try XCTUnwrap(menu.item(withTitle: "조용히 모드"))
        XCTAssertTrue(quiet.attributedTitle?.string.contains("단축키 사용 불가") == true)
        XCTAssertTrue(quiet.toolTip?.contains("다른 앱") == true)
        let composer = try XCTUnwrap(menu.item(withTitle: "메시지 작성…"))
        XCTAssertEqual(composer.toolTip, "Control + Option + Command + I")
    }
}

@MainActor
private final class FakeGlobalShortcutRegistrar: GlobalShortcutRegistering {
    var handlerResult: OSStatus = noErr
    var registrationResults: [GlobalShortcutAction: OSStatus] = [:]
    var registered: [GlobalShortcutAction] = []
    var unregisterCount = 0
    private var handler: ((GlobalShortcutAction, Bool) -> Void)?

    func installHandler(_ handler: @escaping (GlobalShortcutAction, Bool) -> Void) -> OSStatus {
        self.handler = handler
        return handlerResult
    }
    func register(_ action: GlobalShortcutAction) -> OSStatus {
        registered.append(action)
        return registrationResults[action] ?? noErr
    }
    func unregisterAll() {
        unregisterCount += 1
        // Keep the callback to simulate an already enqueued native event after teardown.
    }
    func send(_ action: GlobalShortcutAction, pressed: Bool) { handler?(action, pressed) }
}
