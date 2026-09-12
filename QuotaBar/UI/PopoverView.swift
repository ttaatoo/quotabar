import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Same tree for 0 / 1 / N cards. A ScrollView → hugging stack is always
    /// present so tab switches cannot change NSHostingView.fittingSize.
    /// Cards hug their content; leftover space is the popover background.
    private var cards: some View {
        let rows = cardRows
        return ScrollView(.vertical, showsIndicators: rows.count > 2) {
            VStack(spacing: Theme.accountCardListSpacing) {
                ForEach(rows) { row in
                    AccountCard(
                        row: row,
                        mode: store.settings.displayMode,
                        now: store.now,
                        onRetry: { Task { await store.refreshCard(row.id) } },
                        onOpenSettings: store.openSettings,
                        isActive: store.isActiveAccountCard(row.id),
                        onActivate: (store.selected == .chatgpt || store.selected == .opencodeGo)
                            ? { store.activateAccountCard(row.id) }
                            : nil,
                        reduceMotion: reduceMotion,
                        treatIdleAsUpdating: store.isRefreshing
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if rows.count > 2 {
                LinearGradient(
                    colors: [Theme.background.opacity(0), Theme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 14)
                .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private var cardRows: [AccountCardRow] {
        let rows = store.accountCards
        if rows.isEmpty {
            return [
                AccountCardRow(
                    id: store.selected.rawValue,
                    email: nil,
                    fallbackTitle: "Not signed in",
                    state: store.selectedState,
                    hasCredentials: false
                )
            ]
        }
        return rows
    }

    private var footer: some View {
        VStack(spacing: Theme.footerStackSpacing) {
            Divider().overlay(Theme.hairline)
            HStack {
                FooterTextButton(title: "Settings…", action: store.openSettings)
                Spacer()
                FooterTextButton(title: "Quit QuotaBar") { NSApp.terminate(nil) }
            }
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
        let updated: String
        if let newest = ready.max(by: { $0.fetchedAt < $1.fetchedAt }) {
            updated = updatedText(from: newest)
        } else {
            switch store.selectedState {
            case .ready(let snapshot):
                updated = updatedText(from: snapshot)
            case .loading:
                updated = "Updating…"
            case .idle:
                updated = store.isRefreshing ? "Updating…" : "Waiting…"
            case .signedOut:
                updated = "Not signed in"
            case .failure:
                updated = "Update failed"
            }
        }
        if (store.selected == .chatgpt || store.selected == .opencodeGo), rows.count > 1 {
            return "\(rows.count) accounts · \(updated)"
        }
        return updated
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
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    var isActive: Bool = false
    var onActivate: (() -> Void)? = nil
    var reduceMotion: Bool = false
    var treatIdleAsUpdating: Bool = true

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.accountCardSpacing) {
            headerRow
                .contentShape(Rectangle())
                .onTapGesture { onActivate?() }

            switch row.state {
            case .ready(let snapshot):
                readyBody(snapshot)
                    .contentShape(Rectangle())
                    .onTapGesture { onActivate?() }
            case .loading:
                updatingBody
            case .idle:
                if treatIdleAsUpdating {
                    updatingBody
                } else {
                    Text("Waiting…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate?() }
                }
            case .signedOut(let message):
                signedOutBody(message)
            case .failure(let message):
                EmptyStateView(
                    title: (row.hasCredentials || hasKnownEmail) ? "Couldn’t refresh" : "Couldn’t load",
                    message: shortFailure(message),
                    actionTitle: "Retry",
                    action: onRetry,
                    onSelect: onActivate
                )
            }
        }
        .padding(Theme.accountCardPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Theme.accountCardRadius, style: .continuous)
                .fill(cardFill)
                .contentShape(
                    RoundedRectangle(cornerRadius: Theme.accountCardRadius, style: .continuous)
                )
                .onTapGesture {
                    onActivate?()
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.accountCardRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: isActive ? 1.5 : 1)
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isActive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityHint(onActivate == nil ? "" : "Show this account in the menu bar")
    }

    private var cardFill: Color {
        if isActive {
            return Theme.logoPurple.opacity(0.10)
        }
        if hovering && onActivate != nil {
            return Color(red: 0.19, green: 0.19, blue: 0.205)
        }
        return Theme.elevated
    }

    private var cardStroke: Color {
        if isActive {
            return Theme.logoPurple.opacity(0.78)
        }
        if hovering && onActivate != nil {
            return Color.white.opacity(0.16)
        }
        return Theme.hairline
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let plan = planName {
                Text(plan)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.planBadgeForeground(plan))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous).fill(Theme.planBadgeFill(plan))
                    )
            }
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.logoPurple)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Theme.logoPurple.opacity(0.18)))
                    .accessibilityHidden(true)
            }
        }
    }

    private var updatingBody: some View {
        Text("Updating…")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onActivate?() }
    }

    private func readyBody(_ snapshot: UsageSnapshot) -> some View {
        let windows = [snapshot.session, snapshot.weekly, snapshot.monthly].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Theme.meterSpacing) {
            if windows.isEmpty {
                Text("No usage windows")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(windows, id: \.title) { window in
                    UsageMeterRow(window: window, mode: mode, now: now, compact: true)
                }
            }
            if let extra = snapshot.extraFooter, !extra.isEmpty {
                Text(extra)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func signedOutBody(_ message: String) -> some View {
        if row.hasCredentials || hasKnownEmail {
            EmptyStateView(
                title: "Couldn’t refresh",
                message: "This account is still saved. Retry, or re-add it in Settings if the session expired.",
                actionTitle: "Retry",
                action: onRetry,
                onSelect: onActivate
            )
        } else {
            EmptyStateView(
                title: "Not signed in",
                message: shortFailure(message),
                actionTitle: "Settings",
                action: onOpenSettings,
                onSelect: onActivate
            )
        }
    }

    private var title: String {
        if let email = row.email, !email.isEmpty {
            return email
        }
        if case .ready(let snapshot) = row.state, let email = snapshot.accountEmail, !email.isEmpty {
            return email
        }
        if case .signedOut = row.state, !hasKnownEmail, !row.hasCredentials {
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

    private var hasKnownEmail: Bool {
        if let email = row.email, !email.isEmpty { return true }
        return false
    }

    private func shortFailure(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 140 { return trimmed }
        return String(trimmed.prefix(137)) + "…"
    }
}

private struct FooterTextButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(hovering ? Theme.primary : Theme.secondary)
            .onHover { hovering = $0 }
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
