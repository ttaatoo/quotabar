import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings
    @Published var states: [ProviderKind: ProviderLoadState]
    @Published var chatgptStates: [UUID: ProviderLoadState] = [:]
    @Published var opencodeGoStates: [UUID: ProviderLoadState] = [:]
    @Published var grokStates: [UUID: ProviderLoadState] = [:]
    @Published var now: Date = Date()
    @Published var isRefreshing = false
    private let refreshCoordinator = RefreshCoordinator()
    private var consecutivePollFailures = 0
    private var lastScheduledPollAt: Date?

    @Published var cursorCookie: String = ""
    @Published var chatgptCookies: [UUID: String] = [:]
    @Published var chatgptJSONs: [UUID: String] = [:]
    @Published var glmAPIKey: String = ""
    @Published var opencodeGoAPIKeys: [UUID: String] = [:]
    @Published var grokTokens: [UUID: String] = [:]

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
        loadOpenCodeGoSecrets()
        loadGrokSecrets()
    }

    var selected: ProviderKind { settings.selectedProvider }

    var popoverTab: PopoverTab { settings.popoverTab }

    var popoverTabs: [PopoverTab] {
        [.all] + visibleProviders.map { .provider($0) }
    }

    var visibleChatGPTAccounts: [ChatGPTAccount] {
        settings.visibleChatGPTAccounts
    }

    var selectedState: ProviderLoadState {
        providerState(selected)
    }

    func providerState(_ provider: ProviderKind) -> ProviderLoadState {
        switch provider {
        case .chatgpt:
            return activeChatGPTState
        case .opencodeGo:
            return activeOpenCodeGoState
        case .grok:
            return activeGrokState
        case .cursor, .glm:
            return states[provider] ?? .idle
        }
    }

    /// Card in the ChatGPT tab that is active for the menu bar.
    /// Implicit / empty ChatGPT (no saved accounts) has a single card that is active.
    func isActiveAccountCard(_ cardID: String) -> Bool {
        switch selected {
        case .chatgpt:
            return isActiveChatGPTCard(cardID)
        case .opencodeGo:
            return isActiveOpenCodeGoCard(cardID)
        case .grok:
            return isActiveGrokCard(cardID)
        default:
            return false
        }
    }

    func activateAccountCard(_ cardID: String) {
        switch selected {
        case .chatgpt:
            activateChatGPTCard(cardID)
        case .opencodeGo:
            activateOpenCodeGoCard(cardID)
        case .grok:
            activateGrokCard(cardID)
        default:
            break
        }
    }

    func isActiveChatGPTCard(_ cardID: String) -> Bool {
        guard selected == .chatgpt else { return false }
        if settings.chatgptAccounts.isEmpty {
            return true
        }
        guard let active = activeChatGPTAccountId else { return false }
        return cardID == active.uuidString
    }

    func activateChatGPTCard(_ cardID: String) {
        guard selected == .chatgpt else { return }
        guard let id = UUID(uuidString: cardID) else { return }
        selectChatGPTAccount(id)
    }

    var cursorEmail: String? {
        states[.cursor]?.snapshot?.accountEmail
    }

    var grokEmail: String? {
        if let id = activeGrokAccountId {
            return grokDisplayTitle(for: id)
        }
        return states[.grok]?.snapshot?.accountEmail
            ?? GrokAuth.loadAuthFile()?.email
    }

    var glmIdentity: String? {
        states[.glm]?.snapshot?.accountEmail
            ?? AccountIdentity.fromToken(glmAPIKey)
    }

    /// One card per ChatGPT / OpenCode / Grok account; Cursor / GLM are a single card each.
    var accountCards: [AccountCardRow] {
        accountCards(for: selected)
    }

    /// Same rows the single-provider tab already shows. Overall reuses this —
    /// it does not fetch or cache a second copy of usage state.
    func accountCards(for provider: ProviderKind) -> [AccountCardRow] {
        switch provider {
        case .chatgpt:
            return chatgptDisplayRows.map { row in
                let credentials: Bool
                if let account = row.account {
                    credentials = hasChatGPTCredentials(account.id)
                } else {
                    credentials = CodexCLIAuth.read() != nil
                }
                return AccountCardRow(
                    id: row.id.uuidString,
                    email: row.account?.email ?? row.state.snapshot?.accountEmail,
                    fallbackTitle: row.account?.label ?? "Email unknown",
                    state: row.state,
                    hasCredentials: credentials,
                    recoveryTitle: ChatGPTAccountIdentity.Recovery.action(for: row.state).buttonTitle
                )
            }
        case .opencodeGo:
            return opencodeGoDisplayRows.map { row in
                let credentials: Bool
                if let account = row.account {
                    credentials = hasOpenCodeGoCredentials(account.id)
                } else {
                    credentials = OpenCodeGoClient.resolveToken(explicit: nil) != nil
                }
                return AccountCardRow(
                    id: row.id.uuidString,
                    email: row.account?.email ?? row.state.snapshot?.accountEmail,
                    fallbackTitle: row.account?.label ?? ambientOpenCodeGoTitle,
                    state: row.state,
                    hasCredentials: credentials,
                    recoveryTitle: "Retry"
                )
            }
        case .grok:
            return grokDisplayRows.map { row in
                let credentials: Bool
                if let account = row.account {
                    credentials = hasGrokCredentials(account.id)
                } else {
                    credentials = GrokAuth.loadAuthFile() != nil
                        || GrokAuth.normalizedOAuthToken(
                            ProcessInfo.processInfo.environment["GROK_OAUTH_TOKEN"]
                        ) != nil
                }
                return AccountCardRow(
                    id: row.id.uuidString,
                    email: grokDisplayTitle(for: row.id) ?? row.state.snapshot?.accountEmail,
                    fallbackTitle: row.account?.label ?? "Grok",
                    state: row.state,
                    hasCredentials: credentials,
                    recoveryTitle: GrokAccountIdentity.Recovery.action(for: row.state).buttonTitle
                )
            }
        case .cursor, .glm:
            let state = states[provider] ?? .idle
            let email = state.snapshot?.accountEmail
            let fallback: String
            switch state {
            case .signedOut:
                fallback = "Not signed in"
            case .ready(let snapshot), .stale(let snapshot, _):
                if provider == .glm {
                    fallback = snapshot.accountEmail ?? snapshot.planName.map { "GLM \($0)" } ?? "GLM"
                } else {
                    fallback = snapshot.accountEmail ?? "Email unknown"
                }
            default:
                fallback = provider.title
            }
            return [
                AccountCardRow(
                    id: provider.rawValue,
                    email: email,
                    fallbackTitle: fallback,
                    state: state,
                    hasCredentials: !state.isSignedOut
                )
            ]
        }
    }

    /// Always at least one row so Overall can show signed-out providers
    /// (Settings discovery) instead of omitting the section.
    func displayableAccountCards(for provider: ProviderKind) -> [AccountCardRow] {
        let rows = accountCards(for: provider)
        if rows.isEmpty {
            return [
                AccountCardRow(
                    id: provider.rawValue,
                    email: nil,
                    fallbackTitle: "Not signed in",
                    state: providerState(provider),
                    hasCredentials: false
                )
            ]
        }
        return rows
    }

    var overallSections: [OverallSection] {
        visibleProviders.map { provider in
            OverallSection(
                provider: provider,
                rows: displayableAccountCards(for: provider).map { card in
                    OverallAccountRow(
                        provider: provider,
                        card: card,
                        hint: overallHint(provider: provider, card: card)
                    )
                }
            )
        }
    }

    func openOverallRow(_ row: OverallAccountRow) {
        selectTab(.provider(row.provider))
        activateAccountCard(row.card.id)
    }

    private func overallHint(provider: ProviderKind, card: AccountCardRow) -> String {
        if let snapshot = card.state.snapshot, let plan = snapshot.planName, !plan.isEmpty {
            return plan
        }
        if let label = overallAccountLabel(provider: provider, cardID: card.id),
           label != card.displayTitle(for: provider) {
            return label
        }
        if provider == .opencodeGo, card.id == Self.implicitOpenCodeGoID.uuidString {
            return ambientOpenCodeGoSubtitle
        }
        if case .signedOut(let message) = card.state {
            if provider == .cursor, CursorAuth.isRejectedSessionMessage(message) {
                return "Re-sign in inside Cursor"
            }
            if !card.hasCredentials {
                return "Add in Settings"
            }
        }
        return provider.title
    }

    private func overallAccountLabel(provider: ProviderKind, cardID: String) -> String? {
        guard let id = UUID(uuidString: cardID) else { return nil }
        switch provider {
        case .chatgpt:
            return settings.chatgptAccounts.first(where: { $0.id == id })?.label
        case .opencodeGo:
            return settings.opencodeGoAccounts.first(where: { $0.id == id })?.label
        case .grok:
            return settings.grokAccounts.first(where: { $0.id == id })?.label
        case .cursor, .glm:
            return nil
        }
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
        guard settings.allowImplicitChatGPT || settings.previewFixtures else { return [] }
        let implicit = states[.chatgpt] ?? .idle
        switch implicit {
        case .ready, .stale, .loading, .failure:
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

    /// Visible ChatGPT account the menu bar follows. Stored selection wins when
    /// it is still in the list; otherwise the first signed-in remaining account.
    var activeChatGPTAccountId: UUID? {
        if settings.chatgptAccounts.isEmpty { return nil }
        let visible = visibleChatGPTAccounts
        if let selected = settings.selectedChatGPTAccountId,
           visible.contains(where: { $0.id == selected }) {
            return selected
        }
        if let signedIn = visible.first(where: { isSignedInChatGPT($0.id) }) {
            return signedIn.id
        }
        return nil
    }

    /// Menu bar uses this account only — never the min across every card.
    private var activeChatGPTState: ProviderLoadState {
        if settings.chatgptAccounts.isEmpty {
            return chatGPTState(for: nil)
        }
        if let id = activeChatGPTAccountId {
            return chatgptStates[id] ?? .idle
        }
        return .signedOut(ProviderKind.chatgpt.signInHint)
    }

    private func isSignedInChatGPT(_ id: UUID) -> Bool {
        chatgptStates[id]?.hasUsableSnapshot == true
    }

    /// Cookie, pasted JSON, or a readable `auth.json` for this account.
    /// An email alone is not enough: the file may have been deleted.
    func hasChatGPTCredentials(_ id: UUID) -> Bool {
        let auth = chatGPTAuthInputs(for: id)
        if auth.cookie != nil || auth.json != nil { return true }
        if let home = CodexCLIAuth.homeURL(path: auth.home),
           CodexCLIAuth.read(home: home) != nil {
            return true
        }
        if auth.allowAmbient, CodexCLIAuth.read() != nil {
            return true
        }
        return false
    }

    private func chatGPTAuthInputs(for id: UUID) -> (
        cookie: String?,
        json: String?,
        home: String?,
        allowAmbient: Bool,
        email: String?
    ) {
        let account = settings.chatgptAccounts.first(where: { $0.id == id })
        let cookie = emptyToNil(chatgptCookies[id, default: ""])
        let json = emptyToNil(chatgptJSONs[id, default: ""])
        let path = account?.codexHomePath
        let hasScopedHome = CodexCLIAuth.homeURL(path: path) != nil
        let allowAmbient = account?.usesAmbientCodexHome == true && !hasScopedHome
        return (cookie, json, hasScopedHome ? path : nil, allowAmbient, account?.email)
    }

    private func signedInChatGPTAccountIDs() -> [UUID] {
        visibleChatGPTAccounts.compactMap { account in
            isSignedInChatGPT(account.id) ? account.id : nil
        }
    }

    /// Persist a fallback when the active id was deleted or is no longer visible.
    private func ensureActiveChatGPTAccount() {
        let before = settings.selectedChatGPTAccountId
        settings.resolveSelectedChatGPTAccount(preferring: signedInChatGPTAccountIDs())
        if settings.selectedChatGPTAccountId != before {
            persistSettings()
        }
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
        consecutivePollFailures = 0
        lastScheduledPollAt = Date()
        scheduleNextPoll()
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        let base = TimeInterval(settings.pollIntervalSeconds)
        let interval = RefreshCoordinator.pollDelay(
            base: base,
            consecutiveFailures: consecutivePollFailures
        )
        let now = Date()
        let next = RefreshCoordinator.nextScheduledAt(
            previous: lastScheduledPollAt ?? now,
            interval: interval,
            now: now
        )
        lastScheduledPollAt = next
        let delay = max(next.timeIntervalSince(now), 0.1)
        pollTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [self] in
                await self?.refreshAll()
                self?.scheduleNextPoll()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func syncRefreshingFlag() {
        let next = refreshCoordinator.isRefreshing
        if isRefreshing != next {
            isRefreshing = next
        }
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        let previousInterval = settings.pollIntervalSeconds
        mutate(&settings)
        settings.sanitize()
        persistSettings()
        if settings.pollIntervalSeconds != previousInterval {
            restartPolling()
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
        selectTab(.provider(provider))
    }

    func selectTab(_ tab: PopoverTab) {
        if case .provider(let provider) = tab {
            guard settings.enabledProviders.contains(provider) else { return }
            settings.selectedProvider = provider
        }
        settings.popoverTab = tab
        persistSettings()
    }

    func selectChatGPTAccount(_ id: UUID) {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        guard settings.selectedChatGPTAccountId != id else { return }
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
            if case .provider(let tab) = settings.popoverTab, tab == provider {
                settings.popoverTab = .all
            }
        }
        persistSettings()
        Task { await refresh(provider) }
    }

    func persistSecrets() {
        KeychainStore.set(cursorCookie, account: .cursorCookie)
        KeychainStore.set(glmAPIKey, account: .glmAPIKey)
        persistChatGPTSecrets()
        persistOpenCodeGoSecrets()
        persistGrokSecrets()
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

    func setAllowImplicitChatGPT(_ enabled: Bool) {
        guard settings.allowImplicitChatGPT != enabled else { return }
        settings.allowImplicitChatGPT = enabled
        persistSettings()
        Task { await refresh(.chatgpt) }
    }

    func setAllowImplicitGrok(_ enabled: Bool) {
        guard settings.allowImplicitGrok != enabled else { return }
        settings.allowImplicitGrok = enabled
        persistSettings()
        Task { await refresh(.grok) }
    }

    func setAllowImplicitOpenCodeGo(_ enabled: Bool) {
        guard settings.allowImplicitOpenCodeGo != enabled else { return }
        settings.allowImplicitOpenCodeGo = enabled
        persistSettings()
        Task { await refresh(.opencodeGo) }
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

    /// Create-on-success, or refresh the row that already holds this cookie.
    /// Email is a label only — two sessions with the same mailbox stay two rows.
    @discardableResult
    func upsertChatGPTAccount(cookie: String, email: String?) -> UUID {
        let trimmedCookie = ChatGPTClient.normalizeCookie(cookie)
            ?? cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValue = CodexCLIAuth.usableEmail(email)

        if !trimmedCookie.isEmpty,
           let existing = settings.chatgptAccounts.first(where: {
               chatgptCookies[$0.id] == trimmedCookie
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
        recordChatGPTEmail(emailValue, for: id)
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

    func applyChatGPTRelogin(
        accountId: UUID,
        homePath: String,
        email: String?,
        ambient: Bool
    ) {
        guard let index = settings.chatgptAccounts.firstIndex(where: { $0.id == accountId }) else { return }
        let previousHome = settings.chatgptAccounts[index].codexHomePath
        let standardizedHome = CodexCLIAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        let incomingToken = CodexCLIAuth.homeURL(path: standardizedHome)
            .flatMap { CodexCLIAuth.read(home: $0)?.accessToken }
        if let other = ChatGPTAccountIdentity.matchExisting(
            accounts: settings.chatgptAccounts,
            homePath: standardizedHome,
            accessToken: incomingToken,
            excluding: accountId
        ) {
            ChatGPTAccountIdentity.assignIdentity(
                email,
                to: accountId,
                accounts: &settings.chatgptAccounts
            )
            settings.selectedChatGPTAccountId = other.id
            persistSettings()
            Task { await refreshChatGPTAccount(other.id, userInitiated: true) }
            return
        }
        settings.chatgptAccounts[index].codexHomePath = standardizedHome
        settings.chatgptAccounts[index].usesAmbientCodexHome = ambient
        ChatGPTAccountIdentity.assignIdentity(
            email,
            to: accountId,
            accounts: &settings.chatgptAccounts
        )
        if previousHome != standardizedHome {
            CodexCLIAuth.removeManagedHomeIfSafe(previousHome)
        }
        settings.selectedChatGPTAccountId = accountId
        persistSettings()
        Task { await refreshChatGPTAccount(accountId, userInitiated: true) }
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
        if settings.chatgptAccounts.isEmpty {
            settings.allowImplicitChatGPT = false
        }
        if settings.selectedChatGPTAccountId == id {
            settings.selectedChatGPTAccountId = nil
            settings.resolveSelectedChatGPTAccount(preferring: signedInChatGPTAccountIDs())
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
        let standardizedHome = CodexCLIAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        let tokens = CodexCLIAuth.homeURL(path: standardizedHome).flatMap { CodexCLIAuth.read(home: $0) }
        let existed = Set(settings.chatgptAccounts.map(\.id))
        let id = ChatGPTAccountIdentity.upsertFromHome(
            accounts: &settings.chatgptAccounts,
            homePath: standardizedHome,
            email: email ?? tokens?.email,
            ambient: ambient,
            accessToken: tokens?.accessToken,
            nextLabel: nextChatGPTLabel()
        )
        if !existed.contains(id) {
            chatgptCookies[id] = chatgptCookies[id] ?? ""
            chatgptJSONs[id] = chatgptJSONs[id] ?? ""
            chatgptStates[id] = .idle
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

    func refreshSelected(force: Bool = true) async {
        let key = "ui:selected"
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        // Let SwiftUI paint the spinner before a fast fetch coalesces state updates.
        await Task.yield()
        switch settings.popoverTab {
        case .all:
            await refreshVisibleProviders(force: force, userInitiated: true)
        case .provider(let provider):
            await refreshProviderAccounts(provider, userInitiated: true, force: force)
        }
    }

    func refreshCard(_ cardID: String, provider: ProviderKind? = nil) async {
        let kind = provider ?? selected
        if kind == .chatgpt, let id = UUID(uuidString: cardID),
           settings.chatgptAccounts.contains(where: { $0.id == id }) {
            await refreshChatGPTAccount(id, userInitiated: true)
            return
        }
        if kind == .chatgpt, cardID == Self.implicitChatGPTID.uuidString {
            await refreshImplicitChatGPT(userInitiated: true)
            return
        }
        if kind == .opencodeGo, let id = UUID(uuidString: cardID),
           settings.opencodeGoAccounts.contains(where: { $0.id == id }) {
            await refreshOpenCodeGoAccount(id, userInitiated: true)
            return
        }
        if kind == .opencodeGo, cardID == Self.implicitOpenCodeGoID.uuidString {
            await refreshImplicitOpenCodeGo(userInitiated: true)
            return
        }
        if kind == .grok, let id = UUID(uuidString: cardID),
           settings.grokAccounts.contains(where: { $0.id == id }) {
            await recoverGrokCard(id)
            return
        }
        if kind == .grok, cardID == Self.implicitGrokID.uuidString {
            await refreshImplicitGrok(userInitiated: true)
            return
        }
        if kind == .cursor || kind == .glm {
            await refresh(kind)
            return
        }
        await refreshSelected()
    }

    /// Card Retry / Re-login. Expired ChatGPT / Grok sessions open the same
    /// re-login flow as Settings; other failures re-fetch and show loading.
    func recoverAccountCard(_ cardID: String, provider: ProviderKind? = nil) {
        let kind = provider ?? selected
        if kind == .chatgpt, let id = UUID(uuidString: cardID),
           settings.chatgptAccounts.contains(where: { $0.id == id }) {
            switch ChatGPTAccountIdentity.Recovery.action(for: chatgptStates[id] ?? .idle) {
            case .relogin:
                CodexLoginPresenter.shared.beginRelogin(store: self, accountId: id)
            case .retryRefresh:
                Task { await refreshChatGPTAccount(id, userInitiated: true) }
            }
            return
        }
        if kind == .grok, let id = UUID(uuidString: cardID),
           settings.grokAccounts.contains(where: { $0.id == id }) {
            Task { await recoverGrokCard(id) }
            return
        }
        Task { await refreshCard(cardID, provider: kind) }
    }

    func recoverOverallRow(_ row: OverallAccountRow) {
        recoverAccountCard(row.card.id, provider: row.provider)
    }

    private func recoverGrokCard(_ id: UUID) async {
        let state = grokStates[id] ?? .idle
        switch GrokAccountIdentity.Recovery.action(for: state) {
        case .relogin:
            GrokLoginPresenter.shared.beginRelogin(store: self, accountId: id)
        case .retryRefresh:
            await refreshGrokAccount(id, userInitiated: true)
        }
    }

    func refreshAll() async {
        let key = "ui:all"
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        await refreshVisibleProviders(force: true, userInitiated: false)
    }

    /// Shared fan-out used by poll, All-tab refresh, and `refreshAll`.
    /// Does not invent a second pipeline — same `refresh(_:)` jobs as before.
    private func refreshVisibleProviders(force: Bool, userInitiated: Bool) async {
        let providers = visibleProviders.filter { provider in
            force || needsProviderRefresh(provider)
        }
        // Paint every card as in-flight before any provider hops off MainActor.
        // Otherwise ChatGPT `.loading` + later `.idle` both read as "Updating…".
        for provider in providers {
            markRefreshStarted(provider, userInitiated: userInitiated)
        }
        // Fan-out off MainActor so ChatGPT / Go cannot stall Cursor / GLM / Grok.
        await RefreshWork.mapConcurrent(providers) { provider in
            await AppStore.shared.refresh(provider, userInitiated: userInitiated, force: true)
        }
        notePollOutcome()
    }

    private func refreshProviderAccounts(
        _ provider: ProviderKind,
        userInitiated: Bool,
        force: Bool
    ) async {
        switch provider {
        case .chatgpt:
            await refreshAllChatGPTAccounts(userInitiated: userInitiated, force: force)
        case .opencodeGo:
            await refreshAllOpenCodeGoAccounts(userInitiated: userInitiated, force: force)
        case .grok:
            await refreshAllGrokAccounts(userInitiated: userInitiated, force: force)
        case .cursor, .glm:
            await refresh(provider, userInitiated: userInitiated, force: force)
        }
    }

    private func needsProviderRefresh(_ provider: ProviderKind) -> Bool {
        switch provider {
        case .chatgpt:
            if settings.chatgptAccounts.isEmpty {
                return RefreshCoordinator.needsOpenRefresh(states[.chatgpt] ?? .idle, force: false)
            }
            return visibleChatGPTAccounts.contains {
                RefreshCoordinator.needsOpenRefresh(chatgptStates[$0.id] ?? .idle, force: false)
            }
        case .opencodeGo:
            if settings.opencodeGoAccounts.isEmpty {
                return RefreshCoordinator.needsOpenRefresh(states[.opencodeGo] ?? .idle, force: false)
            }
            return visibleOpenCodeGoAccounts.contains {
                RefreshCoordinator.needsOpenRefresh(opencodeGoStates[$0.id] ?? .idle, force: false)
            }
        case .grok:
            if settings.grokAccounts.isEmpty {
                return RefreshCoordinator.needsOpenRefresh(states[.grok] ?? .idle, force: false)
            }
            return visibleGrokAccounts.contains {
                RefreshCoordinator.needsOpenRefresh(grokStates[$0.id] ?? .idle, force: false)
            }
        case .cursor, .glm:
            return RefreshCoordinator.needsOpenRefresh(states[provider] ?? .idle, force: false)
        }
    }

    private func notePollOutcome() {
        let failed = visibleProviders.contains { provider in
            switch providerState(provider) {
            case .failure, .signedOut, .stale:
                return true
            default:
                return false
            }
        }
        if failed {
            consecutivePollFailures = min(consecutivePollFailures + 1, 5)
        } else {
            consecutivePollFailures = 0
        }
    }

    private func markRefreshStarted(_ provider: ProviderKind, userInitiated: Bool) {
        switch provider {
        case .chatgpt:
            if settings.chatgptAccounts.isEmpty {
                let current = states[.chatgpt] ?? .idle
                if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                    states[.chatgpt] = .loading
                }
            } else {
                for account in settings.chatgptAccounts {
                    let current = chatgptStates[account.id] ?? .idle
                    if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                        chatgptStates[account.id] = .loading
                    }
                }
            }
        case .opencodeGo:
            if settings.opencodeGoAccounts.isEmpty {
                let current = states[.opencodeGo] ?? .idle
                if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                    states[.opencodeGo] = .loading
                }
            } else {
                for account in settings.opencodeGoAccounts {
                    let current = opencodeGoStates[account.id] ?? .idle
                    if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                        opencodeGoStates[account.id] = .loading
                    }
                }
            }
        case .grok:
            if settings.grokAccounts.isEmpty {
                let current = states[.grok] ?? .idle
                if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                    states[.grok] = .loading
                }
            } else {
                for account in settings.grokAccounts {
                    let current = grokStates[account.id] ?? .idle
                    if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                        grokStates[account.id] = .loading
                    }
                }
            }
        default:
            let current = states[provider] ?? .idle
            if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                states[provider] = .loading
            }
        }
    }

    func refresh(
        _ provider: ProviderKind,
        userInitiated: Bool = false,
        force: Bool = true
    ) async {
        if provider == .chatgpt {
            await refreshAllChatGPTAccounts(userInitiated: userInitiated, force: force)
            return
        }
        if provider == .opencodeGo {
            await refreshAllOpenCodeGoAccounts(userInitiated: userInitiated, force: force)
            return
        }
        if provider == .grok {
            await refreshAllGrokAccounts(userInitiated: userInitiated, force: force)
            return
        }
        if !force, !RefreshCoordinator.needsOpenRefresh(states[provider] ?? .idle, force: false) {
            return
        }
        let key = RefreshCoordinator.key(provider)
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        let current = states[provider] ?? .idle
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            states[provider] = .loading
        }
        let job = SingleProviderFetchJob(
            provider: provider,
            preview: settings.previewFixtures,
            cursorCookie: emptyToNil(cursorCookie),
            glmAPIKey: emptyToNil(glmAPIKey),
            glmRegion: settings.glmRegion
        )
        let result = await RefreshWork.performSingle(job)
        guard refreshCoordinator.isCurrent(key, generation: generation) else { return }
        switch result {
        case .success(let snapshot):
            states[provider] = .ready(snapshot)
        case .failure(let error):
            if error.isCancellation { return }
            if error.isAuthFailure {
                states[provider] = .signedOut(error.errorDescription ?? provider.signInHint)
            } else {
                states[provider] = ProviderLoadState.afterFailure(
                    previous: current,
                    error: error,
                    hasCredentials: true,
                    signInHint: provider.signInHint
                )
            }
        }
    }

    private func refreshAllChatGPTAccounts(userInitiated: Bool, force: Bool = true) async {
        let accounts = settings.chatgptAccounts
        if accounts.isEmpty {
            if settings.previewFixtures {
                await refreshChatGPTPreviewFallback(userInitiated: userInitiated)
            } else if settings.allowImplicitChatGPT {
                await refreshImplicitChatGPT(userInitiated: userInitiated)
            } else {
                states[.chatgpt] = .signedOut(ProviderKind.chatgpt.signInHint)
            }
            return
        }
        var jobs: [ChatGPTFetchJob] = []
        var generations: [UUID: Int] = [:]
        for (index, account) in accounts.enumerated() {
            let current = chatgptStates[account.id] ?? .idle
            if !force, !RefreshCoordinator.needsOpenRefresh(current, force: false) {
                continue
            }
            let key = RefreshCoordinator.key(.chatgpt, accountID: account.id)
            generations[account.id] = refreshCoordinator.begin(key)
            if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                chatgptStates[account.id] = .loading
            }
            let auth = chatGPTAuthInputs(for: account.id)
            jobs.append(
                ChatGPTFetchJob(
                    id: account.id,
                    previous: current,
                    cookie: auth.cookie,
                    json: auth.json,
                    home: auth.home,
                    allowAmbient: auth.allowAmbient,
                    email: auth.email,
                    preview: settings.previewFixtures,
                    variant: index
                )
            )
        }
        syncRefreshingFlag()

        let results = await RefreshWork.mapConcurrent(jobs) { job in
            await RefreshWork.performChatGPT(job)
        }
        for item in results {
            let key = RefreshCoordinator.key(.chatgpt, accountID: item.id)
            let generation = generations[item.id] ?? 0
            applyChatGPTResult(item, key: key, generation: generation)
            refreshCoordinator.finish(key, generation: generation)
        }
        syncRefreshingFlag()
        ensureActiveChatGPTAccount()
    }

    private func refreshChatGPTAccount(_ id: UUID, userInitiated: Bool) async {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        let current = chatgptStates[id] ?? .idle
        let key = RefreshCoordinator.key(.chatgpt, accountID: id)
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        // Keep last meters while refreshing. Opening the popover used to
        // flash every card to "Updating…" and then paint a false Sign in
        // if one fetch failed.
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            chatgptStates[id] = .loading
        }

        let index = settings.chatgptAccounts.firstIndex(where: { $0.id == id }) ?? 0
        let auth = chatGPTAuthInputs(for: id)
        let job = ChatGPTFetchJob(
            id: id,
            previous: current,
            cookie: auth.cookie,
            json: auth.json,
            home: auth.home,
            allowAmbient: auth.allowAmbient,
            email: auth.email,
            preview: settings.previewFixtures,
            variant: index
        )
        applyChatGPTResult(await RefreshWork.performChatGPT(job), key: key, generation: generation)
    }

    private func applyChatGPTResult(_ item: AccountFetchResult, key: String, generation: Int) {
        guard refreshCoordinator.isCurrent(key, generation: generation) else { return }
        switch item.result {
        case .success(let snapshot):
            chatgptStates[item.id] = .ready(snapshot)
            recordChatGPTEmail(snapshot.accountEmail, for: item.id)
        case .failure(let error):
            if let quota = error as? QuotaError, quota.isCancellation { return }
            chatgptStates[item.id] = ProviderLoadState.afterFailure(
                previous: item.previous,
                error: error,
                hasCredentials: hasChatGPTCredentials(item.id),
                signInHint: ProviderKind.chatgpt.signInHint
            )
        }
    }

    /// Uses ~/.codex/auth.json when no ChatGPT account has been added yet.
    /// Does not persist a new account on each launch.
    private func refreshImplicitChatGPT(userInitiated: Bool) async {
        let key = RefreshCoordinator.key(.chatgpt, accountID: Self.implicitChatGPTID)
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        let current = states[.chatgpt] ?? .idle
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            states[.chatgpt] = .loading
        }
        let item = await RefreshWork.performChatGPT(
            ChatGPTFetchJob(
                id: Self.implicitChatGPTID,
                previous: current,
                cookie: nil,
                json: nil,
                home: nil,
                allowAmbient: true,
                email: nil,
                preview: false,
                variant: 0
            )
        )
        guard refreshCoordinator.isCurrent(key, generation: generation) else { return }
        applyImplicitChatGPT(current, item)
    }

    private func refreshChatGPTPreviewFallback(userInitiated _: Bool) async {
        let current = states[.chatgpt] ?? .idle
        if shouldShowLoading(current) {
            states[.chatgpt] = .loading
        }
        applyImplicitChatGPT(
            current,
            await RefreshWork.performChatGPT(
                ChatGPTFetchJob(
                    id: Self.implicitChatGPTID,
                    previous: current,
                    cookie: nil,
                    json: nil,
                    home: nil,
                    allowAmbient: false,
                    email: nil,
                    preview: true,
                    variant: 0
                )
            )
        )
    }

    private func applyImplicitChatGPT(_ current: ProviderLoadState, _ item: AccountFetchResult) {
        switch item.result {
        case .success(let snapshot):
            states[.chatgpt] = .ready(snapshot)
        case .failure(let error):
            if error.isCancellation { return }
            states[.chatgpt] = ProviderLoadState.afterFailure(
                previous: current,
                error: error,
                hasCredentials: CodexCLIAuth.read() != nil,
                signInHint: ProviderKind.chatgpt.signInHint
            )
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
        case .ready, .stale, .signedOut, .failure:
            return false
        }
    }

    private func recordChatGPTEmail(_ email: String?, for id: UUID) {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        let before = settings.chatgptAccounts.first(where: { $0.id == id })?.email
        ChatGPTAccountIdentity.assignIdentity(
            email,
            to: id,
            accounts: &settings.chatgptAccounts
        )
        if settings.chatgptAccounts.first(where: { $0.id == id })?.email != before {
            persistSettings()
        }
    }

    private func loadChatGPTSecrets() {
        for account in settings.chatgptAccounts {
            chatgptCookies[account.id] = KeychainStore.get(.chatgptAccountCookie(account.id)) ?? ""
            chatgptJSONs[account.id] = KeychainStore.get(.chatgptAccountJSON(account.id)) ?? ""
            chatgptStates[account.id] = .idle
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

struct OpenCodeGoDisplayRow: Identifiable, Equatable {
    var id: UUID
    var account: OpenCodeGoAccount?
    var state: ProviderLoadState
}

extension AppStore {
    static let implicitOpenCodeGoID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    var visibleOpenCodeGoAccounts: [OpenCodeGoAccount] {
        settings.visibleOpenCodeGoAccounts
    }

    func isActiveOpenCodeGoCard(_ cardID: String) -> Bool {
        guard selected == .opencodeGo else { return false }
        if settings.opencodeGoAccounts.isEmpty {
            return true
        }
        guard let active = activeOpenCodeGoAccountId else { return false }
        return cardID == active.uuidString
    }

    func activateOpenCodeGoCard(_ cardID: String) {
        guard selected == .opencodeGo else { return }
        guard let id = UUID(uuidString: cardID) else { return }
        selectOpenCodeGoAccount(id)
    }

    var opencodeGoDisplayRows: [OpenCodeGoDisplayRow] {
        if !settings.opencodeGoAccounts.isEmpty {
            return visibleOpenCodeGoAccounts.map { account in
                OpenCodeGoDisplayRow(
                    id: account.id,
                    account: account,
                    state: opencodeGoStates[account.id] ?? .idle
                )
            }
        }
        guard settings.allowImplicitOpenCodeGo || settings.previewFixtures else { return [] }
        let implicit = states[.opencodeGo] ?? .idle
        switch implicit {
        case .ready, .stale, .loading, .failure:
            return [OpenCodeGoDisplayRow(id: Self.implicitOpenCodeGoID, account: nil, state: implicit)]
        case .idle:
            if settings.previewFixtures || OpenCodeGoClient.resolveToken(explicit: nil) != nil {
                return [OpenCodeGoDisplayRow(id: Self.implicitOpenCodeGoID, account: nil, state: implicit)]
            }
            return []
        case .signedOut:
            if OpenCodeGoClient.resolveToken(explicit: nil) != nil {
                return [OpenCodeGoDisplayRow(id: Self.implicitOpenCodeGoID, account: nil, state: implicit)]
            }
            return []
        }
    }

    /// True when Settings should show the env/implicit OpenCode row instead of an empty state.
    var hasAmbientOpenCodeGoSource: Bool {
        guard settings.opencodeGoAccounts.isEmpty, settings.allowImplicitOpenCodeGo else { return false }
        if OpenCodeGoClient.resolveToken(explicit: nil) != nil { return true }
        if settings.previewFixtures { return true }
        switch states[.opencodeGo] ?? .idle {
        case .ready, .stale, .loading, .failure:
            return true
        case .idle, .signedOut:
            return false
        }
    }

    var canImportAmbientOpenCodeGo: Bool {
        settings.opencodeGoAccounts.isEmpty && OpenCodeGoClient.resolveToken(explicit: nil) != nil
    }

    var ambientOpenCodeGoVariableName: String? {
        OpenCodeGoClient.ambientEnvironmentVariableName()
    }

    var ambientOpenCodeGoTitle: String {
        if let email = states[.opencodeGo]?.snapshot?.accountEmail, !email.isEmpty {
            return email
        }
        if ambientOpenCodeGoVariableName != nil {
            return "OpenCode (env)"
        }
        if settings.previewFixtures {
            return "OpenCode (preview)"
        }
        return "OpenCode"
    }

    var ambientOpenCodeGoSubtitle: String {
        if let name = ambientOpenCodeGoVariableName {
            return "Using \(name)"
        }
        if settings.previewFixtures {
            return "Preview fixtures"
        }
        return "Ambient OpenCode key"
    }

    var ambientOpenCodeGoStatus: String {
        switch states[.opencodeGo] ?? .idle {
        case .ready(let snapshot):
            if let remaining = snapshot.mostConstrainedRemaining {
                let percent = Int(remaining.rounded())
                if let plan = snapshot.planName, !plan.isEmpty {
                    return "\(plan) · \(percent)% left"
                }
                return "\(percent)% left"
            }
            return snapshot.planName.map { "Live \($0) quota" } ?? "Live quota"
        case .stale(let snapshot, let message):
            if let remaining = snapshot.mostConstrainedRemaining {
                return "\(Int(remaining.rounded()))% left · \(message)"
            }
            return message
        case .loading:
            return "Refreshing quota"
        case .failure(let message), .signedOut(let message):
            return message
        case .idle:
            return "Refresh to load quota"
        }
    }

    var activeOpenCodeGoAccountId: UUID? {
        if settings.opencodeGoAccounts.isEmpty { return nil }
        let visible = visibleOpenCodeGoAccounts
        if let selected = settings.selectedOpenCodeGoAccountId,
           visible.contains(where: { $0.id == selected }) {
            return selected
        }
        if let signedIn = visible.first(where: { isSignedInOpenCodeGo($0.id) }) {
            return signedIn.id
        }
        return nil
    }

    private var activeOpenCodeGoState: ProviderLoadState {
        if settings.opencodeGoAccounts.isEmpty {
            return openCodeGoState(for: nil)
        }
        if let id = activeOpenCodeGoAccountId {
            return opencodeGoStates[id] ?? .idle
        }
        return .signedOut(ProviderKind.opencodeGo.signInHint)
    }

    private func isSignedInOpenCodeGo(_ id: UUID) -> Bool {
        opencodeGoStates[id]?.hasUsableSnapshot == true
    }

    func hasOpenCodeGoCredentials(_ id: UUID) -> Bool {
        emptyToNil(opencodeGoAPIKeys[id, default: ""]) != nil
    }

    func selectOpenCodeGoAccount(_ id: UUID) {
        guard settings.opencodeGoAccounts.contains(where: { $0.id == id }) else { return }
        guard settings.selectedOpenCodeGoAccountId != id else { return }
        settings.selectedOpenCodeGoAccountId = id
        persistSettings()
    }

    func nextOpenCodeGoLabel() -> String {
        let existing = Set(settings.opencodeGoAccounts.map(\.label))
        if !existing.contains("OpenCode") { return "OpenCode" }
        var index = 2
        while existing.contains("OpenCode \(index)") {
            index += 1
        }
        return "OpenCode \(index)"
    }

    @discardableResult
    func addOpenCodeGoAccount(label: String? = nil) -> UUID {
        let id = UUID()
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? nextOpenCodeGoLabel() : trimmed
        settings.opencodeGoAccounts.append(OpenCodeGoAccount(id: id, label: resolved, enabled: true))
        if settings.selectedOpenCodeGoAccountId == nil {
            settings.selectedOpenCodeGoAccountId = id
        }
        opencodeGoAPIKeys[id] = ""
        opencodeGoStates[id] = .idle
        persistSettings()
        return id
    }

    /// Copies the ambient env key into a Keychain account. Does not run unless the user asks.
    @discardableResult
    func importAmbientOpenCodeGoAccount() -> UUID? {
        guard canImportAmbientOpenCodeGo else { return nil }
        guard let token = OpenCodeGoClient.resolveToken(explicit: nil) else { return nil }
        let id = addOpenCodeGoAccount(label: "OpenCode")
        setOpenCodeGoAPIKey(token, for: id)
        if let snapshot = states[.opencodeGo]?.snapshot {
            opencodeGoStates[id] = .ready(snapshot)
            recordOpenCodeGoEmail(snapshot.accountEmail, for: id)
        }
        Task { await refreshOpenCodeGoAccount(id, userInitiated: true) }
        return id
    }

    func renameOpenCodeGoAccount(_ id: UUID, to label: String) {
        guard let index = settings.opencodeGoAccounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.opencodeGoAccounts[index].label = trimmed.isEmpty ? "OpenCode" : trimmed
        persistSettings()
    }

    func deleteOpenCodeGoAccount(_ id: UUID) {
        settings.opencodeGoAccounts.removeAll { $0.id == id }
        opencodeGoAPIKeys[id] = nil
        opencodeGoStates[id] = nil
        KeychainStore.delete(.opencodeGoAPIKey(id))
        if settings.opencodeGoAccounts.isEmpty {
            settings.allowImplicitOpenCodeGo = false
        }
        if settings.selectedOpenCodeGoAccountId == id {
            settings.selectedOpenCodeGoAccountId = nil
            settings.resolveSelectedOpenCodeGoAccount(preferring: signedInOpenCodeGoAccountIDs())
        }
        persistSettings()
    }

    func setOpenCodeGoAPIKey(_ value: String, for id: UUID) {
        opencodeGoAPIKeys[id] = value
        KeychainStore.set(value, account: .opencodeGoAPIKey(id))
    }

    fileprivate func persistOpenCodeGoSecrets() {
        for account in settings.opencodeGoAccounts {
            KeychainStore.set(opencodeGoAPIKeys[account.id], account: .opencodeGoAPIKey(account.id))
        }
    }

    fileprivate func loadOpenCodeGoSecrets() {
        for account in settings.opencodeGoAccounts {
            opencodeGoAPIKeys[account.id] = KeychainStore.get(.opencodeGoAPIKey(account.id)) ?? ""
            opencodeGoStates[account.id] = .idle
        }
    }

    fileprivate func refreshAllOpenCodeGoAccounts(userInitiated: Bool, force: Bool = true) async {
        let accounts = settings.opencodeGoAccounts
        if accounts.isEmpty {
            if settings.allowImplicitOpenCodeGo || settings.previewFixtures {
                await refreshImplicitOpenCodeGo(userInitiated: userInitiated)
            } else {
                states[.opencodeGo] = .signedOut(ProviderKind.opencodeGo.signInHint)
            }
            return
        }
        var jobs: [OpenCodeGoFetchJob] = []
        var generations: [UUID: Int] = [:]
        for (index, account) in accounts.enumerated() {
            let current = opencodeGoStates[account.id] ?? .idle
            if !force, !RefreshCoordinator.needsOpenRefresh(current, force: false) {
                continue
            }
            let key = RefreshCoordinator.key(.opencodeGo, accountID: account.id)
            generations[account.id] = refreshCoordinator.begin(key)
            if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                opencodeGoStates[account.id] = .loading
            }
            jobs.append(
                OpenCodeGoFetchJob(
                    id: account.id,
                    previous: current,
                    apiKey: emptyToNil(opencodeGoAPIKeys[account.id, default: ""]),
                    email: account.email,
                    preview: settings.previewFixtures,
                    variant: index
                )
            )
        }
        syncRefreshingFlag()

        let results = await RefreshWork.mapConcurrent(jobs) { job in
            await RefreshWork.performOpenCodeGo(job)
        }
        for item in results {
            let key = RefreshCoordinator.key(.opencodeGo, accountID: item.id)
            let generation = generations[item.id] ?? 0
            applyOpenCodeGoResult(item, key: key, generation: generation)
            refreshCoordinator.finish(key, generation: generation)
        }
        syncRefreshingFlag()
        ensureActiveOpenCodeGoAccount()
    }

    fileprivate func refreshOpenCodeGoAccount(_ id: UUID, userInitiated: Bool) async {
        guard settings.opencodeGoAccounts.contains(where: { $0.id == id }) else { return }
        let current = opencodeGoStates[id] ?? .idle
        let key = RefreshCoordinator.key(.opencodeGo, accountID: id)
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            opencodeGoStates[id] = .loading
        }
        let index = settings.opencodeGoAccounts.firstIndex(where: { $0.id == id }) ?? 0
        let account = settings.opencodeGoAccounts.first(where: { $0.id == id })
        let job = OpenCodeGoFetchJob(
            id: id,
            previous: current,
            apiKey: emptyToNil(opencodeGoAPIKeys[id, default: ""]),
            email: account?.email,
            preview: settings.previewFixtures,
            variant: index
        )
        applyOpenCodeGoResult(await RefreshWork.performOpenCodeGo(job), key: key, generation: generation)
    }

    private func applyOpenCodeGoResult(_ item: AccountFetchResult, key: String, generation: Int) {
        guard refreshCoordinator.isCurrent(key, generation: generation) else { return }
        switch item.result {
        case .success(let snapshot):
            opencodeGoStates[item.id] = .ready(snapshot)
            recordOpenCodeGoEmail(snapshot.accountEmail, for: item.id)
        case .failure(let error):
            if let quota = error as? QuotaError, quota.isCancellation { return }
            opencodeGoStates[item.id] = ProviderLoadState.afterFailure(
                previous: item.previous,
                error: error,
                hasCredentials: hasOpenCodeGoCredentials(item.id),
                signInHint: ProviderKind.opencodeGo.signInHint
            )
        }
    }

    fileprivate func refreshImplicitOpenCodeGo(userInitiated: Bool) async {
        let current = states[.opencodeGo] ?? .idle
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            states[.opencodeGo] = .loading
        }
        let item = await RefreshWork.performOpenCodeGo(
            OpenCodeGoFetchJob(
                id: Self.implicitOpenCodeGoID,
                previous: current,
                apiKey: nil,
                email: nil,
                preview: settings.previewFixtures,
                variant: 0
            )
        )
        switch item.result {
        case .success(let snapshot):
            states[.opencodeGo] = .ready(snapshot)
        case .failure(let error):
            if error.isCancellation { return }
            states[.opencodeGo] = ProviderLoadState.afterFailure(
                previous: current,
                error: error,
                hasCredentials: OpenCodeGoClient.resolveToken(explicit: nil) != nil,
                signInHint: ProviderKind.opencodeGo.signInHint
            )
        }
    }

    private func openCodeGoState(for id: UUID?) -> ProviderLoadState {
        if settings.opencodeGoAccounts.isEmpty {
            if settings.previewFixtures {
                return states[.opencodeGo] ?? .idle
            }
            let implicit = states[.opencodeGo] ?? .idle
            switch implicit {
            case .idle:
                return .signedOut(ProviderKind.opencodeGo.signInHint)
            default:
                return implicit
            }
        }
        guard let id, settings.opencodeGoAccounts.contains(where: { $0.id == id }) else {
            return .signedOut(ProviderKind.opencodeGo.signInHint)
        }
        return opencodeGoStates[id] ?? .idle
    }

    private func signedInOpenCodeGoAccountIDs() -> [UUID] {
        visibleOpenCodeGoAccounts.compactMap { account in
            isSignedInOpenCodeGo(account.id) ? account.id : nil
        }
    }

    private func ensureActiveOpenCodeGoAccount() {
        let before = settings.selectedOpenCodeGoAccountId
        settings.resolveSelectedOpenCodeGoAccount(preferring: signedInOpenCodeGoAccountIDs())
        if settings.selectedOpenCodeGoAccountId != before {
            persistSettings()
        }
    }

    private func recordOpenCodeGoEmail(_ email: String?, for id: UUID) {
        let trimmed = CodexCLIAuth.usableEmail(email)
        guard let trimmed else { return }
        guard let index = settings.opencodeGoAccounts.firstIndex(where: { $0.id == id }) else { return }
        guard settings.opencodeGoAccounts[index].email != trimmed else { return }
        settings.opencodeGoAccounts[index].email = trimmed
        persistSettings()
    }
}

