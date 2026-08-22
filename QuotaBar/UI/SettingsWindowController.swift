import AppKit
import SwiftUI

enum SettingsPresenter {
    @MainActor
    static func open() {
        // Custom controller only. There is no SwiftUI Settings scene —
        // that registered an empty window titled “QuotaBar Settings”.
        // Cmd+, / Settings selectors on AppDelegate and
        // QuotaBarApplication order this window front in an LSUIElement
        // accessory app. Do not call NSApplication.showSettingsWindow.
        SettingsWindowController.shared.show()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let view = SettingsView(store: AppStore.shared)
            .preferredColorScheme(.dark)
        let hosting = NSHostingController(rootView: view)
        hosting.view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: Theme.settingsColumnWidth, height: 720))
        window.contentMinSize = NSSize(width: Theme.settingsMinWidth, height: Theme.settingsMinHeight)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.backgroundNSColor
        window.titlebarAppearsTransparent = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window = window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.backgroundNSColor
        window.contentView?.appearance = NSAppearance(named: .darkAqua)
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
