import Foundation

enum ConfigStore {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/quotabar/config.json")
    }

    static func load() -> AppSettings {
        var settings = AppSettings.default
        var shouldRewrite = false
        var hadGrokAccountsKey = false
        if let data = try? Data(contentsOf: configURL),
           let file = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            settings = file.settings
            migrateSecrets(from: file)
            shouldRewrite = file.glmApiKey != nil || file.cursorCookie != nil || file.chatgptCookie != nil
            hadGrokAccountsKey = file.grokAccounts != nil
        }
        let migratedLegacyChatGPT = migrateLegacyChatGPTAccounts(&settings)
        if migratedLegacyChatGPT {
            shouldRewrite = true
        }
        let migratedLegacyGrok = migrateLegacyGrokAccounts(&settings, hadGrokAccountsKey: hadGrokAccountsKey)
        if migratedLegacyGrok {
            shouldRewrite = true
        }
        let beforeSanitize = settings
        settings.sanitize()
        if shouldRewrite || settings != beforeSanitize {
            save(settings)
        }
        if configFileHasChatGPTAccounts() {
            let superseded = settings.chatgptAccounts.contains { account in
                KeychainStore.get(.chatgptAccountCookie(account.id)) != nil
                    || KeychainStore.get(.chatgptAccountJSON(account.id)) != nil
            }
            if superseded {
                KeychainStore.delete(.chatgptCookie)
                KeychainStore.delete(.chatgptJSON)
            }
        }
        if grokAccountsSupersedeLegacyToken(settings) {
            KeychainStore.delete(.grokOAuthToken)
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

    /// Moves the pre-multi-account ChatGPT cookie / JSON Keychain entries onto one
    /// account labeled "ChatGPT" so existing users keep their credentials.
    @discardableResult
    static func migrateLegacyChatGPTAccounts(_ settings: inout AppSettings) -> Bool {
        let legacyCookie = KeychainStore.get(.chatgptCookie)
        let legacyJSON = KeychainStore.get(.chatgptJSON)

        if settings.chatgptAccounts.isEmpty {
            guard legacyCookie != nil || legacyJSON != nil else { return false }
            let id = UUID()
            settings.chatgptAccounts = [ChatGPTAccount(id: id, label: "ChatGPT", enabled: true)]
            settings.selectedChatGPTAccountId = id
            copyLegacyChatGPTSecrets(cookie: legacyCookie, json: legacyJSON, to: id)
            return true
        }

        guard settings.chatgptAccounts.count == 1,
              let id = settings.chatgptAccounts.first?.id,
              legacyCookie != nil || legacyJSON != nil
        else { return false }

        let hasCookie = KeychainStore.get(.chatgptAccountCookie(id)) != nil
        let hasJSON = KeychainStore.get(.chatgptAccountJSON(id)) != nil
        var copied = false
        if !hasCookie, let legacyCookie {
            KeychainStore.set(legacyCookie, account: .chatgptAccountCookie(id))
            copied = true
        }
        if !hasJSON, let legacyJSON {
            KeychainStore.set(legacyJSON, account: .chatgptAccountJSON(id))
            copied = true
        }
        return copied
    }

    private static func configFileHasChatGPTAccounts() -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let file = try? JSONDecoder().decode(ConfigFile.self, from: data),
              let accounts = file.chatgptAccounts, !accounts.isEmpty
        else { return false }
        return true
    }

    private static func copyLegacyChatGPTSecrets(cookie: String?, json: String?, to id: UUID) {
        if let cookie {
            KeychainStore.set(cookie, account: .chatgptAccountCookie(id))
        }
        if let json {
            KeychainStore.set(json, account: .chatgptAccountJSON(id))
        }
    }

    /// Pre-multi-account Grok was one Keychain bearer plus optional `~/.grok/auth.json`.
    /// Missing `grokAccounts` (nil) migrates that into one account. An explicit empty
    /// array means the user deleted every Grok row and must not be recreated on launch.
    @discardableResult
    static func migrateLegacyGrokAccounts(_ settings: inout AppSettings, hadGrokAccountsKey: Bool) -> Bool {
        let legacyToken = KeychainStore.get(.grokOAuthToken)
        let ambient = GrokAuth.loadAuthFile()

        if !hadGrokAccountsKey, settings.grokAccounts.isEmpty {
            guard legacyToken != nil || ambient != nil else { return false }
            let id = UUID()
            let email = ambient?.email ?? AccountIdentity.fromToken(legacyToken ?? "")
            settings.grokAccounts = [
                GrokAccount(
                    id: id,
                    label: email ?? "Grok",
                    enabled: true,
                    email: email,
                    usesAmbientAuthFile: ambient != nil
                )
            ]
            settings.selectedGrokAccountId = id
            if let legacyToken {
                KeychainStore.set(legacyToken, account: .grokAccountOAuthToken(id))
            }
            return true
        }

        guard settings.grokAccounts.count == 1,
              let id = settings.grokAccounts.first?.id,
              let legacyToken
        else { return false }

        if KeychainStore.get(.grokAccountOAuthToken(id)) == nil {
            KeychainStore.set(legacyToken, account: .grokAccountOAuthToken(id))
            return true
        }
        return false
    }

    private static func grokAccountsSupersedeLegacyToken(_ settings: AppSettings) -> Bool {
        settings.grokAccounts.contains { account in
            KeychainStore.get(.grokAccountOAuthToken(account.id)) != nil
                || account.usesAmbientAuthFile
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
    var chatgptAccounts: [ChatGPTAccount]?
    var selectedChatGPTAccountId: UUID?
    var didIntroduceGrok: Bool?
    var opencodeGoAccounts: [OpenCodeGoAccount]?
    var selectedOpenCodeGoAccountId: UUID?
    var didIntroduceOpenCodeGo: Bool?
    var grokAccounts: [GrokAccount]?
    var selectedGrokAccountId: UUID?

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
        chatgptAccounts = settings.chatgptAccounts
        selectedChatGPTAccountId = settings.selectedChatGPTAccountId
        didIntroduceGrok = settings.didIntroduceGrok
        opencodeGoAccounts = settings.opencodeGoAccounts
        selectedOpenCodeGoAccountId = settings.selectedOpenCodeGoAccountId
        didIntroduceOpenCodeGo = settings.didIntroduceOpenCodeGo
        grokAccounts = settings.grokAccounts
        selectedGrokAccountId = settings.selectedGrokAccountId
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
        if let chatgptAccounts { value.chatgptAccounts = chatgptAccounts }
        if let selectedChatGPTAccountId { value.selectedChatGPTAccountId = selectedChatGPTAccountId }
        // Missing key = pre-Grok config. sanitize() appends Grok once.
        value.didIntroduceGrok = didIntroduceGrok ?? false
        if let opencodeGoAccounts { value.opencodeGoAccounts = opencodeGoAccounts }
        if let selectedOpenCodeGoAccountId { value.selectedOpenCodeGoAccountId = selectedOpenCodeGoAccountId }
        // Missing key = pre-OpenCode config. sanitize() appends OpenCode Go once.
        value.didIntroduceOpenCodeGo = didIntroduceOpenCodeGo ?? false
        if let grokAccounts { value.grokAccounts = grokAccounts }
        if let selectedGrokAccountId { value.selectedGrokAccountId = selectedGrokAccountId }
        return value
    }
}