struct GrokDisplayRow: Identifiable, Equatable {
    var id: UUID
    var account: GrokAccount?
    var state: ProviderLoadState
}

extension AppStore {
    static let implicitGrokID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    var visibleGrokAccounts: [GrokAccount] {
        settings.visibleGrokAccounts
    }

    func isActiveGrokCard(_ cardID: String) -> Bool {
        guard selected == .grok else { return false }
        if settings.grokAccounts.isEmpty {
            return true
        }
        guard let active = activeGrokAccountId else { return false }
        return cardID == active.uuidString
    }

    func activateGrokCard(_ cardID: String) {
        guard selected == .grok else { return }
        guard let id = UUID(uuidString: cardID) else { return }
        selectGrokAccount(id)
    }

    var grokDisplayRows: [GrokDisplayRow] {
        if !settings.grokAccounts.isEmpty {
            return visibleGrokAccounts.map { account in
                GrokDisplayRow(
                    id: account.id,
                    account: account,
                    state: grokStates[account.id] ?? .idle
                )
            }
        }
        guard settings.allowImplicitGrok || settings.previewFixtures else { return [] }
        let implicit = states[.grok] ?? .idle
        switch implicit {
        case .ready, .stale, .loading, .failure:
            return [GrokDisplayRow(id: Self.implicitGrokID, account: nil, state: implicit)]
        case .idle:
            if settings.previewFixtures {
                return [GrokDisplayRow(id: Self.implicitGrokID, account: nil, state: implicit)]
            }
            return []
        case .signedOut:
            return []
        }
    }

