import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let onboardingContentSize = CGSize(width: 960, height: 720)
    static let settingsContentSize = CGSize(width: 1000, height: 760)

    private let onClose: () -> Void

    init(model: AppModel, actions: SettingsActions = .empty, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let initialContentSize = model.preferences.onboardingComplete
            ? Self.settingsContentSize
            : Self.onboardingContentSize
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "\(AppPresentation.displayName) 설정"
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.minSize = NSSize(width: 860, height: 640)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsRootView(model: model, actions: actions)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func transitionFromOnboardingToSettings() {
        guard let window else { return }
        window.orderOut(nil)
        window.setContentSize(Self.settingsContentSize)
        window.center()
        show()
    }

    func transitionFromSettingsToOnboarding() {
        guard let window else { return }
        window.orderOut(nil)
        window.setContentSize(Self.onboardingContentSize)
        window.center()
        show()
    }

    var contentSize: CGSize {
        guard let window else { return .zero }
        return window.contentRect(forFrameRect: window.frame).size
    }

    func windowWillClose(_ notification: Notification) {
        // Do not change the app activation policy while AppKit is still closing
        // the key window. Finish the close transaction first so removing SIDEY
        // from the Dock cannot hand focus back to an app on another Space.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible != true else { return }
            self.onClose()
        }
    }
}
