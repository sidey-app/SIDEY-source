import AppKit

enum KeychainTransitionNotice {
    static var message: String { L10n.text("keychain.transition.message") }

    static var migrationExplanation: String {
        L10n.text("keychain.transition.migration_explanation")
    }

    static var privacyExplanation: String {
        L10n.text("keychain.transition.privacy_explanation")
    }

    @MainActor
    static func present() -> Bool {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = "\(migrationExplanation)\n\n\(privacyExplanation)"
        alert.addButton(withTitle: L10n.text("common.continue"))
        alert.addButton(withTitle: L10n.text("keychain.transition.quit"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
