import AppKit
import Carbon

enum GlobalShortcutAction: UInt32, CaseIterable, Identifiable, Sendable {
    case toggleQuietMode = 1
    case toggleComposer = 2
    case openHistory = 3
    case toggleOverlay = 4

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .toggleQuietMode: L10n.text("shortcut.action.quiet_mode")
        case .toggleComposer: L10n.text("shortcut.action.composer")
        case .openHistory: L10n.text("shortcut.action.history")
        case .toggleOverlay: L10n.text("shortcut.action.overlay")
        }
    }

    var defaultBinding: GlobalShortcutBinding {
        switch self {
        case .toggleQuietMode: GlobalShortcutBinding(key: .m)
        case .toggleComposer: GlobalShortcutBinding(key: .i)
        case .openHistory: GlobalShortcutBinding(key: .r)
        case .toggleOverlay: GlobalShortcutBinding(key: .h)
        }
    }
}

enum GlobalShortcutModifier: String, CaseIterable, Identifiable, Sendable {
    case control
    case option
    case shift
    case command

    var id: String { rawValue }

    var mask: UInt32 {
        switch self {
        case .control: UInt32(controlKey)
        case .option: UInt32(optionKey)
        case .shift: UInt32(shiftKey)
        case .command: UInt32(cmdKey)
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var title: String {
        switch self {
        case .control: L10n.text("shortcut.modifier.control")
        case .option: L10n.text("shortcut.modifier.option")
        case .shift: L10n.text("shortcut.modifier.shift")
        case .command: L10n.text("shortcut.modifier.command")
        }
    }
}

struct GlobalShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: UInt32

    static let control = Self(rawValue: GlobalShortcutModifier.control.mask)
    static let option = Self(rawValue: GlobalShortcutModifier.option.mask)
    static let shift = Self(rawValue: GlobalShortcutModifier.shift.mask)
    static let command = Self(rawValue: GlobalShortcutModifier.command.mask)
    static let defaultValue: Self = [.control, .option, .command]
    static let supported: Self = [.control, .option, .shift, .command]

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt32.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func contains(_ modifier: GlobalShortcutModifier) -> Bool {
        contains(Self(rawValue: modifier.mask))
    }

    mutating func set(_ modifier: GlobalShortcutModifier, enabled: Bool) {
        let value = Self(rawValue: modifier.mask)
        if enabled {
            insert(value)
        } else {
            remove(value)
        }
    }

    var isValid: Bool {
        !isEmpty && subtracting(Self.supported).isEmpty
    }

    var displayText: String {
        GlobalShortcutModifier.allCases
            .filter(contains)
            .map(\.symbol)
            .joined()
    }

    var descriptiveText: String {
        GlobalShortcutModifier.allCases
            .filter(contains)
            .map(\.title)
            .joined(separator: " + ")
    }
}

enum GlobalShortcutKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G"
    case h = "H", i = "I", j = "J", k = "K", l = "L", m = "M", n = "N"
    case o = "O", p = "P", q = "Q", r = "R", s = "S", t = "T", u = "U"
    case v = "V", w = "W", x = "X", y = "Y", z = "Z"
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .a: UInt32(kVK_ANSI_A)
        case .b: UInt32(kVK_ANSI_B)
        case .c: UInt32(kVK_ANSI_C)
        case .d: UInt32(kVK_ANSI_D)
        case .e: UInt32(kVK_ANSI_E)
        case .f: UInt32(kVK_ANSI_F)
        case .g: UInt32(kVK_ANSI_G)
        case .h: UInt32(kVK_ANSI_H)
        case .i: UInt32(kVK_ANSI_I)
        case .j: UInt32(kVK_ANSI_J)
        case .k: UInt32(kVK_ANSI_K)
        case .l: UInt32(kVK_ANSI_L)
        case .m: UInt32(kVK_ANSI_M)
        case .n: UInt32(kVK_ANSI_N)
        case .o: UInt32(kVK_ANSI_O)
        case .p: UInt32(kVK_ANSI_P)
        case .q: UInt32(kVK_ANSI_Q)
        case .r: UInt32(kVK_ANSI_R)
        case .s: UInt32(kVK_ANSI_S)
        case .t: UInt32(kVK_ANSI_T)
        case .u: UInt32(kVK_ANSI_U)
        case .v: UInt32(kVK_ANSI_V)
        case .w: UInt32(kVK_ANSI_W)
        case .x: UInt32(kVK_ANSI_X)
        case .y: UInt32(kVK_ANSI_Y)
        case .z: UInt32(kVK_ANSI_Z)
        case .zero: UInt32(kVK_ANSI_0)
        case .one: UInt32(kVK_ANSI_1)
        case .two: UInt32(kVK_ANSI_2)
        case .three: UInt32(kVK_ANSI_3)
        case .four: UInt32(kVK_ANSI_4)
        case .five: UInt32(kVK_ANSI_5)
        case .six: UInt32(kVK_ANSI_6)
        case .seven: UInt32(kVK_ANSI_7)
        case .eight: UInt32(kVK_ANSI_8)
        case .nine: UInt32(kVK_ANSI_9)
        }
    }
}

