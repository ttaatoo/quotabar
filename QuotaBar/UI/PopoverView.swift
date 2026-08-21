import AppKit
import SwiftUI

struct PopoverSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct PopoverView: View {
    @ObservedObject var store: AppStore
    var onIntrinsicSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switcherBlock
            content
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .frame(width: Theme.popoverWidth)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PopoverSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PopoverSizeKey.self, perform: onIntrinsicSizeChange)
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.selected.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    if let badge = badgeText {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous).fill(Theme.badgeFill)
                            )
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                Task { await store.refreshSelected() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .rotationEffect(.degrees(store.isRefreshing || isLoading ? 360 : 0))
                    .animation(
                        (store.isRefreshing || isLoading)
                            ? .linear(duration: 0.85).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing || isLoading
                    )
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .frame(minHeight: 34, alignment: .top)
    }

    private var switcherBlock: some View {
        VStack(spacing: 6) {
            ProviderSwitcher(
                providers: store.visibleProviders,
                selected: Binding(
                    get: { store.selected },
                    set: { store.select($0) }
                )
            )
            if showsAccountSwitcher {
                ChatGPTAccountSwitcher(
                    accounts: store.visibleChatGPTAccounts,
                    selectedID: Binding(
                        get: {
                            store.settings.selectedChatGPTAccountId
                                ?? store.visibleChatGPTAccounts.first?.id
                                ?? UUID()
                        },
                        set: { store.selectChatGPTAccount($0) }
                    )
                )
            }
        }
    }

    private var content: some View {
        VStack(spacing: Theme.meterSpacing) {
            UsageMeterRow(
                title: "Session",
                window: store.selectedState.snapshot?.session,
                mode: store.settings.displayMode,
                now: store.now
            )
            UsageMeterRow(
                title: "Weekly",
                window: store.selectedState.snapshot?.weekly,
                mode: store.settings.displayMode,
                now: store.now
            )
        }
        .frame(height: Theme.meterStackHeight, alignment: .top)
        .clipped()
    }

    private var footer: some View {
        VStack(spacing: 8) {
            statusRow
            Divider().overlay(Theme.hairline)
            HStack {
                Button("Settings…") { store.openSettings() }
                Spacer()
                Button("Quit QuotaBar") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.selectedState {
        case .signedOut(let message):
            EmptyStateView(
                title: "Sign in / add key",
                message: message,
                actionTitle: "Open Settings",
                action: store.openSettings
            )
        case .failure(let message):
            EmptyStateView(
                title: "Couldn’t load quota",
                message: message,
                actionTitle: "Try again",
                action: { Task { await store.refreshSelected() } }
            )
        case .ready(let snapshot) where snapshot.session == nil && snapshot.weekly == nil:
            EmptyStateView(
                title: "No usage windows",
                message: "The provider replied, but no session or weekly quota was in the payload.",
                actionTitle: "Open Settings",
                action: store.openSettings
            )
        case .ready(let snapshot):
            extraFooterRow(snapshot.extraFooter)
        case .idle, .loading:
            extraFooterRow(nil)
        }
    }

    private func extraFooterRow(_ text: String?) -> some View {
        HStack {
            Spacer()
            Text(text ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .opacity((text == nil || text?.isEmpty == true) ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.statusRowHeight, maxHeight: Theme.statusRowHeight)
    }

    private var showsAccountSwitcher: Bool {
        store.selected == .chatgpt && store.visibleChatGPTAccounts.count >= 2
    }

    private var isLoading: Bool {
        if case .loading = store.selectedState { return true }
        return false
    }

    private var badgeText: String? {
        if store.settings.previewFixtures { return "Preview" }
        if case .ready(let snapshot) = store.selectedState {
            return snapshot.planName
        }
        return nil
    }

    private var subtitle: String {
        switch store.selectedState {
        case .ready(let snapshot):
            var text = TimeFormatting.relativeUpdated(from: snapshot.fetchedAt, now: store.now)
            if snapshot.source == .fixture { text += " · Preview" }
            if snapshot.source == .pastedJSON { text += " · Pasted JSON" }
            return text
        case .loading, .idle:
            return "Updating…"
        case .signedOut:
            return "Not signed in"
        case .failure:
            return "Update failed"
        }
    }
}
