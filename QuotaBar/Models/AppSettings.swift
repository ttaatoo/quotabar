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

struct OpenCodeGoAccount: Equatable, Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var enabled: Bool
    var email: String?

    init(
        id: UUID = UUID(),
        label: String,
        enabled: Bool = true,
        email: String? = nil
    ) {
        self.id = id
        self.label = label
        self.enabled = enabled
        self.email = email
    }

    enum CodingKeys: String, CodingKey {
        case id, label, enabled, email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(email, forKey: .email)
    }

    var displayTitle: String {
        if let email, !email.isEmpty {
            return email
        }
        return label
    }
}

struct GrokAccount: Equatable, Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var enabled: Bool
    var email: String?
    /// Reads `~/.grok/auth.json` (or `$GROK_HOME/auth.json`). Never written by QuotaBar.
    var usesAmbientAuthFile: Bool
    /// Private or pinned Grok home. Extra accounts use Application Support
    /// `managed-grok-homes/<uuid>` so ambient auth.json is not overwritten.
    var grokHomePath: String?

    init(
        id: UUID = UUID(),
        label: String,
        enabled: Bool = true,
        email: String? = nil,
        usesAmbientAuthFile: Bool = false,
        grokHomePath: String? = nil
    ) {
        self.id = id
        self.label = label
        self.enabled = enabled
        self.email = email
        self.usesAmbientAuthFile = usesAmbientAuthFile
        self.grokHomePath = grokHomePath
    }

    enum CodingKeys: String, CodingKey {
        case id, label, enabled, email, usesAmbientAuthFile, grokHomePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        email = try container.decodeIfPresent(String.self, forKey: .email)
        usesAmbientAuthFile = try container.decodeIfPresent(Bool.self, forKey: .usesAmbientAuthFile) ?? false
        grokHomePath = try container.decodeIfPresent(String.self, forKey: .grokHomePath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(usesAmbientAuthFile, forKey: .usesAmbientAuthFile)
        try container.encodeIfPresent(grokHomePath, forKey: .grokHomePath)
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
    /// Last real provider for the menu bar and Settings first-open. Never `.all`.
    var selectedProvider: ProviderKind
    /// Popover landing tab. Missing config key decodes as All.
    var popoverTab: PopoverTab
    var pollIntervalSeconds: Int
    var displayMode: DisplayMode
    var glmRegion: GLMRegion
    var previewFixtures: Bool
    var launchAtLogin: Bool
    var chatgptAccounts: [ChatGPTAccount]
    /// ChatGPT account whose remaining % is shown in the menu bar.
    var selectedChatGPTAccountId: UUID?
    /// One-shot so existing 0.0.6 configs gain Grok without re-enabling it after the user hides it.
    var didIntroduceGrok: Bool
    var opencodeGoAccounts: [OpenCodeGoAccount]
    /// OpenCode Go account whose remaining % is shown in the menu bar.
    var selectedOpenCodeGoAccountId: UUID?
    /// One-shot so existing 0.0.12 configs gain OpenCode Go without re-enabling it after the user hides it.
    var didIntroduceOpenCodeGo: Bool
    var grokAccounts: [GrokAccount]
    /// Grok account whose remaining % is shown in the menu bar.
    var selectedGrokAccountId: UUID?

    static let `default` = AppSettings(
        enabledProviders: ProviderKind.allCases,
        selectedProvider: .cursor,
        popoverTab: .all,
        pollIntervalSeconds: 120,
        displayMode: .remaining,
        glmRegion: .global,
        previewFixtures: false,
        launchAtLogin: false,
        chatgptAccounts: [],
        selectedChatGPTAccountId: nil,
        didIntroduceGrok: true,
        opencodeGoAccounts: [],
        selectedOpenCodeGoAccountId: nil,
        didIntroduceOpenCodeGo: true,
        grokAccounts: [],
        selectedGrokAccountId: nil
    )

    var visibleProviders: [ProviderKind] {
        let enabled = enabledProviders
        return ProviderKind.allCases.filter { enabled.contains($0) }
    }

    var visibleChatGPTAccounts: [ChatGPTAccount] {
        let enabled = chatgptAccounts.filter(\.enabled)
        return enabled.isEmpty ? chatgptAccounts : enabled
    }

    var visibleOpenCodeGoAccounts: [OpenCodeGoAccount] {
        let enabled = opencodeGoAccounts.filter(\.enabled)
        return enabled.isEmpty ? opencodeGoAccounts : enabled
    }

    var visibleGrokAccounts: [GrokAccount] {
        let enabled = grokAccounts.filter(\.enabled)
        return enabled.isEmpty ? grokAccounts : enabled
    }

    mutating func sanitize() {
        if pollIntervalSeconds < 15 { pollIntervalSeconds = 15 }
        if pollIntervalSeconds > 3600 { pollIntervalSeconds = 3600 }
        if enabledProviders.isEmpty {
            enabledProviders = ProviderKind.allCases
        }
        if !didIntroduceGrok {
            if !enabledProviders.contains(.grok) {
                enabledProviders.append(.grok)
            }
            didIntroduceGrok = true
        }
        if !didIntroduceOpenCodeGo {
            if !enabledProviders.contains(.opencodeGo) {
                enabledProviders.append(.opencodeGo)
            }
            didIntroduceOpenCodeGo = true
        }
        if !enabledProviders.contains(selectedProvider) {
            selectedProvider = enabledProviders.first ?? .cursor
        }
        if case .provider(let tab) = popoverTab, !enabledProviders.contains(tab) {
            popoverTab = .all
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

        var seenOpenCode = Set<UUID>()
        opencodeGoAccounts = opencodeGoAccounts.filter { account in
            if seenOpenCode.contains(account.id) { return false }
            seenOpenCode.insert(account.id)
            return true
        }
        for index in opencodeGoAccounts.indices {
            let trimmed = opencodeGoAccounts[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                opencodeGoAccounts[index].label = "OpenCode"
            } else {
                opencodeGoAccounts[index].label = trimmed
            }
            if let email = opencodeGoAccounts[index].email?.trimmingCharacters(in: .whitespacesAndNewlines), email.isEmpty {
                opencodeGoAccounts[index].email = nil
            }
        }

        var seenGrok = Set<UUID>()
        grokAccounts = grokAccounts.filter { account in
            if seenGrok.contains(account.id) { return false }
            seenGrok.insert(account.id)
            return true
        }
        for index in grokAccounts.indices {
            let trimmed = grokAccounts[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                grokAccounts[index].label = "Grok"
            } else {
                grokAccounts[index].label = trimmed
            }
            if let email = grokAccounts[index].email?.trimmingCharacters(in: .whitespacesAndNewlines), email.isEmpty {
                grokAccounts[index].email = nil
            }
            if let home = grokAccounts[index].grokHomePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
                grokAccounts[index].grokHomePath = home.isEmpty ? nil : home
            }
        }

        resolveSelectedChatGPTAccount()
        resolveSelectedOpenCodeGoAccount()
        resolveSelectedGrokAccount()
    }

    /// Keeps `selectedChatGPTAccountId` on a still-visible account.
    /// `preferred` is typically signed-in IDs in display order, used only when
    /// the stored selection is missing (deleted, disabled, or never set).
    mutating func resolveSelectedChatGPTAccount(preferring preferred: [UUID] = []) {
        let selectable = visibleChatGPTAccounts
        if let selected = selectedChatGPTAccountId, selectable.contains(where: { $0.id == selected }) {
            return
        }
        if let match = selectable.first(where: { preferred.contains($0.id) }) {
            selectedChatGPTAccountId = match.id
            return
        }
        selectedChatGPTAccountId = selectable.first?.id
    }

    mutating func resolveSelectedOpenCodeGoAccount(preferring preferred: [UUID] = []) {
        let selectable = visibleOpenCodeGoAccounts
        if let selected = selectedOpenCodeGoAccountId, selectable.contains(where: { $0.id == selected }) {
            return
        }
        if let match = selectable.first(where: { preferred.contains($0.id) }) {
            selectedOpenCodeGoAccountId = match.id
            return
        }
        selectedOpenCodeGoAccountId = selectable.first?.id
    }

    mutating func resolveSelectedGrokAccount(preferring preferred: [UUID] = []) {
        let selectable = visibleGrokAccounts
        if let selected = selectedGrokAccountId, selectable.contains(where: { $0.id == selected }) {
            return
        }
        if let match = selectable.first(where: { preferred.contains($0.id) }) {
            selectedGrokAccountId = match.id
            return
        }
        selectedGrokAccountId = selectable.first?.id
    }
}