struct GlobalShortcutBinding: Codable, Equatable, Hashable, Sendable {
    var key: GlobalShortcutKey
    var modifiers: GlobalShortcutModifiers

    init(key: GlobalShortcutKey, modifiers: GlobalShortcutModifiers = .defaultValue) {
        self.key = key
        self.modifiers = modifiers
    }

    var isValid: Bool { modifiers.isValid }
    var keyCode: UInt32 { key.keyCode }
    var modifierMask: UInt32 { modifiers.rawValue }
    var displayShortcut: String { modifiers.displayText + key.rawValue }
    var descriptiveShortcut: String { modifiers.descriptiveText + " + " + key.rawValue }
}

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    var toggleQuietMode: GlobalShortcutBinding
    var toggleComposer: GlobalShortcutBinding
    var openHistory: GlobalShortcutBinding
    var toggleOverlay: GlobalShortcutBinding

    static let defaults = GlobalShortcutConfiguration(
        toggleQuietMode: GlobalShortcutAction.toggleQuietMode.defaultBinding,
        toggleComposer: GlobalShortcutAction.toggleComposer.defaultBinding,
        openHistory: GlobalShortcutAction.openHistory.defaultBinding,
        toggleOverlay: GlobalShortcutAction.toggleOverlay.defaultBinding
    )

    subscript(action: GlobalShortcutAction) -> GlobalShortcutBinding {
        get {
            switch action {
            case .toggleQuietMode: toggleQuietMode
            case .toggleComposer: toggleComposer
            case .openHistory: openHistory
            case .toggleOverlay: toggleOverlay
            }
        }
        set {
            switch action {
            case .toggleQuietMode: toggleQuietMode = newValue
            case .toggleComposer: toggleComposer = newValue
            case .openHistory: openHistory = newValue
            case .toggleOverlay: toggleOverlay = newValue
            }
        }
    }

    func action(using binding: GlobalShortcutBinding, excluding excluded: GlobalShortcutAction) -> GlobalShortcutAction? {
        GlobalShortcutAction.allCases.first { $0 != excluded && self[$0] == binding }
    }

    private enum CodingKeys: String, CodingKey {
        case toggleQuietMode
        case toggleComposer
        case openHistory
        case toggleOverlay
    }

    init(
        toggleQuietMode: GlobalShortcutBinding,
        toggleComposer: GlobalShortcutBinding,
        openHistory: GlobalShortcutBinding,
        toggleOverlay: GlobalShortcutBinding
    ) {
        self.toggleQuietMode = toggleQuietMode
        self.toggleComposer = toggleComposer
        self.openHistory = openHistory
        self.toggleOverlay = toggleOverlay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        self.init(
            toggleQuietMode: (try? values.decode(
                GlobalShortcutBinding.self, forKey: .toggleQuietMode
            )) ?? defaults.toggleQuietMode,
            toggleComposer: (try? values.decode(
                GlobalShortcutBinding.self, forKey: .toggleComposer
            )) ?? defaults.toggleComposer,
            openHistory: (try? values.decode(
                GlobalShortcutBinding.self, forKey: .openHistory
            )) ?? defaults.openHistory,
            toggleOverlay: (try? values.decode(
                GlobalShortcutBinding.self, forKey: .toggleOverlay
            )) ?? defaults.toggleOverlay
        )
        self = normalized()
    }

    func normalized() -> Self {
        var result = Self.defaults
        var used: Set<GlobalShortcutBinding> = []
        for action in GlobalShortcutAction.allCases {
            let requested = self[action]
            let candidates = [requested, action.defaultBinding]
                + GlobalShortcutAction.allCases.map(\.defaultBinding)
            guard let accepted = candidates.first(where: { $0.isValid && !used.contains($0) }) else {
                continue
            }
            result[action] = accepted
            used.insert(accepted)
        }
        return result
    }
}