    var activeGrokAccountId: UUID? {
        if settings.grokAccounts.isEmpty { return nil }
        let visible = visibleGrokAccounts
        if let selected = settings.selectedGrokAccountId,
           visible.contains(where: { $0.id == selected }) {
            return selected
        }
        if let signedIn = visible.first(where: { isSignedInGrok($0.id) }) {
            return signedIn.id
        }
        return nil
    }

    var activeGrokState: ProviderLoadState {
        if settings.grokAccounts.isEmpty {
            return grokState(for: nil)
        }
        if let id = activeGrokAccountId {
            return grokStates[id] ?? .idle
        }
        return .signedOut(ProviderKind.grok.signInHint)
    }

    var hasAmbientGrokAccount: Bool {
        settings.grokAccounts.contains { account in
            account.usesAmbientAuthFile || GrokAuth.isAmbientHomePath(account.grokHomePath)
        }
    }

    var canImportAmbientGrok: Bool {
        !hasAmbientGrokAccount && GrokAuth.loadAuthFile() != nil
    }

    private func isSignedInGrok(_ id: UUID) -> Bool {
        grokStates[id]?.hasUsableSnapshot == true
    }

    func hasGrokCredentials(_ id: UUID) -> Bool {
        if emptyToNil(grokTokens[id, default: ""]) != nil { return true }
        let account = settings.grokAccounts.first(where: { $0.id == id })
        if let path = account?.grokHomePath,
           let home = GrokAuth.homeURL(path: path),
           GrokAuth.loadAuthFile(home: home) != nil {
            return true
        }
        if account?.usesAmbientAuthFile == true, GrokAuth.loadAuthFile() != nil {
            return true
        }
        return false
    }

