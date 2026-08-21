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
            cards
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    if store.settings.previewFixtures {
                        Text("Preview")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous).fill(Theme.badgeFill)
                            )
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10))
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
    private var cards: some View {
        let rows = store.accountCards
        if rows.isEmpty {
            AccountCard(
                row: AccountCardRow(
                    id: store.selected.rawValue,
                    email: nil,
                    fallbackTitle: "Not signed in",
                    state: store.selectedState
                ),
                mode: store.settings.displayMode,
                now: store.now,
                fillsBody: true,
                onRetry: { Task { await store.refreshSelected() } },
                onOpenSettings: store.openSettings
            )
        } else if rows.count == 1, let row = rows.first {
            AccountCard(
                row: row,
                mode: store.settings.displayMode,
                now: store.now,
                fillsBody: true,
                onRetry: { Task { await store.refreshSelected() } },
                onOpenSettings: store.openSettings
            )
        } else {
            ScrollView(.vertical, showsIndicators: rows.count > 2) {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        AccountCard(
                            row: row,
                            mode: store.settings.displayMode,
                            now: store.now,
                            fillsBody: false,
                            onRetry: { Task { await store.refreshSelected() } },
                            onOpenSettings: store.openSettings
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.footerStackSpacing) {
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

    private var isLoading: Bool {
        if store.isRefreshing { return true }
        return store.accountCards.contains { row in
            if case .loading = row.state { return true }
            return false
        }
    }

    private var subtitle: String {
        let rows = store.accountCards
        let ready = rows.compactMap { row -> UsageSnapshot? in
            if case .ready(let snapshot) = row.state { return snapshot }
            return nil
        }
        if let newest = ready.max(by: { $0.fetchedAt < $1.fetchedAt }) {
            return updatedText(from: newest)
        }
        switch store.selectedState {
        case .ready(let snapshot):
            return updatedText(from: snapshot)
        case .loading, .idle:
            return "Updating…"
        case .signedOut:
            return "Not signed in"
        case .failure:
            return "Update failed"
        }
    }

    private func updatedText(from snapshot: UsageSnapshot) -> String {
        var text = TimeFormatting.relativeUpdated(from: snapshot.fetchedAt, now: store.now)
        if snapshot.source == .fixture { text += " · Preview" }
        if snapshot.source == .pastedJSON { text += " · Pasted JSON" }
        return text
    }
}

/// Shared account chrome: email + plan, that account's meters, extra footer inside the card.
struct AccountCard: View {
    let row: AccountCardRow
    let mode: DisplayMode
    let now: Date
    var fillsBody: Bool = false
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.accountCardSpacing) {
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
                let windows = [snapshot.session, snapshot.weekly].compactMap { $0 }
                if windows.isEmpty {
                    Text("No usage windows")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: Theme.meterSpacing) {
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
        .padding(Theme.accountCardPadding)
        .frame(maxWidth: .infinity, maxHeight: fillsBody ? .infinity : nil, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.accountCardRadius, style: .continuous)
                .fill(Theme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.accountCardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var title: String {
        if let email = row.email, !email.isEmpty {
            return email
        }
        if case .ready(let snapshot) = row.state, let email = snapshot.accountEmail, !email.isEmpty {
            return email
        }
        if case .signedOut = row.state {
            return "Not signed in"
        }
        if case .failure = row.state {
            return row.fallbackTitle
        }
        return row.fallbackTitle
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
