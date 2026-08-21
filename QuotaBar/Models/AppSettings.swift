import Foundation

struct AppSettings: Equatable, Codable {
    var enabledProviders: [ProviderKind]
    var selectedProvider: ProviderKind
    var pollIntervalSeconds: Int
    var displayMode: DisplayMode
    var glmRegion: GLMRegion
    var previewFixtures: Bool
    var launchAtLogin: Bool

    static let `default` = AppSettings(
        enabledProviders: ProviderKind.allCases,
        selectedProvider: .cursor,
        pollIntervalSeconds: 120,
        displayMode: .remaining,
        glmRegion: .global,
        previewFixtures: false,
        launchAtLogin: false
    )

    var visibleProviders: [ProviderKind] {
        let enabled = enabledProviders
        return ProviderKind.allCases.filter { enabled.contains($0) }
    }

    mutating func sanitize() {
        if pollIntervalSeconds < 15 { pollIntervalSeconds = 15 }
        if pollIntervalSeconds > 3600 { pollIntervalSeconds = 3600 }
        if enabledProviders.isEmpty {
            enabledProviders = ProviderKind.allCases
        }
        if !enabledProviders.contains(selectedProvider) {
            selectedProvider = enabledProviders.first ?? .cursor
        }
    }
}