enum GlobalShortcutChangeFailure: Equatable {
    case invalid
    case duplicate(GlobalShortcutAction)
    case unavailable(OSStatus)
}

enum GlobalShortcutStatus: Equatable {
    case registered
    case unavailable(OSStatus)
    case changeRejected(GlobalShortcutChangeFailure)

    var notice: String? {
        switch self {
        case .registered:
            nil
        case .unavailable(let code) where code == eventHotKeyExistsErr:
            L10n.text("shortcut.error.used_by_other_app")
        case .unavailable:
            L10n.text("shortcut.error.registration_failed")
        case .changeRejected(.invalid):
            L10n.text("shortcut.error.modifier_required")
        case .changeRejected(.duplicate(let action)):
            L10n.format("shortcut.error.duplicate", action.title)
        case .changeRejected(.unavailable(let code)) where code == eventHotKeyExistsErr:
            L10n.text("shortcut.error.new_binding_used_by_other_app")
        case .changeRejected(.unavailable):
            L10n.text("shortcut.error.new_binding_registration_failed")
        }
    }

    var menuAnnotation: String? {
        switch self {
        case .registered: nil
        case .unavailable: L10n.text("shortcut.status.unavailable")
        case .changeRejected: L10n.text("shortcut.status.change_failed")
        }
    }
}

/// Only registered shortcut identifiers reach the app; other applications' key input is never observed.
@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func installHandler(_ handler: @escaping (GlobalShortcutAction, Bool) -> Void) -> OSStatus
    func register(_ action: GlobalShortcutAction, binding: GlobalShortcutBinding) -> OSStatus
    func replace(_ action: GlobalShortcutAction, binding: GlobalShortcutBinding) -> OSStatus
    func unregisterAll()
}

@MainActor
final class GlobalShortcutController {
    private let registrarLifetime: MainActorResourceLifetime<any GlobalShortcutRegistering>
    private var registrar: any GlobalShortcutRegistering { registrarLifetime.resource }
    private let onAction: (GlobalShortcutAction) -> Void
    private let onStatusChanged: ([GlobalShortcutAction: GlobalShortcutStatus]) -> Void
    private var configuration: GlobalShortcutConfiguration
    private var statuses: [GlobalShortcutAction: GlobalShortcutStatus] = [:]
    private var registeredActions: Set<GlobalShortcutAction> = []
    private var pressed: Set<GlobalShortcutAction> = []
    private var installed = false
    private var handlerStatus: OSStatus?

    init(
        configuration: GlobalShortcutConfiguration = .defaults,
        registrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        onAction: @escaping (GlobalShortcutAction) -> Void,
        onStatusChanged: @escaping ([GlobalShortcutAction: GlobalShortcutStatus]) -> Void = { _ in }
    ) {
        self.configuration = configuration.normalized()
        self.registrarLifetime = MainActorResourceLifetime(registrar) { $0.unregisterAll() }
        self.onAction = onAction
        self.onStatusChanged = onStatusChanged
    }

    // The lifetime object performs cleanup without the older isolated-deinit runtime path.
    nonisolated deinit {}

    func install() {
        guard !installed else { return }
        installed = true
        let handlerStatus = registrar.installHandler { [weak self] action, isPressed in
            self?.receive(action, isPressed: isPressed)
        }
        self.handlerStatus = handlerStatus
        for action in GlobalShortcutAction.allCases {
            let status = handlerStatus == noErr
                ? registrar.register(action, binding: configuration[action])
                : handlerStatus
            if status == noErr { registeredActions.insert(action) }
            statuses[action] = status == noErr ? .registered : .unavailable(status)
        }
        onStatusChanged(statuses)
    }

    @discardableResult
    func update(_ action: GlobalShortcutAction, binding: GlobalShortcutBinding) -> Bool {
        guard binding.isValid else {
            reject(action, failure: .invalid)
            return false
        }
        if let duplicate = configuration.action(using: binding, excluding: action) {
            reject(action, failure: .duplicate(duplicate))
            return false
        }
        if configuration[action] == binding {
            if registeredActions.contains(action) { statuses[action] = .registered }
            onStatusChanged(statuses)
            return registeredActions.contains(action)
        }

        guard installed else {
            configuration[action] = binding
            return true
        }
        guard handlerStatus == noErr else {
            reject(action, failure: .unavailable(handlerStatus ?? OSStatus(eventInternalErr)))
            return false
        }
        let result = registrar.replace(action, binding: binding)
        guard result == noErr else {
            reject(action, failure: .unavailable(result))
            return false
        }

        configuration[action] = binding
        registeredActions.insert(action)
        pressed.remove(action)
        statuses[action] = .registered
        onStatusChanged(statuses)
        return true
    }