    func selectGrokAccount(_ id: UUID) {
        guard settings.grokAccounts.contains(where: { $0.id == id }) else { return }
        guard settings.selectedGrokAccountId != id else { return }
        settings.selectedGrokAccountId = id
        persistSettings()
    }

    func nextGrokLabel() -> String {
        let existing = Set(settings.grokAccounts.map(\.label))
        if !existing.contains("Grok") { return "Grok" }
        var index = 2
        while existing.contains("Grok \(index)") {
            index += 1
        }
        return "Grok \(index)"
    }

    @discardableResult
    func addGrokAccount(label: String? = nil) -> UUID {
        let id = UUID()
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? nextGrokLabel() : trimmed
        settings.grokAccounts.append(GrokAccount(id: id, label: resolved, enabled: true))
        if settings.selectedGrokAccountId == nil {
            settings.selectedGrokAccountId = id
        }
        grokTokens[id] = ""
        grokStates[id] = .idle
        persistSettings()
        return id
    }

    /// Empty-state Add: import `~/.grok/auth.json` when it is unused, otherwise a blank row.
    @discardableResult
    func addGrokAccountOrImportAmbient() -> UUID {
        if let imported = importAmbientGrokAccountIfAvailable() {
            return imported
        }
        return addGrokAccount()
    }

