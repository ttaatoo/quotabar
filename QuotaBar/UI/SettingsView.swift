import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    private enum AccountKind {
        case chatgpt
        case opencodeGo
    }

    @State private var section: SettingsSection = .providers
    @State private var didUnlockSection = false
    @State private var renameKind: AccountKind = .chatgpt
    @State private var renameID: UUID?
    @State private var renameLabel = ""
    @State private var deleteKind: AccountKind = .chatgpt
    @State private var deleteID: UUID?
    @FocusState private var focusedField: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Theme.settingsHairline)
                .frame(width: 1)
            pane
        }
        .background(Theme.settingsPageFill)
        .frame(minWidth: Theme.settingsMinWidth, minHeight: Theme.settingsMinHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            if !didUnlockSection {
                section = SettingsSection.pane(for: store.selected)
                didUnlockSection = true
            }
        }
        .onChange(of: store.cursorCookie) { _, _ in store.persistSecrets() }
        .onChange(of: store.glmAPIKey) { _, _ in store.persistSecrets() }
        .onChange(of: store.grokOAuthToken) { _, _ in store.persistSecrets() }
        .onChange(of: store.settings) { _, _ in
            store.persistSettings()
            store.restartPolling()
        }
        .onChange(of: store.settings.previewFixtures) { _, _ in
            Task { await store.refreshAll() }
        }
        .onDisappear {
            store.persistSecrets()
            store.persistSettings()
        }
        .alert("Rename account", isPresented: renamePresented) {
            TextField("Label", text: $renameLabel)
            Button("Save") {
                if let renameID = renameID {
                    switch renameKind {
                    case .chatgpt:
                        store.renameChatGPTAccount(renameID, to: renameLabel)
                    case .opencodeGo:
                        store.renameOpenCodeGoAccount(renameID, to: renameLabel)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            deleteKind == .chatgpt ? "Delete this ChatGPT account?" : "Delete this OpenCode account?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteID = deleteID {
                    switch deleteKind {
                    case .chatgpt:
                        store.deleteChatGPTAccount(deleteID)
                    case .opencodeGo:
                        store.deleteOpenCodeGoAccount(deleteID)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteKind == .chatgpt
                 ? "The Keychain cookie and JSON for this account are removed. A private Codex home is deleted when it belongs to QuotaBar; ~/.codex/auth.json is never deleted."
                 : "The Keychain API key for this OpenCode account is removed. Other accounts stay.")
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SettingsNavGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.rawValue)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.settingsTertiary)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                        ForEach(group.sections) { item in
                            SettingsNavItem(
                                section: item,
                                selected: section == item,
                                badge: sidebarBadge(for: item),
                                action: { select(item) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(width: Theme.settingsSidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.settingsSidebarFill)
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: moveSection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private var pane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneBody
            }
            .padding(.horizontal, Theme.settingsContentPadding)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: Theme.settingsContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.settingsPageFill)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch section {
        case .providers:
            providersPane
        case .cursor:
            cursorPane
        case .chatgpt:
            chatgptPane
        case .opencodeGo:
            opencodeGoPane
        case .glm:
            glmPane
        case .grok:
            grokPane
        case .display:
            displayPane
        case .about:
            aboutPane
        }
    }

    private var providersPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.providers.paneTitle,
                subtitle: "Turn off a provider to hide it from the popover. Credentials stay saved."
            )
            SettingsGroup {
                ForEach(Array(ProviderKind.allCases.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        SettingsInsetHairline()
                    }
                    providerRow(provider)
                }
            }
            SettingsCaption(text: "At least one provider stays visible in the menu-bar popover.")
        }
    }

    private var cursorPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.cursor.paneTitle,
                subtitle: "Leave the cookie empty to use the local Cursor.app token."
            )
            SettingsGroup {
                statusRow(
                    title: cursorStatusTitle,
                    subtitle: cursorStatusSubtitle
                )
                SettingsInsetHairline()
                SettingsLabeledField(label: "Cookie (optional)") {
                    SettingsSecretField(
                        placeholder: "WorkosCursorSessionToken or Cookie header",
                        text: $store.cursorCookie,
                        focusID: "cursor.cookie",
                        focusedField: $focusedField
                    )
                }
            }
            SettingsCaption(text: "Or paste a WorkosCursorSessionToken / full Cookie header.")
        }
    }

    private var chatgptPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.chatgpt.paneTitle,
                subtitle: "Add account runs `codex login` in your default browser. Extra accounts use a private Codex home so ~/.codex/auth.json is not overwritten."
            ) {
                if !store.settings.chatgptAccounts.isEmpty {
                    SettingsSecondaryButton(title: "Add account", systemImage: "plus") {
                        CodexLoginPresenter.shared.begin(store: store)
                    }
                }
            }

            if store.settings.chatgptAccounts.isEmpty {
                SettingsGroup {
                    SettingsEmptyState(
                        symbol: ProviderKind.chatgpt.settingsSymbol,
                        title: "No ChatGPT accounts",
                        message: "Add an account to sign in with Codex in your browser, or paste a session cookie under Advanced after you add one.",
                        actionTitle: "Add account"
                    ) {
                        CodexLoginPresenter.shared.begin(store: store)
                    }
                }
            } else {
                SettingsGroup {
                    ForEach(Array(store.settings.chatgptAccounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            SettingsInsetHairline()
                        }
                        chatgptAccountRow(account)
                    }
                }
            }
        }
    }

    private var opencodeGoPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.opencodeGo.paneTitle,
                subtitle: "Paste a Go API key per account. QuotaBar calls GET /zen/go/v1/usage with Bearer only."
            ) {
                if !store.settings.opencodeGoAccounts.isEmpty {
                    SettingsSecondaryButton(title: "Add account", systemImage: "plus") {
                        addOpenCodeAccount()
                    }
                }
            }

            if store.settings.opencodeGoAccounts.isEmpty {
                SettingsGroup {
                    SettingsEmptyState(
                        symbol: ProviderKind.opencodeGo.settingsSymbol,
                        title: "No OpenCode accounts",
                        message: "Add an account, then paste a Go API key. QuotaBar also reads OPENCODE_GO_API_KEY when no accounts exist yet.",
                        actionTitle: "Add account"
                    ) {
                        addOpenCodeAccount()
                    }
                }
            } else {
                SettingsGroup {
                    ForEach(Array(store.settings.opencodeGoAccounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            SettingsInsetHairline()
                        }
                        opencodeAccountRow(account)
                    }
                }
                SettingsCaption(text: "An optional label is enough. The usage API does not always return an email.")
            }
        }
    }

    private var glmPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.glm.paneTitle,
                subtitle: "Stored in the Keychain. Also accepted from ~/.config/quotabar/config.json or Z_AI_API_KEY."
            )
            SettingsGroup {
                SettingsLabeledField(label: "API key") {
                    SettingsSecretField(
                        placeholder: "API key",
                        text: $store.glmAPIKey,
                        focusID: "glm.key",
                        focusedField: $focusedField
                    )
                }
                SettingsInsetHairline()
                SettingsRow(title: "Region", subtitle: "Global uses api.z.ai. China uses open.bigmodel.cn.") {
                    Picker("Region", selection: $store.settings.glmRegion) {
                        ForEach(GLMRegion.allCases) { region in
                            Text(region.title).tag(region)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minHeight: Theme.settingsHitTarget)
                    .tint(Theme.settingsAccent)
                }
            }
        }
    }

    private var grokPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.grok.paneTitle,
                subtitle: "QuotaBar reads ~/.grok/auth.json from `grok login`. It never writes or refreshes that file."
            )
            SettingsGroup {
                statusRow(
                    title: grokStatusTitle,
                    subtitle: grokStatusSubtitle
                )
                SettingsInsetHairline()
                SettingsLabeledField(label: "SuperGrok bearer (optional)") {
                    SettingsSecretField(
                        placeholder: "SuperGrok bearer",
                        text: $store.grokOAuthToken,
                        warning: grokTokenRejected,
                        focusID: "grok.token",
                        focusedField: $focusedField
                    )
                }
            }
            if grokTokenRejected {
                SettingsCaption(
                    text: "Rejected: paste a SuperGrok bearer, not an xai- management key or cookie.",
                    tone: .warning
                )
            } else {
                SettingsCaption(text: "Optional if `grok login` already wrote ~/.grok/auth.json. Also accepted from GROK_OAUTH_TOKEN.")
            }
        }
    }

    private var displayPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeader(
                title: SettingsSection.display.paneTitle,
                subtitle: "How often QuotaBar polls, and how the menu-bar number reads."
            )
            SettingsGroup {
                SettingsRow(title: "Poll interval") {
                    Picker("Poll interval", selection: $store.settings.pollIntervalSeconds) {
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                        Text("10 min").tag(600)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minHeight: Theme.settingsHitTarget)
                    .tint(Theme.settingsAccent)
                }
                SettingsInsetHairline()
                SettingsRow(title: "Show") {
                    Picker("Show", selection: $store.settings.displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .frame(minHeight: Theme.settingsHitTarget)
                    .tint(Theme.settingsAccent)
                }
            }
            SettingsGroup {
                SettingsRow(title: "Launch at login") {
                    Toggle("Launch at login", isOn: launchBinding)
                        .labelsHidden()
                        .tint(Theme.settingsAccent)
                        .frame(minHeight: Theme.settingsHitTarget)
                }
                SettingsInsetHairline()
                SettingsRow(
                    title: "Preview fixtures",
                    subtitle: "Loads bundled sample JSON so the popover can be screenshot without accounts."
                ) {
                    Toggle("Preview fixtures", isOn: $store.settings.previewFixtures)
                        .labelsHidden()
                        .tint(Theme.settingsAccent)
                        .frame(minHeight: Theme.settingsHitTarget)
                }
            }
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                QuotaBarSettingsMark()
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuotaBar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.settingsPrimary)
                    Text("Remaining quota for Cursor, ChatGPT, GLM, Grok, and OpenCode Go in the menu bar.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.settingsSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            SettingsGroup {
                SettingsRow(title: "Version") {
                    Text(appVersion)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.settingsPrimary)
                }
            }
            SettingsCaption(text: "Unofficial usage endpoints can change without notice. Secrets stay in the Keychain; QuotaBar never phones home.")
        }
    }

    private func providerRow(_ provider: ProviderKind) -> some View {
        let on = store.settings.enabledProviders.contains(provider)
        let onlyOn = on && store.settings.enabledProviders.count == 1
        let tint = Theme.settingsTint(for: provider)
        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: provider.settingsSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.settingsPrimary)
                Text(provider.settingsBlurb)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.settingsSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(provider.title, isOn: providerBinding(provider))
                .labelsHidden()
                .tint(Theme.settingsAccent)
                .disabled(onlyOn)
                .help(onlyOn
                      ? "At least one provider must stay visible"
                      : (on ? "Hide \(provider.title) in the popover" : "Show \(provider.title) in the popover"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.settingsRowHeight)
    }

    private func chatgptAccountRow(_ account: ChatGPTAccount) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.settingsPrimary)
                        .lineLimit(1)
                    if let email = account.email,
                       !email.isEmpty,
                       account.label.caseInsensitiveCompare(email) != .orderedSame {
                        Text(account.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.settingsSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsIconButton(systemName: "arrow.clockwise", help: "Re-login") {
                    CodexLoginPresenter.shared.beginRelogin(store: store, accountId: account.id)
                }
                SettingsIconButton(systemName: "pencil", help: "Rename") {
                    renameKind = .chatgpt
                    renameID = account.id
                    renameLabel = account.label
                }
                SettingsIconButton(systemName: "trash", help: "Delete", destructive: true) {
                    deleteKind = .chatgpt
                    deleteID = account.id
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            SettingsAdvancedDisclosure(title: "Advanced: cookie / JSON") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session cookie")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.settingsSecondary)
                        SettingsSecretField(
                            placeholder: "Session cookie",
                            text: cookieBinding(account.id),
                            focusID: "chatgpt.cookie.\(account.id.uuidString)",
                            focusedField: $focusedField
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Usage JSON")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.settingsSecondary)
                        SettingsCaption(text: "Optional pasted wham/usage JSON when the live API has no percentages.")
                        SettingsCodeEditor(text: jsonBinding(account.id))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
    }

    private func opencodeAccountRow(_ account: OpenCodeGoAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.settingsPrimary)
                        .lineLimit(1)
                    if let email = account.email,
                       !email.isEmpty,
                       account.label.caseInsensitiveCompare(email) != .orderedSame {
                        Text(account.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.settingsSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsIconButton(systemName: "pencil", help: "Rename") {
                    renameKind = .opencodeGo
                    renameID = account.id
                    renameLabel = account.label
                }
                SettingsIconButton(systemName: "trash", help: "Delete", destructive: true) {
                    deleteKind = .opencodeGo
                    deleteID = account.id
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.settingsSecondary)
                SettingsSecretField(
                    placeholder: "API key",
                    text: opencodeKeyBinding(account.id),
                    focusID: "opencode.key.\(account.id.uuidString)",
                    focusedField: $focusedField
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func statusRow(title: String, subtitle: String) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }

    private var cursorStatusTitle: String {
        if let email = store.cursorEmail, !email.isEmpty {
            return email
        }
        return "Cursor.app token"
    }

    private var cursorStatusSubtitle: String {
        if let email = store.cursorEmail, !email.isEmpty {
            return "Signed in. Cookie paste is an optional fallback."
        }
        return "No email from Cursor yet. Sign in to Cursor.app, or paste a cookie below."
    }

    private var grokStatusTitle: String {
        if let email = store.grokEmail, !email.isEmpty {
            return email
        }
        return "Not signed in"
    }

    private var grokStatusSubtitle: String {
        if let email = store.grokEmail, !email.isEmpty {
            return "Identity from ~/.grok/auth.json"
        }
        return "Run `grok login` in Terminal, then Refresh."
    }

    private var grokTokenRejected: Bool {
        let raw = store.grokOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        return GrokAuth.normalizedOAuthToken(raw) == nil
    }

    private func sidebarBadge(for item: SettingsSection) -> String? {
        guard let provider = item.provider else { return nil }
        return store.settings.enabledProviders.contains(provider) ? nil : "Off"
    }

    private func select(_ item: SettingsSection) {
        section = item
    }

    private func moveSection(_ direction: MoveCommandDirection) {
        let items = SettingsSection.allCases
        guard let index = items.firstIndex(of: section) else { return }
        switch direction {
        case .up:
            if index > 0 { select(items[index - 1]) }
        case .down:
            if index < items.count - 1 { select(items[index + 1]) }
        default:
            break
        }
    }

    private func addOpenCodeAccount() {
        let id = store.addOpenCodeGoAccount()
        focusedField = "opencode.key.\(id.uuidString)"
    }

    private func providerBinding(_ provider: ProviderKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledProviders.contains(provider) },
            set: { store.setEnabled(provider, enabled: $0) }
        )
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let short = short, !short.isEmpty {
            return short
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build = build, !build.isEmpty {
            return build
        }
        return "-"
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameID != nil },
            set: { if !$0 { renameID = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteID != nil },
            set: { if !$0 { deleteID = nil } }
        )
    }

    private func cookieBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.chatgptCookies[id, default: ""] },
            set: { store.setChatGPTCookie($0, for: id) }
        )
    }

    private func opencodeKeyBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.opencodeGoAPIKeys[id, default: ""] },
            set: { store.setOpenCodeGoAPIKey($0, for: id) }
        )
    }

    private func jsonBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.chatgptJSONs[id, default: ""] },
            set: { store.setChatGPTJSON($0, for: id) }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }
}

private extension ProviderKind {
    var settingsBlurb: String {
        switch self {
        case .cursor:
            return "Local Cursor.app token, optional cookie"
        case .chatgpt:
            return "Multi-account via `codex login`"
        case .glm:
            return "z.ai / BigModel API key"
        case .grok:
            return "SuperGrok via `grok login`"
        case .opencodeGo:
            return "Multi-account Go API keys"
        }
    }
}
