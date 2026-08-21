import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(ProviderKind.allCases) { provider in
                    Toggle(provider.title, isOn: enabledBinding(provider))
                }
            }

            Section("Cursor") {
                SecureField("Cookie (optional)", text: $store.cursorCookie)
                    .textContentType(.password)
                Text("Leave empty to read the local Cursor.app token from state.vscdb. Otherwise paste a WorkosCursorSessionToken or full Cookie header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ChatGPT") {
                SecureField("Session / cookie", text: $store.chatgptCookie)
                    .textContentType(.password)
                Text(verbatim: "Paste __Secure-next-auth.session-token=… or the full Cookie header from chatgpt.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.chatgptJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 84)
                Text("Optional: paste official conversation_limit JSON from DevTools if the live endpoint does not return remaining quota. QuotaBar never invents percentages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("GLM") {
                SecureField("API key", text: $store.glmAPIKey)
                    .textContentType(.password)
                Picker("Region", selection: $store.settings.glmRegion) {
                    ForEach(GLMRegion.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }
                Text("Also accepted from ~/.config/quotabar/config.json or Z_AI_API_KEY / GLM_API_KEY / BIGMODEL_API_KEY. Keys are stored in the Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Picker("Poll interval", selection: $store.settings.pollIntervalSeconds) {
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                }
                Picker("Show", selection: $store.settings.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: launchBinding)
                Toggle("Preview fixtures", isOn: $store.settings.previewFixtures)
                Text("Preview loads bundled sample JSON so the popover can be screenshot without accounts. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1")
                Text("Unofficial usage endpoints can change or break without notice. QuotaBar stores secrets in the Keychain and never phones home.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 520)
        .onChange(of: store.cursorCookie) { _, _ in store.persistSecrets() }
        .onChange(of: store.chatgptCookie) { _, _ in store.persistSecrets() }
        .onChange(of: store.chatgptJSON) { _, _ in store.persistSecrets() }
        .onChange(of: store.glmAPIKey) { _, _ in store.persistSecrets() }
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
    }

    private func enabledBinding(_ provider: ProviderKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledProviders.contains(provider) },
            set: { store.setEnabled(provider, enabled: $0) }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }
}