    func renameGrokAccount(_ id: UUID, to label: String) {
        guard let index = settings.grokAccounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.grokAccounts[index].label = trimmed.isEmpty ? "Grok" : trimmed
        persistSettings()
    }

    func deleteGrokAccount(_ id: UUID) {
        let homePath = settings.grokAccounts.first(where: { $0.id == id })?.grokHomePath
        let ambient = settings.grokAccounts.first(where: { $0.id == id })?.usesAmbientAuthFile ?? false
        settings.grokAccounts.removeAll { $0.id == id }
        grokTokens[id] = nil
        grokStates[id] = nil
        KeychainStore.delete(.grokAccountOAuthToken(id))
        if !ambient {
            GrokAuth.removeManagedHomeIfSafe(homePath)
        }
        if settings.grokAccounts.isEmpty {
            settings.allowImplicitGrok = false
        }
        if settings.selectedGrokAccountId == id {
            settings.selectedGrokAccountId = nil
            settings.resolveSelectedGrokAccount(preferring: signedInGrokAccountIDs())
        }
        persistSettings()
    }

    func applyGrokRelogin(
        accountId: UUID,
        homePath: String,
        email: String?,
        ambient: Bool
    ) {
        guard let index = settings.grokAccounts.firstIndex(where: { $0.id == accountId }) else { return }
        let previousHome = settings.grokAccounts[index].grokHomePath
        let standardizedHome = GrokAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        settings.grokAccounts[index].grokHomePath = standardizedHome
        settings.grokAccounts[index].usesAmbientAuthFile = ambient
        GrokAccountIdentity.assignIdentity(
            email,
            to: accountId,
            accounts: &settings.grokAccounts
        )
        if previousHome != standardizedHome {
            GrokAuth.removeManagedHomeIfSafe(previousHome)
        }
        settings.selectedGrokAccountId = accountId
        persistSettings()
        Task { await refreshGrokAccount(accountId, userInitiated: true) }
    }

