import Foundation

enum ConfigStore {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quotabar/config.json")
    }

    static func load() -> AppSettings {
        var settings = AppSettings.default
        var shouldRewrite = false
        if let data = try? Data(contentsOf: configURL),
           let file = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            settings = file.settings
            migrateSecrets(from: file)
            shouldRewrite = file.glmApiKey != nil || file.cursorCookie != nil || file.chatgptCookie != nil
        }
        settings.sanitize()
        if shouldRewrite {
            save(settings)
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        var cleaned = settings
        cleaned.sanitize()
        let file = ConfigFile(settings: cleaned)
        let directory = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: configURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configURL.path
            )
        } catch {
            // Settings still live in memory / Keychain; a config write failure is not fatal.
        }
    }

    static func readLegacyGLMKey() -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in ["glmApiKey", "zAiApiKey", "apiKey"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func migrateSecrets(from file: ConfigFile) {
        if let key = file.glmApiKey, KeychainStore.get(.glmAPIKey) == nil {
            KeychainStore.set(key, account: .glmAPIKey)
        }
        if let cookie = file.cursorCookie, KeychainStore.get(.cursorCookie) == nil {
            KeychainStore.set(cookie, account: .cursorCookie)
        }
        if let cookie = file.chatgptCookie, KeychainStore.get(.chatgptCookie) == nil {
            KeychainStore.set(cookie, account: .chatgptCookie)
        }
    }
}

private struct ConfigFile: Codable {
    var enabledProviders: [ProviderKind]?
    var selectedProvider: ProviderKind?
    var pollIntervalSeconds: Int?
    var displayMode: DisplayMode?
    var glmRegion: GLMRegion?
    var previewFixtures: Bool?
    var launchAtLogin: Bool?

    /// Legacy / imported secrets. Written as null after migration.
    var glmApiKey: String?
    var cursorCookie: String?
    var chatgptCookie: String?

    init(settings: AppSettings) {
        enabledProviders = settings.enabledProviders
        selectedProvider = settings.selectedProvider
        pollIntervalSeconds = settings.pollIntervalSeconds
        displayMode = settings.displayMode
        glmRegion = settings.glmRegion
        previewFixtures = settings.previewFixtures
        launchAtLogin = settings.launchAtLogin
        glmApiKey = nil
        cursorCookie = nil
        chatgptCookie = nil
    }

    var settings: AppSettings {
        var value = AppSettings.default
        if let enabledProviders { value.enabledProviders = enabledProviders }
        if let selectedProvider { value.selectedProvider = selectedProvider }
        if let pollIntervalSeconds { value.pollIntervalSeconds = pollIntervalSeconds }
        if let displayMode { value.displayMode = displayMode }
        if let glmRegion { value.glmRegion = glmRegion }
        if let previewFixtures { value.previewFixtures = previewFixtures }
        if let launchAtLogin { value.launchAtLogin = launchAtLogin }
        return value
    }
}
