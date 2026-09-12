import AppKit

/// Opens the local Cursor.app so the user can sign in there.
/// There is no public Cursor OAuth / `cursor login` CLI — do not invent one.
enum CursorAppLauncher {
    static let websiteURL = URL(string: "https://cursor.com")!

    /// Official Mac build is still the Todesktop-wrapped Cursor.app.
    static let bundleIdentifiers = [
        "com.todesktop.230313mzl4w4u92"
    ]

    enum Outcome: Equatable {
        case launchedApp
        case openedWebsite
        case failed(String)
    }

    static func applicationURL(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        let homeApps = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Cursor.app")
        let candidates = [
            URL(fileURLWithPath: "/Applications/Cursor.app"),
            homeApps
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    @MainActor
    static func open() async -> Outcome {
        if let url = applicationURL() {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                return .launchedApp
            } catch {
                return openWebsiteFallback()
            }
        }
        return openWebsiteFallback()
    }

    private static func openWebsiteFallback() -> Outcome {
        if NSWorkspace.shared.open(websiteURL) {
            return .openedWebsite
        }
        return .failed("Cursor.app is not installed. Download it from cursor.com, sign in there, then Refresh.")
    }
}