    @discardableResult
    func upsertGrokAccountFromHome(
        homePath: String,
        email: String?,
        ambient: Bool
    ) -> UUID? {
        let standardizedHome = GrokAuth.homeURL(path: homePath)?.path(percentEncoded: false) ?? homePath
        let creds = GrokAuth.homeURL(path: standardizedHome).flatMap { GrokAuth.loadAuthFile(home: $0) }
        let existed = Set(settings.grokAccounts.map(\.id))
        let id = GrokAccountIdentity.upsertFromHome(
            accounts: &settings.grokAccounts,
            homePath: standardizedHome,
            email: email ?? creds?.email,
            ambient: ambient,
            accessToken: creds?.accessToken,
            nextLabel: nextGrokLabel()
        )
        if !existed.contains(id) {
            grokTokens[id] = grokTokens[id] ?? ""
            grokStates[id] = .idle
        }
        settings.selectedGrokAccountId = id
        persistSettings()
        Task { await refreshGrokAccount(id, userInitiated: true) }
        return id
    }

    func setGrokOAuthToken(_ value: String, for id: UUID) {
        grokTokens[id] = value
        KeychainStore.set(value, account: .grokAccountOAuthToken(id))
    }

    @discardableResult
    func importAmbientGrokAccountIfAvailable() -> UUID? {
        if hasAmbientGrokAccount { return nil }
        guard let creds = GrokAuth.loadAuthFile() else { return nil }
        let email = GrokAccountIdentity.resolve(credentials: creds).display
        let ambientPath = GrokAuth.defaultHomeURL().path(percentEncoded: false)
        let existed = Set(settings.grokAccounts.map(\.id))
        let id = GrokAccountIdentity.upsertFromHome(
            accounts: &settings.grokAccounts,
            homePath: ambientPath,
            email: email,
            ambient: true,
            accessToken: creds.accessToken,
            nextLabel: nextGrokLabel()
        )
        if !existed.contains(id) {
            grokTokens[id] = grokTokens[id] ?? ""
            grokStates[id] = .idle
        }
        settings.selectedGrokAccountId = id
        persistSettings()
        Task { await refreshGrokAccount(id, userInitiated: true) }
        return id
    }

