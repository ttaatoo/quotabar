import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    @State private var renameID: UUID?
    @State private var renameLabel = ""
    @State private var deleteID: UUID?

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
                Text("QuotaBar uses the same Codex OAuth file CodexBar uses (~/.codex/auth.json from `codex login`). The in-app ChatGPT window is a cookie fallback that now hits that same usage API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    ChatGPTLoginPresenter.shared.begin(store: store)
                } label: {
                    Label("Add account", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if store.settings.chatgptAccounts.isEmpty {
                    Text("No ChatGPT accounts yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.settings.chatgptAccounts) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.label)
                                    .font(.headline)
                                if let email = account.email,
                                   !email.isEmpty,
                                   email.caseInsensitiveCompare(account.label) != .orderedSame {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Rename") {
                                renameID = account.id
                                renameLabel = account.label
                            }
                            Button("Delete", role: .destructive) {
                                deleteID = account.id
                            }
                        }

                        DisclosureGroup("Advanced — cookie / JSON fallback") {
                            SecureField("Session / cookie", text: cookieBinding(account.id))
                                .textContentType(.password)
                            Text("Optional pasted usage JSON (wham/usage or conversation_limit) when the live API has no percentages. Numbers are never invented.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            jsonEditor(for: account.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
                LabeledContent("Version", value: appVersion)
                Text("Unofficial usage endpoints can change or break without notice. QuotaBar stores secrets in the Keychain and never phones home.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 560)
        .onChange(of: store.cursorCookie) { _, _ in store.persistSecrets() }
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
        .alert("Rename account", isPresented: renamePresented) {
            TextField("Label", text: $renameLabel)
            Button("Save") {
                if let renameID {
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
                if let deleteID {
                    store.deleteChatGPTAccount(deleteID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Keychain cookie and JSON for this account are removed. Other accounts are left alone.")
        }
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
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 80, maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
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
