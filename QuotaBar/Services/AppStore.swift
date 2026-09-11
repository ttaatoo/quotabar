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
    @Published var grokOAuthToken: String = ""

    private var pollTimer: Timer?
    private var clockTimer: Timer?

    private init() {
        var loaded = ConfigStore.load()
        loaded.launchAtLogin = LaunchAtLogin.isEnabled
        settings = loaded
        states = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, .idle) })
        cursorCookie = KeychainStore.get(.cursorCookie) ?? ""
        glmAPIKey = KeychainStore.get(.glmAPIKey) ?? ""
        grokOAuthToken = KeychainStore.get(.grokOAuthToken) ?? ""
        loadChatGPTSecrets()
    }

    var selected: ProviderKind { settings.selectedProvider }

    var visibleChatGPTAccounts: [ChatGPTAccount] {
        settings.visibleChatGPTAccounts
    }

    var selectedState: ProviderLoadState {
        if selected == .chatgpt {
            return activeChatGPTState
        }
        return states[selected] ?? .idle
    }

    /// Card in the ChatGPT tab that is active for the menu bar.
    /// Implicit / empty ChatGPT (no saved accounts) has a single card that is active.
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
        states[.grok]?.snapshot?.accountEmail
            ?? GrokAuth.loadAuthFile()?.email
    }

    /// One card per ChatGPT account; Cursor / GLM / Grok are a single card each.
    var accountCards: [AccountCardRow] {
        if selected == .chatgpt {
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
                    hasCredentials: credentials
                )
            }
        }
        let state = states[selected] ?? .idle
        let email = state.snapshot?.accountEmail
        let fallback: String
        switch state {
        case .signedOut:
            fallback = "Not signed in"
        case .ready:
            fallback = "Email unknown"
        default:
            fallback = selected.title
        }
        return [
            AccountCardRow(
                id: selected.rawValue,
                email: email,
                fallbackTitle: fallback,
                state: state,
                hasCredentials: !state.isSignedOut
            )
        ]
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
        switch chatgptStates[id] {
        case .ready:
            return true
        case .failure, .loading:
            return hasChatGPTCredentials(id)
        default:
            return false
        }
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
        KeychainStore.set(grokOAuthToken, account: .grokOAuthToken)
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

    func refreshCard(_ cardID: String) async {
        if selected == .chatgpt, let id = UUID(uuidString: cardID),
           settings.chatgptAccounts.contains(where: { $0.id == id }) {
            await refreshChatGPTAccount(id, userInitiated: true)
            return
        }
        await refreshSelected()
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
        var jobs: [ChatGPTFetchJob] = []
        for (index, account) in accounts.enumerated() {
            let current = chatgptStates[account.id] ?? .idle
            if shouldShowLoading(current) || (userInitiated && current.isSignedOut) {
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

        var results: [(UUID, ProviderLoadState, Result<UsageSnapshot, Error>)] = []
        await withTaskGroup(of: (UUID, ProviderLoadState, Result<UsageSnapshot, Error>).self) { group in
            for job in jobs {
                group.addTask {
                    await Self.performChatGPTFetch(job)
                }
            }
            for await item in group {
                results.append(item)
            }
        }

        for (id, previous, result) in results {
            switch result {
            case .success(let snapshot):
                chatgptStates[id] = .ready(snapshot)
                recordChatGPTEmail(snapshot.accountEmail, for: id)
            case .failure(let error):
                chatgptStates[id] = chatGPTFailureState(
                    previous: previous,
                    id: id,
                    error: error
                )
            }
        }
        ensureActiveChatGPTAccount()
    }

    private func refreshChatGPTAccount(_ id: UUID, userInitiated: Bool) async {
        guard settings.chatgptAccounts.contains(where: { $0.id == id }) else { return }
        let current = chatgptStates[id] ?? .idle
        // Keep last meters while refreshing. Opening the popover used to
        // flash every card to "Updating…" and then paint a false Sign in
        // if one fetch failed.
        if shouldShowLoading(current) || (userInitiated && current.isSignedOut) {
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
        let (_, previous, result) = await Self.performChatGPTFetch(job)
        switch result {
        case .success(let snapshot):
            chatgptStates[id] = .ready(snapshot)
            recordChatGPTEmail(snapshot.accountEmail, for: id)
        case .failure(let error):
            chatgptStates[id] = chatGPTFailureState(
                previous: previous,
                id: id,
                error: error
            )
        }
    }

    private static func performChatGPTFetch(
        _ job: ChatGPTFetchJob
    ) async -> (UUID, ProviderLoadState, Result<UsageSnapshot, Error>) {
        do {
            let snapshot: UsageSnapshot
            if job.preview {
                snapshot = try FixtureLoader.load(
                    .chatgpt,
                    now: Date(),
                    variant: job.variant,
                    emailOverride: job.email
                )
            } else {
                snapshot = try await ChatGPTClient.fetch(
                    cookie: job.cookie,
                    pastedJSON: job.json,
                    codexHomePath: job.home,
                    allowAmbientCodex: job.allowAmbient,
                    expectedEmail: job.email
                )
            }
            return (job.id, job.previous, .success(snapshot))
        } catch {
            return (job.id, job.previous, .failure(error))
        }
    }

    /// Auth failure without credentials → signed out. Anything else keeps the
    /// last snapshot so switching or a sibling fetch cannot wipe a good card.
    private func chatGPTFailureState(
        previous: ProviderLoadState,
        id: UUID,
        error: Error
    ) -> ProviderLoadState {
        let message: String
        let authFailure: Bool
        if let quota = error as? QuotaError {
            message = quota.errorDescription ?? ProviderKind.chatgpt.signInHint
            authFailure = quota.isAuthFailure
        } else {
            message = error.localizedDescription
            authFailure = false
        }

        if case .ready(let snapshot) = previous {
            return .ready(snapshot)
        }
        if authFailure, !hasChatGPTCredentials(id) {
            return .signedOut(message)
        }
        return .failure(message)
    }

    /// Uses ~/.codex/auth.json when no ChatGPT account has been added yet.
    /// Does not persist a new account on each launch.
    private func refreshImplicitChatGPT(userInitiated: Bool) async {
        let current = states[.chatgpt] ?? .idle
        if shouldShowLoading(current) || (userInitiated && current.isSignedOut) {
            states[.chatgpt] = .loading
        }
        do {
            let snapshot = try await ChatGPTClient.fetch(
                cookie: nil,
                pastedJSON: nil,
                allowAmbientCodex: true
            )
            states[.chatgpt] = .ready(snapshot)
        } catch {
            if case .ready(let snapshot) = current {
                states[.chatgpt] = .ready(snapshot)
            } else if let quota = error as? QuotaError, quota.isAuthFailure {
                states[.chatgpt] = .signedOut(quota.errorDescription ?? ProviderKind.chatgpt.signInHint)
            } else {
                states[.chatgpt] = .failure(error.localizedDescription)
            }
        }
    }

    private func refreshChatGPTPreviewFallback(userInitiated _: Bool) async {
        let current = states[.chatgpt] ?? .idle
        if shouldShowLoading(current) {
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
            let auth = chatGPTAuthInputs(for: id)
            return try await ChatGPTClient.fetch(
                cookie: auth.cookie,
                pastedJSON: auth.json,
                codexHomePath: auth.home,
                allowAmbientCodex: auth.allowAmbient,
                expectedEmail: auth.email
            )
        case .glm:
            return try await GLMClient.fetch(apiKey: emptyToNil(glmAPIKey), region: settings.glmRegion)
        case .grok:
            return try await GrokClient.fetch(pastedToken: emptyToNil(grokOAuthToken))
        }
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static let implicitChatGPTID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

private struct ChatGPTFetchJob {
    var id: UUID
    var previous: ProviderLoadState
    var cookie: String?
    var json: String?
    var home: String?
    var allowAmbient: Bool
    var email: String?
    var preview: Bool
    var variant: Int
}

struct ChatGPTDisplayRow: Identifiable, Equatable {
    var id: UUID
    var account: ChatGPTAccount?
    var state: ProviderLoadState
}

struct AccountCardRow: Identifiable, Equatable {
    var id: String
    var email: String?
    var fallbackTitle: String
    var state: ProviderLoadState
    var hasCredentials: Bool = false
}
