import Foundation

struct ChatGPTAccount: Equatable, Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var enabled: Bool
    var email: String?
    /// Private or ambient Codex home whose `auth.json` this account reads. Never written by QuotaBar.
    var codexHomePath: String?
    var usesAmbientCodexHome: Bool

    init(
        id: UUID = UUID(),
        label: String,
        enabled: Bool = true,
        email: String? = nil,
        codexHomePath: String? = nil,
        usesAmbientCodexHome: Bool = false
    ) {
        self.id = id
        self.label = label
        self.enabled = enabled
        self.email = email
        self.codexHomePath = codexHomePath
        self.usesAmbientCodexHome = usesAmbientCodexHome
    }

    enum CodingKeys: String, CodingKey {
        case id, label, enabled, email, codexHomePath, usesAmbientCodexHome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        email = try container.decodeIfPresent(String.self, forKey: .email)
        codexHomePath = try container.decodeIfPresent(String.self, forKey: .codexHomePath)
        usesAmbientCodexHome = try container.decodeIfPresent(Bool.self, forKey: .usesAmbientCodexHome) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(codexHomePath, forKey: .codexHomePath)
        try container.encode(usesAmbientCodexHome, forKey: .usesAmbientCodexHome)
    }

    var displayTitle: String {
        if let email, !email.isEmpty {
            return email
        }
        return label
    }
}

struct AppSettings: Equatable, Codable {
    var enabledProviders: [ProviderKind]
    var selectedProvider: ProviderKind
    var pollIntervalSeconds: Int
    var displayMode: DisplayMode
    var glmRegion: GLMRegion
    var previewFixtures: Bool
    var launchAtLogin: Bool
    var chatgptAccounts: [ChatGPTAccount]
    var selectedChatGPTAccountId: UUID?

    static let `default` = AppSettings(
        enabledProviders: ProviderKind.allCases,
        selectedProvider: .cursor,
        pollIntervalSeconds: 120,
        displayMode: .remaining,
        glmRegion: .global,
        previewFixtures: false,
        launchAtLogin: false,
        chatgptAccounts: [],
        selectedChatGPTAccountId: nil
    )

    var visibleProviders: [ProviderKind] {
        let enabled = enabledProviders
        return ProviderKind.allCases.filter { enabled.contains($0) }
    }

    var visibleChatGPTAccounts: [ChatGPTAccount] {
        let enabled = chatgptAccounts.filter(\.enabled)
        return enabled.isEmpty ? chatgptAccounts : enabled
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

        var seen = Set<UUID>()
        chatgptAccounts = chatgptAccounts.filter { account in
            if seen.contains(account.id) { return false }
            seen.insert(account.id)
            return true
        }
        for index in chatgptAccounts.indices {
            let trimmed = chatgptAccounts[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                chatgptAccounts[index].label = "ChatGPT"
            } else {
                chatgptAccounts[index].label = trimmed
            }
            if let email = chatgptAccounts[index].email?.trimmingCharacters(in: .whitespacesAndNewlines), email.isEmpty {
                chatgptAccounts[index].email = nil
            }
            if let home = chatgptAccounts[index].codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
                chatgptAccounts[index].codexHomePath = home.isEmpty ? nil : home
            }
        }

        let selectable = visibleChatGPTAccounts
        if let selected = selectedChatGPTAccountId, selectable.contains(where: { $0.id == selected }) {
            return
        }
        selectedChatGPTAccountId = selectable.first?.id
    }
}
