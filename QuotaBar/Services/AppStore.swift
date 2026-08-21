import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings
    @Published var states: [ProviderKind: ProviderLoadState]
    @Published var chatgptStates: [UUID: ProviderLoadState] = [:]
    @Published var now: Date = Date()
    @Published var isRefreshing = false

    @Published var cursorCookie: String = ""
    @Published var chatgptCookies: [UUID: String] = [:]
    @Published var chatgptJSONs: [UUID: String] = [:]
    @Published var glmAPIKey: String = ""

    private var pollTimer: Timer?
    private var clockTimer: Timer?

    private init() {
        var loaded = ConfigStore.load()
        loaded.launchAtLogin = LaunchAtLogin.isEnabled
        settings = loaded
        states = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, .idle) })
        cursorCookie = KeychainStore.get(.cursorCookie) ?? ""
        glmAPIKey = KeychainStore.get(.glmAPIKey) ?? ""
        loadChatGPTSecrets()
    }

    var selected: ProviderKind { settings.selectedProvider }

    var visibleChatGPTAccounts: [ChatGPTAccount] {
        settings.visibleChatGPTAccounts
    }

    var selectedState: ProviderLoadState {
        if selected == .chatgpt {
            return aggregatedChatGPTState
        }
        return states[selected] ?? .idle
    }

    var cursorEmail: String? {
        states[.cursor]?.snapshot?.accountEmail
    }

    var hasAmbientCodexAccount: Bool {
        settings.chatgptAccounts.contains { account in
            account.usesAmbientCodexHome || isAmbientHome(account.codexHomePath)
        }
    }

    var chatgptDisplayRows: [ChatGPTDisplayRow] {
        if !settings.chatgptAccounts.isEmpty {
            return visibleChatGPTAccounts.map { account in
                ChatGPTDisplayRow(
                    id: account.id,
                    account: account,
                    state: chatgptStates[account.id] ?? .idle
                )
            }
        }
        let implicit = states[.chatgpt] ?? .idle
        switch implicit {
        case .ready, .loading, .failure:
            return [ChatGPTDisplayRow(id: Self.implicitChatGPTID, account: nil, state: implicit)]
        case .idle:
            if settings.previewFixtures {
                return [ChatGPTDisplayRow(id: Self.implicitChatGPTID, account: nil, state: implicit)]
            }
            return []
        case .signedOut:
            return []
        }
    }

    private var aggregatedChatGPTState: ProviderLoadState {
        if settings.chatgptAccounts.isEmpty {
            return chatGPTState(for: nil)
        }
        let rows = visibleChatGPTAccounts.map { chatgptStates[$0.id] ?? .idle }
        if rows.isEmpty {
            return .signedOut(ProviderKind.chatgpt.signInHint)
        }
        let ready = rows.compactMap { state -> UsageSnapshot? in
            if case .ready(let snapshot) = state { return snapshot }
            return nil
        }
        if let combined = combineChatGPTSnapshots(ready) {
            return .ready(combined)
        }
        if rows.contains(where: { if case .loading = $0 { return true }; return false }) {
            return .loading
        }
        if rows.allSatisfy(\.isSignedOut) {
            return .signedOut(ProviderKind.chatgpt.signInHint)
        }
        if let failure = rows.compactMap({ state -> String? in
            if case .failure(let message) = state { return message }
            return nil
        }).first {
            return .failure(failure)
        }
        return .idle
    }

    private func combineChatGPTSnapshots(_ snapshots: [UsageSnapshot]) -> UsageSnapshot? {
        guard let first = snapshots.first else { return nil }
        if snapshots.count == 1 { return first }
        let remaining = snapshots.compactMap(\.mostConstrainedRemaining)
        guard let lowest = remaining.min(),
              let chosen = snapshots.first(where: { $0.mostConstrainedRemaining == lowest })
        else { return first }
        var combined = chosen
        combined.accountEmail = nil
        combined.planName = nil
        combined.extraFooter = nil
        return combined
    }

    var visibleProviders: [ProviderKind] {
        let visible = settings.visibleProviders
        return visible.isEmpty ? ProviderKind.allCases : visible
    }

    func start() {
        restartPolling()
        Task { await refreshAll() }
    }

    func restartPolling() {
        pollTimer?.invalidate()
        let interval = TimeInterval(settings.pollIntervalSeconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in
                await self?.refreshAll()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func startClock() {
        clockTimer?.invalidate()
        now = Date()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in
                self?.now = Date()
            }
        }
        if let clockTimer {
            RunLoop.main.add(clockTimer, forMode: .common)
        }
    }

    func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    func select(_ provider: ProviderKind) {
        guard settings.enabledProviders.contains(provider) else { return }
        settings.selectedProvider = provider
        persistSettings()
    }

    func selectChatGPTAccount(_ id: UUID) {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        settings.selectedChatGPTAccountId = id
        persistSettings()
    }

    func setEnabled(_ provider: ProviderKind, enabled: Bool) {
        if enabled {
            if !settings.enabledProviders.contains(provider) {
                settings.enabledProviders.append(provider)
            }
        } else {
            settings.enabledProviders.removeAll { $0 == provider }
            if settings.enabledProviders.isEmpty {
                settings.enabledProviders = [provider]
                return
            }
            if settings.selectedProvider == provider {
                settings.selectedProvider = settings.enabledProviders[0]
            }
        }
        persistSettings()
        Task { await refresh(provider) }
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        settings.sanitize()
        persistSettings()
        restartPolling()
    }

    func persistSecrets() {
        KeychainStore.set(cursorCookie, account: .cursorCookie)
        KeychainStore.set(glmAPIKey, account: .glmAPIKey)
        persistChatGPTSecrets()
    }

    private func persistChatGPTSecrets() {
        for account in settings.chatgptAccounts {
            KeychainStore.set(chatgptCookies[account.id], account: .chatgptAccountCookie(account.id))
            KeychainStore.set(chatgptJSONs[account.id], account: .chatgptAccountJSON(account.id))
        }
    }

    func setChatGPTCookie(_ value: String, for id: UUID) {
        chatgptCookies[id] = value
        KeychainStore.set(value, account: .chatgptAccountCookie(id))
    }

    func setChatGPTJSON(_ value: String, for id: UUID) {
        chatgptJSONs[id] = value
        KeychainStore.set(value, account: .chatgptAccountJSON(id))
    }

    func persistSettings() {
        settings.sanitize()
        ConfigStore.save(settings)
    }

    func nextChatGPTLabel() -> String {
        let existing = Set(settings.chatgptAccounts.map(\.label))
        if !existing.contains("ChatGPT") { return "ChatGPT" }
        var index = 2
        while existing.contains("ChatGPT \(index)") {
            index += 1
        }
        return "ChatGPT \(index)"
    }

    @discardableResult
    func addChatGPTAccount(label: String? = nil) -> UUID {
        let id = UUID()
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? nextChatGPTLabel() : trimmed
        settings.chatgptAccounts.append(ChatGPTAccount(id: id, label: resolved, enabled: true))
        if settings.selectedChatGPTAccountId == nil {
            settings.selectedChatGPTAccountId = id
        }
        chatgptCookies[id] = ""
        chatgptJSONs[id] = ""
        chatgptStates[id] = .idle
        persistSettings()
        return id
    }

    /// Create-on-success (or refresh an existing email's cookie). Label is the
    /// session email when present; otherwise ChatGPT / ChatGPT 2. Rename stays
    /// user-editable and is not overwritten on a later sign-in of the same email.
    @discardableResult
    func upsertChatGPTAccount(cookie: String, email: String?) -> UUID {
        let trimmedCookie = ChatGPTClient.normalizeCookie(cookie)
            ?? cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValue: String?
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            emailValue = email
        } else {
            emailValue = nil
        }

        if let emailValue,
           let existing = settings.chatgptAccounts.first(where: {
               $0.email?.caseInsensitiveCompare(emailValue) == .orderedSame
           }) {
            setChatGPTCookie(trimmedCookie, for: existing.id)
            recordChatGPTEmail(emailValue, for: existing.id)
            settings.selectedChatGPTAccountId = existing.id
            persistSettings()
            Task { await refreshChatGPTAccount(existing.id, userInitiated: true) }
            return existing.id
        }

        let label = emailValue ?? nextChatGPTLabel()
        let id = addChatGPTAccount(label: label)
        if let emailValue, let index = settings.chatgptAccounts.firstIndex(where: { $0.id == id }) {
            settings.chatgptAccounts[index].email = emailValue
        }
        settings.selectedChatGPTAccountId = id
        setChatGPTCookie(trimmedCookie, for: id)
        persistSettings()
        Task { await refreshChatGPTAccount(id, userInitiated: true) }
        return id
    }

    func renameChatGPTAccount(_ id: UUID, to label: String) {
        guard let index = settings.chatgptAccounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.chatgptAccounts[index].label = trimmed.isEmpty ? "ChatGPT" : trimmed
        persistSettings()
    }

    func deleteChatGPTAccount(_ id: UUID) {
        let homePath = settings.chatgptAccounts.first(where: { $0.id == id })?.codexHomePath
        let ambient = settings.chatgptAccounts.first(where: { $0.id == id })?.usesAmbientCodexHome ?? false
        settings.chatgptAccounts.removeAll { $0.id == id }
        chatgptCookies[id] = nil
        chatgptJSONs[id] = nil
        chatgptStates[id] = nil
        KeychainStore.delete(.chatgptAccountCookie(id))
        KeychainStore.delete(.chatgptAccountJSON(id))
        if !ambient {
            CodexCLIAuth.removeManagedHomeIfSafe(homePath)
        }
        if settings.selectedChatGPTAccountId == id {
            settings.selectedChatGPTAccountId = settings.visibleChatGPTAccounts.first?.id
                ?? settings.chatgptAccounts.first?.id
        }
        persistSettings()
    }

    @discardableResult
    func importAmbientCodexAccountIfAvailable() -> UUID? {
        if hasAmbientCodexAccount { return nil }
        let home = CodexCLIAuth.defaultHomeURL()
        guard let tokens = CodexCLIAuth.read(home: home) else { return nil }
        return upsertChatGPTAccountFromCodexHome(
            homePath: home.path,
            email: tokens.email,
            ambient: true
        )
    }

    @discardableResult
    func upsertChatGPTAccountFromCodexHome(
        homePath: String,
        email: String?,
        ambient: Bool
    ) -> UUID? {
        let trimmedEmail = CodexCLIAuth.usableEmail(email)
        let standardizedHome = CodexCLIAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath

        if let trimmedEmail,
           let existing = settings.chatgptAccounts.first(where: {
               $0.email?.caseInsensitiveCompare(trimmedEmail) == .orderedSame
           }) {
            if let index = settings.chatgptAccounts.firstIndex(where: { $0.id == existing.id }) {
                let previousHome = settings.chatgptAccounts[index].codexHomePath
                settings.chatgptAccounts[index].email = trimmedEmail
                settings.chatgptAccounts[index].codexHomePath = standardizedHome
                settings.chatgptAccounts[index].usesAmbientCodexHome = ambient
                if previousHome != standardizedHome {
                    CodexCLIAuth.removeManagedHomeIfSafe(previousHome)
                }
            }
            settings.selectedChatGPTAccountId = existing.id
            persistSettings()
            Task { await refreshChatGPTAccount(existing.id, userInitiated: true) }
            return existing.id
        }

        let label = trimmedEmail ?? nextChatGPTLabel()
        let id = addChatGPTAccount(label: label)
        if let index = settings.chatgptAccounts.firstIndex(where: { $0.id == id }) {
            settings.chatgptAccounts[index].email = trimmedEmail
            settings.chatgptAccounts[index].codexHomePath = standardizedHome
            settings.chatgptAccounts[index].usesAmbientCodexHome = ambient
        }
        settings.selectedChatGPTAccountId = id
        persistSettings()
        Task { await refreshChatGPTAccount(id, userInitiated: true) }
        return id
    }

    private func isAmbientHome(_ path: String?) -> Bool {
        guard let url = CodexCLIAuth.homeURL(path: path) else { return false }
        return CodexCLIAuth.isAmbientHome(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if LaunchAtLogin.setEnabled(enabled) {
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        } else {
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
        persistSettings()
    }

    func openSettings() {
        SettingsPresenter.open()
    }

    func refreshSelected() async {
        let alreadyRefreshing = isRefreshing
        isRefreshing = true
        defer {
            if !alreadyRefreshing {
                isRefreshing = false
            }
        }
        // Let SwiftUI paint the spinner before a fast fetch coalesces state updates.
        await Task.yield()
        if selected == .chatgpt {
            await refreshAllChatGPTAccounts(userInitiated: true)
            return
        }
        await refresh(selected)
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        for provider in visibleProviders {
            await refresh(provider)
        }
    }

    func refresh(_ provider: ProviderKind) async {
        if provider == .chatgpt {
            await refreshAllChatGPTAccounts(userInitiated: false)
            return
        }
        states[provider] = .loading
        do {
            let snapshot: UsageSnapshot
            if settings.previewFixtures {
                snapshot = try FixtureLoader.load(provider, now: Date())
            } else {
                snapshot = try await fetchLive(provider)
            }
            states[provider] = .ready(snapshot)
        } catch let error as QuotaError {
            if error.isAuthFailure {
                states[provider] = .signedOut(error.errorDescription ?? provider.signInHint)
            } else {
                states[provider] = .failure(error.errorDescription ?? "Something went wrong.")
            }
        } catch {
            states[provider] = .failure(error.localizedDescription)
        }
    }

    private func refreshAllChatGPTAccounts(userInitiated: Bool) async {
        let accounts = settings.chatgptAccounts
        if accounts.isEmpty {
            if settings.previewFixtures {
                await refreshChatGPTPreviewFallback(userInitiated: userInitiated)
            } else {
                await refreshImplicitChatGPT(userInitiated: userInitiated)
            }
            return
        }
        for account in accounts {
            await refreshChatGPTAccount(account.id, userInitiated: userInitiated)
        }
    }

    private func refreshChatGPTAccount(_ id: UUID, userInitiated: Bool) async {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        let current = chatgptStates[id] ?? .idle
        if userInitiated || shouldShowLoading(current) {
            chatgptStates[id] = .loading
        }

        do {
            let snapshot: UsageSnapshot
            if settings.previewFixtures {
                snapshot = try FixtureLoader.load(.chatgpt, now: Date())
            } else {
                snapshot = try await ChatGPTClient.fetch(
                    cookie: emptyToNil(chatgptCookies[id, default: ""]),
                    pastedJSON: emptyToNil(chatgptJSONs[id, default: ""]),
                    codexHomePath: settings.chatgptAccounts.first(where: { $0.id == id })?.codexHomePath,
                    allowAmbientCodex: false
                )
            }
            chatgptStates[id] = .ready(snapshot)
            recordChatGPTEmail(snapshot.accountEmail, for: id)
        } catch let error as QuotaError {
            if error.isAuthFailure {
                chatgptStates[id] = .signedOut(error.errorDescription ?? ProviderKind.chatgpt.signInHint)
            } else {
                chatgptStates[id] = .failure(error.errorDescription ?? "Something went wrong.")
            }
        } catch {
            chatgptStates[id] = .failure(error.localizedDescription)
        }
    }

    /// Uses ~/.codex/auth.json when no ChatGPT account has been added yet.
    /// Does not persist a new account on each launch.
    private func refreshImplicitChatGPT(userInitiated: Bool) async {
        let current = states[.chatgpt] ?? .idle
        if userInitiated || shouldShowLoading(current) {
            states[.chatgpt] = .loading
        }
        do {
            let snapshot = try await ChatGPTClient.fetch(
                cookie: nil,
                pastedJSON: nil,
                allowAmbientCodex: true
            )
            states[.chatgpt] = .ready(snapshot)
        } catch let error as QuotaError {
            if error.isAuthFailure {
                states[.chatgpt] = .signedOut(error.errorDescription ?? ProviderKind.chatgpt.signInHint)
            } else {
                states[.chatgpt] = .failure(error.errorDescription ?? "Something went wrong.")
            }
        } catch {
            states[.chatgpt] = .failure(error.localizedDescription)
        }
    }

    private func refreshChatGPTPreviewFallback(userInitiated: Bool) async {
        let current = states[.chatgpt] ?? .idle
        if userInitiated || shouldShowLoading(current) {
            states[.chatgpt] = .loading
        }
        do {
            states[.chatgpt] = .ready(try FixtureLoader.load(.chatgpt, now: Date()))
        } catch {
            states[.chatgpt] = .failure(error.localizedDescription)
        }
    }

    private func chatGPTState(for id: UUID?) -> ProviderLoadState {
        if settings.chatgptAccounts.isEmpty {
            if settings.previewFixtures {
                return states[.chatgpt] ?? .idle
            }
            let implicit = states[.chatgpt] ?? .idle
            switch implicit {
            case .idle:
                return .signedOut(ProviderKind.chatgpt.signInHint)
            default:
                return implicit
            }
        }
        guard let id, settings.chatgptAccounts.contains(where: { $0.id == id }) else {
            return .signedOut(ProviderKind.chatgpt.signInHint)
        }
        return chatgptStates[id] ?? .idle
    }

    private func shouldShowLoading(_ state: ProviderLoadState) -> Bool {
        switch state {
        case .idle, .loading:
            return true
        case .ready, .signedOut, .failure:
            return false
        }
    }

    private func recordChatGPTEmail(_ email: String?, for id: UUID) {
        let trimmed = CodexCLIAuth.usableEmail(email)
        guard let trimmed else { return }
        guard let index = settings.chatgptAccounts.firstIndex(where: { $0.id == id }) else { return }
        guard settings.chatgptAccounts[index].email != trimmed else { return }
        settings.chatgptAccounts[index].email = trimmed
        persistSettings()
    }

    private func loadChatGPTSecrets() {
        for account in settings.chatgptAccounts {
            chatgptCookies[account.id] = KeychainStore.get(.chatgptAccountCookie(account.id)) ?? ""
            chatgptJSONs[account.id] = KeychainStore.get(.chatgptAccountJSON(account.id)) ?? ""
            chatgptStates[account.id] = .idle
        }
    }

    private func fetchLive(_ provider: ProviderKind) async throws -> UsageSnapshot {
        switch provider {
        case .cursor:
            return try await CursorClient.fetch(cookie: emptyToNil(cursorCookie))
        case .chatgpt:
            guard let id = settings.selectedChatGPTAccountId else {
                return try await ChatGPTClient.fetch(cookie: nil, pastedJSON: nil, allowAmbientCodex: true)
            }
            return try await ChatGPTClient.fetch(
                cookie: emptyToNil(chatgptCookies[id, default: ""]),
                pastedJSON: emptyToNil(chatgptJSONs[id, default: ""]),
                codexHomePath: settings.chatgptAccounts.first(where: { $0.id == id })?.codexHomePath,
                allowAmbientCodex: false
            )
        case .glm:
            return try await GLMClient.fetch(apiKey: emptyToNil(glmAPIKey), region: settings.glmRegion)
        }
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static let implicitChatGPTID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

struct ChatGPTDisplayRow: Identifiable, Equatable {
    var id: UUID
    var account: ChatGPTAccount?
    var state: ProviderLoadState
}
