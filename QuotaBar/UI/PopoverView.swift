import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.popoverStackSpacing) {
            header
            ProviderSwitcher(
                providers: store.visibleProviders,
                selected: Binding(
                    get: { store.selected },
                    set: { store.select($0) }
                )
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.horizontal, Theme.popoverHorizontalPadding)
        .padding(.top, Theme.popoverPaddingTop)
        .padding(.bottom, Theme.popoverPaddingBottom)
        .frame(width: Theme.popoverWidth, height: Theme.popoverHeight, alignment: .top)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.selected.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    if let badge = badgeText {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous).fill(Theme.badgeFill)
                            )
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
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

    @ViewBuilder
    private var content: some View {
        if store.selected == .chatgpt {
            chatgptContent
        } else {
            providerMeters
        }
    }

    private var providerMeters: some View {
        let snapshot = store.selectedState.snapshot
        return VStack(spacing: Theme.meterSpacing) {
            if let session = snapshot?.session {
                UsageMeterRow(window: session, mode: store.settings.displayMode, now: store.now, compact: true)
            }
            if let weekly = snapshot?.weekly {
                UsageMeterRow(window: weekly, mode: store.settings.displayMode, now: store.now, compact: true)
            }
            if snapshot?.session == nil && snapshot?.weekly == nil {
                contentStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var chatgptContent: some View {
        let rows = store.chatgptDisplayRows
        if rows.isEmpty {
            contentStatus
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical, showsIndicators: rows.count > 2) {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        ChatGPTAccountCard(
                            row: row,
                            mode: store.settings.displayMode,
                            now: store.now,
                            onRetry: { Task { await store.refreshSelected() } },
                            onOpenSettings: store.openSettings
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var contentStatus: some View {
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
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.footerStackSpacing) {
            if let footerText = extraFooterText {
                HStack {
                    Spacer()
                    Text(footerText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                .frame(height: Theme.statusRowHeight)
            }
            Divider().overlay(Theme.hairline)
            HStack {
                Button("Settings…") { store.openSettings() }
                Spacer()
                Button("Quit QuotaBar") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondary)
            .frame(height: Theme.footerButtonsHeight)
        }
    }

    private var extraFooterText: String? {
        if store.selected == .chatgpt { return nil }
        if case .ready(let snapshot) = store.selectedState {
            let text = snapshot.extraFooter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private var isLoading: Bool {
        if store.isRefreshing { return true }
        if store.selected == .chatgpt {
            return store.chatgptDisplayRows.contains { row in
                if case .loading = row.state { return true }
                return false
            }
        }
        if case .loading = store.selectedState { return true }
        return false
    }

    private var badgeText: String? {
        if store.settings.previewFixtures { return "Preview" }
        if store.selected == .chatgpt { return nil }
        if case .ready(let snapshot) = store.selectedState {
            return snapshot.planName
        }
        return nil
    }

    private var subtitle: String {
        if store.selected == .chatgpt {
            return chatgptSubtitle
        }
        switch store.selectedState {
        case .ready(let snapshot):
            var parts: [String] = []
            if let email = snapshot.accountEmail, !email.isEmpty {
                parts.append(email)
            }
            parts.append(updatedText(from: snapshot))
            return parts.joined(separator: " · ")
        case .loading, .idle:
            return "Updating…"
        case .signedOut:
            return "Not signed in"
        case .failure:
            return "Update failed"
        }
    }

    private var chatgptSubtitle: String {
        let rows = store.chatgptDisplayRows
        if rows.isEmpty {
            if case .signedOut = store.selectedState { return "Not signed in" }
            return "No accounts"
        }
        let ready = rows.compactMap { row -> UsageSnapshot? in
            if case .ready(let snapshot) = row.state { return snapshot }
            return nil
        }
        if let newest = ready.max(by: { $0.fetchedAt < $1.fetchedAt }) {
            let count = rows.count
            let prefix = count == 1 ? "1 account" : "\(count) accounts"
            return "\(prefix) · \(updatedText(from: newest))"
        }
        if rows.contains(where: { if case .loading = $0.state { return true }; return false }) {
            return "Updating…"
        }
        if rows.allSatisfy({ $0.state.isSignedOut }) {
            return "Not signed in"
        }
        return "Update failed"
    }

    private func updatedText(from snapshot: UsageSnapshot) -> String {
        var text = TimeFormatting.relativeUpdated(from: snapshot.fetchedAt, now: store.now)
        if snapshot.source == .fixture { text += " · Preview" }
        if snapshot.source == .pastedJSON { text += " · Pasted JSON" }
        return text
    }
}

private struct ChatGPTAccountCard: View {
    let row: ChatGPTDisplayRow
    let mode: DisplayMode
    let now: Date
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let plan = planName {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule(style: .continuous).fill(Theme.badgeFill))
                }
            }

            switch row.state {
            case .ready(let snapshot):
                let windows = [snapshot.weekly, snapshot.session].compactMap { $0 }
                if windows.isEmpty {
                    Text("No usage windows")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(windows, id: \.title) { window in
                            UsageMeterRow(window: window, mode: mode, now: now, compact: true)
                        }
                    }
                }
                if let extra = snapshot.extraFooter, !extra.isEmpty {
                    Text(extra)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case .loading, .idle:
                Text("Updating…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
            case .signedOut(let message):
                EmptyStateView(
                    title: "Sign in",
                    message: message,
                    actionTitle: "Settings",
                    action: onOpenSettings
                )
            case .failure(let message):
                EmptyStateView(
                    title: "Couldn’t load",
                    message: message,
                    actionTitle: "Retry",
                    action: onRetry
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var title: String {
        if let email = row.account?.email, !email.isEmpty {
            return email
        }
        if case .ready(let snapshot) = row.state, let email = snapshot.accountEmail, !email.isEmpty {
            return email
        }
        return row.account?.label ?? "ChatGPT"
    }

    private var planName: String? {
        if case .ready(let snapshot) = row.state {
            return snapshot.planName
        }
        return nil
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
                .frame(width: 20, height: 20)
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