    fileprivate func persistGrokSecrets() {
        for account in settings.grokAccounts {
            KeychainStore.set(grokTokens[account.id], account: .grokAccountOAuthToken(account.id))
        }
    }

    fileprivate func loadGrokSecrets() {
        for account in settings.grokAccounts {
            grokTokens[account.id] = KeychainStore.get(.grokAccountOAuthToken(account.id)) ?? ""
            grokStates[account.id] = .idle
        }
    }

    fileprivate func refreshAllGrokAccounts(userInitiated: Bool, force: Bool = true) async {
        let accounts = settings.grokAccounts
        if accounts.isEmpty {
            if settings.allowImplicitGrok || settings.previewFixtures {
                await refreshImplicitGrok(userInitiated: userInitiated)
            } else {
                states[.grok] = .signedOut(ProviderKind.grok.signInHint)
            }
            return
        }
        var jobs: [GrokFetchJob] = []
        var generations: [UUID: Int] = [:]
        for (index, account) in accounts.enumerated() {
            let current = grokStates[account.id] ?? .idle
            if !force, !RefreshCoordinator.needsOpenRefresh(current, force: false) {
                continue
            }
            let key = RefreshCoordinator.key(.grok, accountID: account.id)
            generations[account.id] = refreshCoordinator.begin(key)
            if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
                grokStates[account.id] = .loading
            }
            jobs.append(grokJob(for: account, previous: current, variant: index))
        }
        syncRefreshingFlag()

