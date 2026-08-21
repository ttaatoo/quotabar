import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings
    @Published var states: [ProviderKind: ProviderLoadState]
    @Published var now: Date = Date()
    @Published var isRefreshing = false

    @Published var cursorCookie: String = ""
    @Published var chatgptCookie: String = ""
    @Published var chatgptJSON: String = ""
    @Published var glmAPIKey: String = ""

    private var pollTimer: Timer?
    private var clockTimer: Timer?

    private init() {
        var loaded = ConfigStore.load()
        loaded.launchAtLogin = LaunchAtLogin.isEnabled
        settings = loaded
        states = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, .idle) })
        cursorCookie = KeychainStore.get(.cursorCookie) ?? ""
        chatgptCookie = KeychainStore.get(.chatgptCookie) ?? ""
        chatgptJSON = KeychainStore.get(.chatgptJSON) ?? ""
        glmAPIKey = KeychainStore.get(.glmAPIKey) ?? ""
    }

    var selected: ProviderKind { settings.selectedProvider }

    var selectedState: ProviderLoadState {
        states[selected] ?? .idle
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
            Task { @MainActor in
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
            Task { @MainActor in
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
        KeychainStore.set(chatgptCookie, account: .chatgptCookie)
        KeychainStore.set(chatgptJSON, account: .chatgptJSON)
        KeychainStore.set(glmAPIKey, account: .glmAPIKey)
    }

    func persistSettings() {
        settings.sanitize()
        ConfigStore.save(settings)
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

    private func fetchLive(_ provider: ProviderKind) async throws -> UsageSnapshot {
        switch provider {
        case .cursor:
            return try await CursorClient.fetch(cookie: emptyToNil(cursorCookie))
        case .chatgpt:
            return try await ChatGPTClient.fetch(
                cookie: emptyToNil(chatgptCookie),
                pastedJSON: emptyToNil(chatgptJSON)
            )
        case .glm:
            return try await GLMClient.fetch(apiKey: emptyToNil(glmAPIKey), region: settings.glmRegion)
        }
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