    func uninstall() {
        guard installed else { return }
        installed = false
        handlerStatus = nil
        registrar.unregisterAll()
        registeredActions.removeAll()
        pressed.removeAll()
        statuses.removeAll()
        onStatusChanged(statuses)
    }

    private func reject(_ action: GlobalShortcutAction, failure: GlobalShortcutChangeFailure) {
        statuses[action] = .changeRejected(failure)
        onStatusChanged(statuses)
    }

    private func receive(_ action: GlobalShortcutAction, isPressed: Bool) {
        guard installed, registeredActions.contains(action) else { return }
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
    private struct Registration {
        let identifier: UInt32
        let reference: EventHotKeyRef
    }

    private final class Resources {
        var handler: ((GlobalShortcutAction, Bool) -> Void)?
        var eventHandler: EventHandlerRef?
        var registrations: [GlobalShortcutAction: Registration] = [:]
        var actionsByIdentifier: [UInt32: GlobalShortcutAction] = [:]

        @MainActor
        func unregisterAll() {
            for registration in registrations.values {
                UnregisterEventHotKey(registration.reference)
            }
            registrations.removeAll()
            actionsByIdentifier.removeAll()
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            handler = nil
        }

        @MainActor
        func handle(_ event: EventRef) -> OSStatus {
            var identifier = EventHotKeyID()
            let result = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard result == noErr, identifier.signature == CarbonGlobalShortcutRegistrar.signature,
                  let action = actionsByIdentifier[identifier.id]
            else { return OSStatus(eventNotHandledErr) }
            handler?(action, GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }
    }

    private static let signature: OSType = 0x53445948 // SDYH
    private let resourceLifetime = MainActorResourceLifetime(Resources()) { $0.unregisterAll() }
    private var resources: Resources { resourceLifetime.resource }
    private var nextIdentifier: UInt32 = 1

    nonisolated deinit {}

    func installHandler(_ handler: @escaping (GlobalShortcutAction, Bool) -> Void) -> OSStatus {
        guard resources.eventHandler == nil else { return noErr }
        resources.handler = handler
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
                    let resources = Unmanaged<Resources>.fromOpaque(context).takeUnretainedValue()
                    return resources.handle(event)
                }
            },
            types.count, &types,
            // Cleanup retains this context until its native handler is removed on MainActor.
            Unmanaged.passUnretained(resources).toOpaque(), &resources.eventHandler
        )
        if result != noErr { resources.handler = nil }
        return result
    }

    func register(_ action: GlobalShortcutAction, binding: GlobalShortcutBinding) -> OSStatus {
        guard resources.registrations[action] == nil else { return OSStatus(eventHotKeyExistsErr) }
        let (status, registration) = makeRegistration(binding: binding)
        if let registration { store(registration, for: action) }
        return status
    }

    func replace(_ action: GlobalShortcutAction, binding: GlobalShortcutBinding) -> OSStatus {
        let (status, replacement) = makeRegistration(binding: binding)
        guard status == noErr, let replacement else { return status }

        if let current = resources.registrations[action] {
            let unregisterStatus = UnregisterEventHotKey(current.reference)
            guard unregisterStatus == noErr else {
                UnregisterEventHotKey(replacement.reference)
                return unregisterStatus
            }
            resources.actionsByIdentifier[current.identifier] = nil
        }
        store(replacement, for: action)
        return noErr
    }

    func unregisterAll() {
        resources.unregisterAll()
    }

    private func makeRegistration(binding: GlobalShortcutBinding) -> (OSStatus, Registration?) {
        let identifier = nextIdentifier
        nextIdentifier &+= 1
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(
            binding.keyCode, binding.modifierMask,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(), 0, &reference
        )
        guard result == noErr, let reference else { return (result, nil) }
        return (noErr, Registration(identifier: identifier, reference: reference))
    }

    private func store(_ registration: Registration, for action: GlobalShortcutAction) {
        resources.registrations[action] = registration
        resources.actionsByIdentifier[registration.identifier] = action
    }
}
