import SwiftUI

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live in SettingsWindowController. A SwiftUI Settings scene
        // registers `showSettingsWindow:` which can swallow the second click
        // without bringing that window forward (LSUIElement accessory app).
        Settings {
            EmptyView()
        }
    }
}
