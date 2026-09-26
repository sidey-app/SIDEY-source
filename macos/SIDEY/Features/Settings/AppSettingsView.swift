import SwiftUI
import AuthenticationServices

enum AppSettingsLegalLinks {
    static var localizedPrivacyPolicy: URL {
        localizedURL(page: "privacy")
    }

    static var localizedTermsOfService: URL {
        localizedURL(page: "terms")
    }

    static func localizedURL(
        page: String,
        preferredLocalization: String = Bundle.main.preferredLocalizations.first ?? "en"
    ) -> URL {
        let localePath = switch preferredLocalization.lowercased() {
        case let value where value.hasPrefix("ko"): "ko/"
        case let value where value.hasPrefix("ja"): "ja/"
        case let value where value.hasPrefix("zh-hant")
            || value.hasPrefix("zh-tw")
            || value.hasPrefix("zh-hk")
            || value.hasPrefix("zh-mo"): "zh-hant/"
        default: "en/"
        }
        return URL(string: "https://sidey-app.github.io/SIDEY/\(localePath)\(page)/")!
    }
}

struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let storeAvailability: StoreAvailability
    @State private var showsDeletionControls = false
    @State private var deletionPhrase = ""

    init(
        model: AppModel,
        actions: SettingsActions,
        storeAvailability: StoreAvailability = AppReleaseChannel.resolve().storeAvailability
    ) {
        self.model = model
        self.actions = actions
        self.storeAvailability = storeAvailability
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            #if DEBUG
            Text(verbatim: debugBuildStamp)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            #endif
            SettingsSection(
                title: "settings.section.general.title",
                subtitle: "settings.general.subtitle",
                systemImage: "gearshape"
            ) {
                SettingsToggleRow(
                    title: "settings.overlay.title",
                    description: "settings.general.overlay_visible.description",
                    isOn: Binding(
                        get: { model.overlayVisible },
                        set: { actions.onOverlayVisibilityChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "settings.startup.title",
                    description: "settings.startup.description",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { actions.onLaunchAtLoginChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "settings.section.display.title",
                subtitle: "settings.display.subtitle",
                systemImage: "eye"
            ) {
                SettingsToggleRow(
                    title: "settings.display.quiet_mode.title",
                    description: "settings.display.quiet_mode.description",
                    isOn: Binding(
                        get: { model.preferences.quietModeEnabled },
                        set: { actions.onQuietModeChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "settings.display.offline_members.title",
                    description: "settings.display.offline_members.description",
                    isOn: Binding(
                        get: { model.preferences.showOfflineMembers },
                        set: { actions.onShowOfflineMembersChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "settings.display.throw_guard.title",
                    description: "settings.display.throw_guard.description",
                    isOn: Binding(
                        get: { model.preferences.requiresRightClickToThrow },
                        set: { actions.onRequiresRightClickToThrowChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "settings.shortcuts.title",
                subtitle: "settings.shortcuts.subtitle",
                systemImage: "keyboard"
            ) {
                ForEach(GlobalShortcutAction.allCases) { shortcut in
                    SettingsControlRow(
                        title: shortcut.localizedTitle,
                        verbatimDescription: model.globalShortcutStatuses[shortcut]?.notice
                            ?? model.preferences.globalShortcuts[shortcut].descriptiveShortcut
                    ) {
                        GlobalShortcutEditor(
                            binding: shortcutBinding(shortcut),
                            defaultBinding: shortcut.defaultBinding
                        )
                    }
                    if shortcut != GlobalShortcutAction.allCases.last { Divider() }
                }
            }

            SettingsSection(
                title: "settings.section.sound.title",
                subtitle: "settings.sound.subtitle",
                systemImage: "speaker.wave.2"
            ) {
                SettingsToggleRow(
                    title: "settings.sound.character_effects.title",
                    description: "settings.sound.character_effects.description",
                    isOn: Binding(get: { model.preferences.characterSoundEffectsEnabled },
                                  set: { actions.onCharacterSoundEffectsChanged($0) })
                )
            }

            SettingsSection(
                title: "settings.placement.title",
                subtitle: "settings.placement.subtitle",
                systemImage: "rectangle.inset.filled"
            ) {
                SettingsControlRow(
                    title: "settings.placement.edge.title",
                    description: "settings.placement.edge.description"
                ) {
                    Picker("settings.placement.edge.picker", selection: regionEdgeBinding) {
                        ForEach(OverlayEdge.allCases) { edge in
                            Text(edge.localizedTitle).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "settings.placement.span.title",
                    description: "settings.placement.span.description"
                ) {
                    Picker("settings.placement.span.picker", selection: regionSpanBinding) {
                        ForEach(OverlaySpan.allCases) { span in
                            Text(span.localizedTitle).tag(span)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "settings.placement.monitor.title",
                    description: "settings.placement.monitor.description"
                ) {
                    Picker("settings.placement.monitor.picker", selection: regionScreenBinding) {
                        ForEach(model.availableScreens) { screen in
                            Text(verbatim: screen.name).tag(Optional(screen.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                }
            }

            if storeAvailability.usesAppStore {
                accountSection
            }

        }
    }

    private var accountSection: some View {
        SettingsSection(
            title: "settings.account.title",
            subtitle: "settings.account.subtitle",
            systemImage: "person.crop.circle"
        ) {
            HStack(spacing: 18) {
                Link(
                    "settings.account.privacy_policy",
                    destination: AppSettingsLegalLinks.localizedPrivacyPolicy
                )
                Link(
                    "settings.account.terms",
                    destination: AppSettingsLegalLinks.localizedTermsOfService
                )
                Spacer()
                Button("settings.account.restore_purchases", action: actions.onRestorePurchases)
                    .disabled(model.accountOperationInProgress)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.account.delete.title")
                    .font(.body.weight(.semibold))
                Text("settings.account.delete.description")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if showsDeletionControls {
                    TextField("settings.account.delete.placeholder", text: $deletionPhrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    SignInWithAppleButton(.continue) { request in
                        let nonce = AppleAuthorization.makeNonce()
                        AppleAuthorization.prepare(request, nonce: nonce)
                    } onCompletion: { result in
                        do {
                            let payload = try AppleAuthorization.payload(from: result)
                            actions.onDeleteAccount(payload)
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(width: 280, height: 40)
                    .disabled(deletionPhrase != deletionConfirmationPhrase || model.accountOperationInProgress)
                    Text("settings.account.delete.authentication_notice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("settings.account.delete.reveal", role: .destructive) {
                        showsDeletionControls = true
                    }
                }
            }
        }
    }

    private var regionEdgeBinding: Binding<OverlayEdge> {
        Binding(
            get: { model.preferences.overlayRegion.edge },
            set: { edge in
                var preference = model.preferences.overlayRegion
                preference.edge = edge
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private func shortcutBinding(_ action: GlobalShortcutAction) -> Binding<GlobalShortcutBinding> {
        Binding(
            get: { model.preferences.globalShortcuts[action] },
            set: { actions.onGlobalShortcutChanged(action, $0) }
        )
    }

    private var regionSpanBinding: Binding<OverlaySpan> {
        Binding(
            get: { model.preferences.overlayRegion.span },
            set: { span in
                var preference = model.preferences.overlayRegion
                preference.span = span
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var regionScreenBinding: Binding<String?> {
        Binding(
            get: { model.preferences.overlayRegion.screenIdentifier },
            set: { screenIdentifier in
                var preference = model.preferences.overlayRegion
                preference.screenIdentifier = screenIdentifier
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var deletionConfirmationPhrase: String {
        L10n.text("settings.account.delete.confirmation_phrase")
    }

    private var debugBuildStamp: String {
        let dirtySuffix = SideyBuildStamp.dirty
            ? " · \(InternalL10n.text("debug.build.dirty"))"
            : ""
        return "\(SideyBuildStamp.target) · \(SideyBuildStamp.commit.prefix(8))\(dirtySuffix)"
    }
}

private struct GlobalShortcutEditor: View {
    @Binding var binding: GlobalShortcutBinding
    let defaultBinding: GlobalShortcutBinding

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GlobalShortcutModifier.allCases) { modifier in
                Toggle(modifier.symbol, isOn: modifierBinding(modifier))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(Text(modifier.localizedTitle))
                    .accessibilityLabel(Text(modifier.localizedTitle))
            }
            Picker("settings.shortcuts.key.picker", selection: keyBinding) {
                ForEach(GlobalShortcutKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 64)

            Button {
                binding = defaultBinding
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(binding == defaultBinding)
            .help("settings.shortcuts.restore_default.help")
            .accessibilityLabel("settings.shortcuts.restore_default.accessibility")
        }
        .font(.body.monospaced())
    }

    private func modifierBinding(_ modifier: GlobalShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { binding.modifiers.contains(modifier) },
            set: { enabled in
                var updated = binding
                updated.modifiers.set(modifier, enabled: enabled)
                binding = updated
            }
        )
    }

    private var keyBinding: Binding<GlobalShortcutKey> {
        Binding(
            get: { binding.key },
            set: { key in
                var updated = binding
                updated.key = key
                binding = updated
            }
        )
    }
}

private extension GlobalShortcutAction {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .toggleQuietMode: "shortcut.action.quiet_mode"
        case .toggleComposer: "shortcut.action.composer"
        case .openHistory: "shortcut.action.history"
        case .toggleOverlay: "shortcut.action.overlay"
        }
    }
}

private extension GlobalShortcutModifier {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .control: "shortcut.modifier.control"
        case .option: "shortcut.modifier.option"
        case .shift: "shortcut.modifier.shift"
        case .command: "shortcut.modifier.command"
        }
    }
}

private extension OverlayEdge {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .bottom: "settings.placement.edge.bottom"
        case .left: "settings.placement.edge.left"
        case .right: "settings.placement.edge.right"
        case .top: "settings.placement.edge.top"
        }
    }
}

private extension OverlaySpan {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .third: "settings.placement.span.third"
        case .half: "settings.placement.span.half"
        case .full: "settings.placement.span.full"
        }
    }
}