        let results = await RefreshWork.mapConcurrent(jobs) { job in
            await RefreshWork.performGrok(job)
        }
        for item in results {
            let key = RefreshCoordinator.key(.grok, accountID: item.id)
            let generation = generations[item.id] ?? 0
            applyGrokResult(item, key: key, generation: generation)
            refreshCoordinator.finish(key, generation: generation)
        }
        syncRefreshingFlag()
        ensureActiveGrokAccount()
    }

    fileprivate func refreshGrokAccount(_ id: UUID, userInitiated: Bool) async {
        guard let account = settings.grokAccounts.first(where: { $0.id == id }) else { return }
        let current = grokStates[id] ?? .idle
        let key = RefreshCoordinator.key(.grok, accountID: id)
        let generation = refreshCoordinator.begin(key)
        syncRefreshingFlag()
        defer {
            refreshCoordinator.finish(key, generation: generation)
            syncRefreshingFlag()
        }
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            grokStates[id] = .loading
        }
        let index = settings.grokAccounts.firstIndex(where: { $0.id == id }) ?? 0
        applyGrokResult(
            await RefreshWork.performGrok(grokJob(for: account, previous: current, variant: index)),
            key: key,
            generation: generation
        )
    }

    private func grokJob(for account: GrokAccount, previous: ProviderLoadState, variant: Int) -> GrokFetchJob {
        GrokFetchJob(
            id: account.id,
            previous: previous,
            pastedToken: emptyToNil(grokTokens[account.id, default: ""]),
            useAmbientFile: account.usesAmbientAuthFile,
            allowEnvironment: false,
            grokHomePath: account.grokHomePath,
            email: account.email,
            preview: settings.previewFixtures,
            variant: variant
        )
    }

    private func applyGrokResult(_ item: AccountFetchResult, key: String, generation: Int) {
        guard refreshCoordinator.isCurrent(key, generation: generation) else { return }
        switch item.result {
        case .success(let snapshot):
            grokStates[item.id] = .ready(snapshot)
            recordGrokIdentity(snapshot.accountEmail, for: item.id)
        case .failure(let error):
            if let quota = error as? QuotaError, quota.isCancellation { return }
            grokStates[item.id] = ProviderLoadState.afterFailure(
                previous: item.previous,
                error: error,
                hasCredentials: hasGrokCredentials(item.id),
                signInHint: ProviderKind.grok.signInHint
            )
        }
    }

    fileprivate func refreshImplicitGrok(userInitiated: Bool) async {
        let current = states[.grok] ?? .idle
        if shouldShowLoading(current) || (userInitiated && current.showsUserInitiatedLoading) {
            states[.grok] = .loading
        }
        let item = await RefreshWork.performGrok(
            GrokFetchJob(
                id: Self.implicitGrokID,
                previous: current,
                pastedToken: nil,
                useAmbientFile: true,
                allowEnvironment: true,
                email: nil,
                preview: settings.previewFixtures,
                variant: 0
            )
        )
        switch item.result {
        case .success(let snapshot):
            states[.grok] = .ready(snapshot)
        case .failure(let error):
            if error.isCancellation { return }
            states[.grok] = ProviderLoadState.afterFailure(
                previous: current,
                error: error,
                hasCredentials: GrokAuth.loadAuthFile() != nil,
                signInHint: ProviderKind.grok.signInHint
            )
        }
    }

    private func grokState(for id: UUID?) -> ProviderLoadState {
        if settings.grokAccounts.isEmpty {
            if settings.previewFixtures {
                return states[.grok] ?? .idle
            }
            let implicit = states[.grok] ?? .idle
            switch implicit {
            case .idle:
                return .signedOut(ProviderKind.grok.signInHint)
            default:
                return implicit
            }
        }
        guard let id, settings.grokAccounts.contains(where: { $0.id == id }) else {
            return .signedOut(ProviderKind.grok.signInHint)
        }
        return grokStates[id] ?? .idle
    }

    private func signedInGrokAccountIDs() -> [UUID] {
        visibleGrokAccounts.compactMap { account in
            isSignedInGrok(account.id) ? account.id : nil
        }
    }

    private func ensureActiveGrokAccount() {
        let before = settings.selectedGrokAccountId
        settings.resolveSelectedGrokAccount(preferring: signedInGrokAccountIDs())
        if settings.selectedGrokAccountId != before {
            persistSettings()
        }
    }

    func grokDisplayTitle(for id: UUID) -> String? {
        grokDisplayTitles()[id]
    }

    func grokDisplayTitle(for account: GrokAccount) -> String {
        grokDisplayTitle(for: account.id) ?? account.displayTitle
    }

    private func grokDisplayTitles() -> [UUID: String] {
        let inputs = settings.grokAccounts.map { account in
            GrokAccountIdentity.CardInput(
                id: account.id,
                storedEmail: account.email,
                snapshotEmail: grokStates[account.id]?.snapshot?.accountEmail,
                label: account.label,
                uniqueFallback: GrokAccountIdentity.uniqueFallback(
                    account: account,
                    pastedToken: emptyToNil(grokTokens[account.id, default: ""])
                )
            )
        }
        return GrokAccountIdentity.cardTitles(inputs)
    }

    private func recordGrokIdentity(_ identity: String?, for id: UUID) {
        guard let index = settings.grokAccounts.firstIndex(where: { $0.id == id }) else { return }
        let before = settings.grokAccounts[index].email
        GrokAccountIdentity.assignIdentity(
            identity,
            to: id,
            accounts: &settings.grokAccounts
        )
        if settings.grokAccounts[index].email != before {
            persistSettings()
        }
    }
}

struct AccountCardRow: Identifiable, Equatable {
    var id: String
    var email: String?
    var fallbackTitle: String
    var state: ProviderLoadState
    var hasCredentials: Bool = false
    var recoveryTitle: String = "Retry"

    var showsRecoveryAction: Bool {
        switch state {
        case .failure, .stale:
            return true
        case .signedOut:
            return hasCredentials || hasKnownEmail
        default:
            return false
        }
    }

    var hasKnownEmail: Bool {
        if let email, !email.isEmpty { return true }
        return false
    }

    func displayTitle(for provider: ProviderKind) -> String {
        if let email, !email.isEmpty {
            return email
        }
        if let email = state.snapshot?.accountEmail, !email.isEmpty {
            return email
        }
        if case .signedOut(let message) = state, !hasKnownEmail, !hasCredentials {
            return Self.signedOutTitle(provider: provider, message: message)
        }
        return fallbackTitle
    }

    static func signedOutTitle(provider: ProviderKind, message: String) -> String {
        if provider == .cursor, CursorAuth.isRejectedSessionMessage(message) {
            return "Session rejected"
        }
        return "Not signed in"
    }

    func compactStatus(treatIdleAsUpdating: Bool) -> String? {
        switch state {
        case .ready(let snapshot):
            return snapshot.windows.isEmpty ? "No usage windows" : nil
        case .stale(_, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 80 { return trimmed }
            return String(trimmed.prefix(77)) + "…"
        case .loading:
            return "Updating…"
        case .idle:
            return treatIdleAsUpdating ? "Updating…" : "Waiting…"
        case .signedOut:
            if hasCredentials || hasKnownEmail {
                return "Couldn’t refresh"
            }
            return nil
        case .failure(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 80 { return trimmed }
            return String(trimmed.prefix(77)) + "…"
        }
    }
}

struct OverallSection: Identifiable, Equatable {
    var provider: ProviderKind
    var rows: [OverallAccountRow]

    var id: ProviderKind { provider }
}

struct OverallAccountRow: Identifiable, Equatable {
    var provider: ProviderKind
    var card: AccountCardRow
    var hint: String

    var id: String { "\(provider.rawValue):\(card.id)" }
}
