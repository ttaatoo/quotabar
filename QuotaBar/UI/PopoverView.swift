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
        VStack(alignment: .leading, spacing: Theme.popoverStackSpacing) {
            header
            switcherBlock
            content
            footer
        }
        .padding(.horizontal, Theme.popoverHorizontalPadding)
        .padding(.top, Theme.popoverPaddingTop)
        .padding(.bottom, Theme.popoverPaddingBottom)
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
                RefreshSpinner(spinning: store.isRefreshing || isLoading)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .frame(minHeight: Theme.headerMinHeight, alignment: .top)
    }

    private var switcherBlock: some View {
        VStack(spacing: Theme.accountRowSpacing) {
            ProviderSwitcher(
                providers: store.visibleProviders,
                selected: Binding(
                    get: { store.selected },
                    set: { store.select($0) }
                )
            )
            accountSlot
        }
        .frame(height: Theme.switcherBlockHeight, alignment: .top)
    }

    @ViewBuilder
    private var accountSlot: some View {
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
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Theme.accountRowHeight)
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
        let snapshot = store.selectedState.snapshot
        return VStack(spacing: Theme.meterSpacing) {
            UsageMeterRow(
                title: snapshot?.session?.title ?? store.selected.primaryWindowTitle,
                window: snapshot?.session,
                mode: store.settings.displayMode,
                now: store.now
            )
            UsageMeterRow(
                title: snapshot?.weekly?.title ?? store.selected.secondaryWindowTitle,
                window: snapshot?.weekly,
                mode: store.settings.displayMode,
                now: store.now
            )
        }
        .frame(height: Theme.meterStackHeight, alignment: .top)
        .clipped()
    }

    private var footer: some View {
        VStack(spacing: Theme.footerStackSpacing) {
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
            .frame(height: Theme.footerButtonsHeight)
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

/// Time-driven spin so a user click still animates when the fetch is short
/// or the selected provider never enters `.loading`.
private struct RefreshSpinner: View {
    let spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !spinning)) { context in
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .rotationEffect(.degrees(Self.angle(date: context.date, spinning: spinning)))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }

    private static func angle(date: Date, spinning: Bool) -> Double {
        guard spinning else { return 0 }
        let period = 0.85
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return (t / period) * 360
    }
}
