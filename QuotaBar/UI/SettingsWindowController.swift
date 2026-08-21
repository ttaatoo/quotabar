import AppKit
import SwiftUI

enum SettingsPresenter {
    @MainActor
    static func open() {
        // Always the custom controller. `showSettingsWindow:` can return true
        // for the unused SwiftUI Settings scene without ordering this window
        // front — a second click then does nothing in an LSUIElement app.
        SettingsWindowController.shared.show()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let view = SettingsView(store: AppStore.shared)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: Theme.settingsColumnWidth, height: 720))
        window.contentMinSize = NSSize(width: Theme.settingsMinWidth, height: Theme.settingsMinHeight)
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
