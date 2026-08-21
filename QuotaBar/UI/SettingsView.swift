import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    @State private var renameID: UUID?
    @State private var renameLabel = ""
    @State private var deleteID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                providersCard
                cursorCard
                chatgptCard
                glmCard
                grokCard
                displayCard
                aboutCard
            }
            .padding(Theme.settingsPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.settingsPageFill)
        .frame(minWidth: Theme.settingsMinWidth, minHeight: Theme.settingsMinHeight)
        .preferredColorScheme(.dark)
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
                    store.renameChatGPTAccount(renameID, to: renameLabel)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this ChatGPT account?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteID = deleteID {
                    store.deleteChatGPTAccount(deleteID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Keychain cookie and JSON for this account are removed. A private Codex home is deleted when it belongs to QuotaBar; ~/.codex/auth.json is never deleted.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            QuotaBarSettingsMark()
                .frame(width: 36, height: 36)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("QuotaBar")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("Remaining quota for Cursor, ChatGPT, GLM, and Grok — in the menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(appVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private var providersCard: some View {
        SettingsCard(
            title: "Providers",
            symbol: "switch.2",
            tint: Theme.logoBlue,
            hint: "Turn off a provider to hide it from the popover."
        ) {
            HStack(spacing: 6) {
                ForEach(ProviderKind.allCases) { provider in
                    providerChip(provider)
                }
            }
        }
    }

    private var cursorCard: some View {
        SettingsCard(
            title: "Cursor",
            symbol: ProviderKind.cursor.settingsSymbol,
            tint: Theme.settingsTint(for: .cursor),
            hint: "Leave empty to use the local Cursor.app token."
        ) {
            if let email = store.cursorEmail, !email.isEmpty {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
            }
            SettingsSecretField(placeholder: "Cookie (optional)", text: $store.cursorCookie)
            Text("Or paste a WorkosCursorSessionToken / full Cookie header.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var chatgptCard: some View {
        SettingsCard(
            title: "ChatGPT",
            symbol: ProviderKind.chatgpt.settingsSymbol,
            tint: Theme.settingsTint(for: .chatgpt),
            hint: "Add account runs `codex login` in your default browser. Extra accounts use a private Codex home so ~/.codex/auth.json is not overwritten."
        ) {
            Button {
                CodexLoginPresenter.shared.begin(store: store)
            } label: {
                Label("Add account", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.settingsHitTarget)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.logoPurple.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)

            if store.settings.chatgptAccounts.isEmpty {
                Text("No accounts yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.settings.chatgptAccounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            Divider().overlay(Theme.settingsHairline)
                        }
                        accountRow(account)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var glmCard: some View {
        SettingsCard(
            title: "GLM",
            symbol: ProviderKind.glm.settingsSymbol,
            tint: Theme.settingsTint(for: .glm),
            hint: "Stored in the Keychain. Also accepted from ~/.config/quotabar/config.json or Z_AI_API_KEY."
        ) {
            SettingsSecretField(placeholder: "API key", text: $store.glmAPIKey)
            Picker("Region", selection: $store.settings.glmRegion) {
                ForEach(GLMRegion.allCases) { region in
                    Text(region.title).tag(region)
                }
            }
            .frame(minHeight: Theme.settingsHitTarget)
        }
    }

    private var grokCard: some View {
        SettingsCard(
            title: "Grok",
            symbol: ProviderKind.grok.settingsSymbol,
            tint: Theme.settingsTint(for: .grok),
            hint: "QuotaBar reads ~/.grok/auth.json from `grok login`. It never writes or refreshes that file."
        ) {
            if let email = store.grokEmail, !email.isEmpty {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Not signed in. Run `grok login` in Terminal, then Refresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSecretField(placeholder: "SuperGrok bearer (optional)", text: $store.grokOAuthToken)
            if grokTokenRejected {
                Text("Rejected: paste a SuperGrok bearer, not an xai- management key or cookie.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            } else {
                Text("Optional if `grok login` already wrote ~/.grok/auth.json. Also accepted from GROK_OAUTH_TOKEN.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var grokTokenRejected: Bool {
        let raw = store.grokOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        return GrokAuth.normalizedOAuthToken(raw) == nil
    }

    private var displayCard: some View {
        SettingsCard(
            title: "Display",
            symbol: "slider.horizontal.3",
            tint: Theme.secondary,
            hint: nil
        ) {
            Picker("Poll interval", selection: $store.settings.pollIntervalSeconds) {
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("2 min").tag(120)
                Text("5 min").tag(300)
                Text("10 min").tag(600)
            }
            .frame(minHeight: Theme.settingsHitTarget)

            VStack(alignment: .leading, spacing: 6) {
                Text("Show")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primary)
                Picker("Show", selection: $store.settings.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minHeight: Theme.settingsHitTarget)
            }

            Toggle("Launch at login", isOn: launchBinding)
                .frame(minHeight: Theme.settingsHitTarget)
                .tint(Theme.logoBlue)
            Toggle("Preview fixtures", isOn: $store.settings.previewFixtures)
                .frame(minHeight: Theme.settingsHitTarget)
                .tint(Theme.logoBlue)
            Text("Preview loads bundled sample JSON so the popover can be screenshot without accounts.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var aboutCard: some View {
        SettingsCard(
            title: "About",
            symbol: "info.circle",
            tint: Theme.secondary,
            hint: nil
        ) {
            HStack {
                Text("Version")
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(appVersion)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.primary)
            }
            .frame(minHeight: Theme.settingsHitTarget)
            Text("Unofficial usage endpoints can change without notice. Secrets stay in the Keychain; QuotaBar never phones home.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accountRow(_ account: ChatGPTAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    if let email = account.email,
                       !email.isEmpty,
                       account.label.caseInsensitiveCompare(email) != .orderedSame {
                        Text(account.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                iconButton("pencil", help: "Rename") {
                    renameID = account.id
                    renameLabel = account.label
                }
                iconButton("trash", help: "Delete", destructive: true) {
                    deleteID = account.id
                }
            }

            DisclosureGroup("Advanced — cookie / JSON") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSecretField(placeholder: "Session cookie", text: cookieBinding(account.id))
                    Text("Optional pasted wham/usage JSON when the live API has no percentages.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                    jsonEditor(for: account.id)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
        }
    }

    private func providerChip(_ provider: ProviderKind) -> some View {
        let on = store.settings.enabledProviders.contains(provider)
        let tint = Theme.settingsTint(for: provider)
        return Button {
            store.setEnabled(provider, enabled: !on)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: provider.settingsSymbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(provider.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(on ? Theme.primary : Theme.secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.settingsHitTarget)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? tint.opacity(0.22) : Theme.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(on ? tint.opacity(0.45) : Theme.settingsHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(on ? "Hide \(provider.title) in the popover" : "Show \(provider.title) in the popover")
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? Color.red.opacity(0.85) : Theme.secondary)
                .frame(width: Theme.settingsHitTarget, height: Theme.settingsHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.fieldFill)
                )
        }
        .buttonStyle(.plain)
        .help(help)
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
        return "—"
    }

    @ViewBuilder
    private func jsonEditor(for id: UUID) -> some View {
        TextEditor(text: jsonBinding(id))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Theme.primary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 80, maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.settingsFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.settingsHairline, lineWidth: 1)
            )
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

private struct SettingsSecretField: View {
    let placeholder: String
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.primary)
            .textContentType(.password)
            .focusEffectDisabled()

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(revealed ? "Hide" : "Show")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: Theme.settingsFieldHeight, maxHeight: Theme.settingsFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.settingsFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.settingsHairline, lineWidth: 1)
        )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var hint: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.18))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    if let hint = hint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content()
        }
        .padding(Theme.settingsCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous)
                .fill(Theme.settingsCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous)
                .strokeBorder(Theme.settingsHairline, lineWidth: 1)
        )
    }
}

private struct QuotaBarSettingsMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            cap(Theme.logoBlue, 0.42)
            cap(Theme.logoPurple, 0.62)
            cap(Theme.logoGreen, 0.82)
            cap(Theme.logoAmber, 1.0)
        }
        .padding(8)
        .frame(width: 36, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.settingsHairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func cap(_ color: Color, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
            .fill(color)
            .frame(width: 4, height: 18 * height)
    }
}
