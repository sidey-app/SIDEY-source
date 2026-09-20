import AppKit
import Carbon

enum GlobalShortcutAction: UInt32, CaseIterable, Identifiable {
    case toggleQuietMode = 1
    case toggleComposer = 2
    case openHistory = 3

    var id: UInt32 { rawValue }
    var title: String {
        switch self {
        case .toggleQuietMode: "조용히 모드"
        case .toggleComposer: "입력창 열기 / 닫기"
        case .openHistory: "최근 기록 열기"
        }
    }
    var key: String {
        switch self {
        case .toggleQuietMode: "M"
        case .toggleComposer: "I"
        case .openHistory: "R"
        }
    }
    static let modifierMask = UInt32(controlKey | optionKey | cmdKey)
    static let modifierDescription = "Control + Option + Command"

    var displayShortcut: String { "⌃⌥⌘\(key)" }
    var descriptiveShortcut: String { "\(Self.modifierDescription) + \(key)" }
    var keyCode: UInt32 {
        switch self {
        case .toggleQuietMode: UInt32(kVK_ANSI_M)
        case .toggleComposer: UInt32(kVK_ANSI_I)
        case .openHistory: UInt32(kVK_ANSI_R)
        }
    }
}

enum GlobalShortcutStatus: Equatable {
    case registered
    case unavailable(OSStatus)

    var notice: String? {
        switch self {
        case .registered: nil
        case .unavailable(let code) where code == eventHotKeyExistsErr:
            "다른 앱에서 사용 중인 단축키입니다. 충돌하는 단축키를 해제한 뒤 SIDEY를 다시 실행해 주세요."
        case .unavailable:
            "단축키를 등록하지 못했습니다. 메뉴에서 실행하거나 SIDEY를 다시 실행해 주세요."
        }
    }
}

/// Only registered shortcut identifiers reach the app; other applications' key input is never observed.
@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func installHandler(_ handler: @escaping (GlobalShortcutAction, Bool) -> Void) -> OSStatus
    func register(_ action: GlobalShortcutAction) -> OSStatus
    func unregisterAll()
}

@MainActor
final class GlobalShortcutController {
    private let registrar: any GlobalShortcutRegistering
    private let onAction: (GlobalShortcutAction) -> Void
    private let onStatusChanged: ([GlobalShortcutAction: GlobalShortcutStatus]) -> Void
    private var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
    private var pressed: Set<GlobalShortcutAction> = []
    private var installed = false

    init(
        registrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        onAction: @escaping (GlobalShortcutAction) -> Void,
        onStatusChanged: @escaping ([GlobalShortcutAction: GlobalShortcutStatus]) -> Void = { _ in }
    ) {
        self.registrar = registrar
        self.onAction = onAction
        self.onStatusChanged = onStatusChanged
    }

    isolated deinit {
        registrar.unregisterAll()
    }

    func install() {
        guard !installed else { return }
        installed = true
        let handlerStatus = registrar.installHandler { [weak self] action, isPressed in
            self?.receive(action, isPressed: isPressed)
        }
        for action in GlobalShortcutAction.allCases {
            let status = handlerStatus == noErr ? registrar.register(action) : handlerStatus
            statuses[action] = status == noErr ? .registered : .unavailable(status)
        }
        onStatusChanged(statuses)
    }

    func uninstall() {
        guard installed else { return }
        installed = false
        registrar.unregisterAll()
        pressed.removeAll()
        statuses.removeAll()
        onStatusChanged(statuses)
    }

    private func receive(_ action: GlobalShortcutAction, isPressed: Bool) {
        guard installed, statuses[action] == .registered else { return }
        if isPressed {
            guard pressed.insert(action).inserted else { return }
            onAction(action)
        } else {
            pressed.remove(action)
        }
    }
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private static let signature: OSType = 0x53445948 // SDYH
    private var handler: ((GlobalShortcutAction, Bool) -> Void)?
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    isolated deinit {
        for reference in hotKeys { UnregisterEventHotKey(reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func installHandler(_ handler: @escaping (GlobalShortcutAction, Bool) -> Void) -> OSStatus {
        guard eventHandler == nil else { return noErr }
        self.handler = handler
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                // The handler is installed on the application's main event target from the main actor.
                return MainActor.assumeIsolated {
                    let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(context).takeUnretainedValue()
                    return registrar.handle(event)
                }
            },
            types.count, &types,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        if result != noErr { self.handler = nil }
        return result
    }

    func register(_ action: GlobalShortcutAction) -> OSStatus {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(
            action.keyCode, GlobalShortcutAction.modifierMask,
            EventHotKeyID(signature: Self.signature, id: action.rawValue),
            GetApplicationEventTarget(), 0, &reference
        )
        if result == noErr, let reference { hotKeys.append(reference) }
        return result
    }

    func unregisterAll() {
        for reference in hotKeys { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        handler = nil
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let result = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
        )
        guard result == noErr, identifier.signature == Self.signature,
              let action = GlobalShortcutAction(rawValue: identifier.id)
        else { return OSStatus(eventNotHandledErr) }
        handler?(action, GetEventKind(event) == UInt32(kEventHotKeyPressed))
        return noErr
    }
}
