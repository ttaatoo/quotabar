import SwiftUI

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI requires a Scene. Do not use `Settings { }` — that
        // registers an empty window titled "QuotaBar Settings".
        // Settings are SettingsWindowController via AppDelegate /
        // QuotaBarApplication ObjC Settings selectors.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}
