import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ProviderSwitcher(
                providers: store.visibleProviders,
                selected: Binding(
                    get: { store.selected },
                    set: { store.select($0) }
                )
            )
            content
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .frame(width: Theme.popoverWidth)
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
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedState {
        case .idle, .loading:
            VStack(spacing: 10) {
                placeholderMeter(title: "Session")
                placeholderMeter(title: "Weekly")
            }
            .redacted(reason: .placeholder)
            .padding(.vertical, 2)
        case .ready(let snapshot):
            VStack(spacing: 14) {
                if let session = snapshot.session {
                    UsageMeterRow(window: session, mode: store.settings.displayMode, now: store.now)
                }
                if let weekly = snapshot.weekly {
                    UsageMeterRow(window: weekly, mode: store.settings.displayMode, now: store.now)
                }
                if snapshot.session == nil && snapshot.weekly == nil {
                    EmptyStateView(
                        title: "No usage windows",
                        message: "The provider replied, but no session or weekly quota was in the payload.",
                        actionTitle: "Open Settings",
                        action: store.openSettings
                    )
                }
            }
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
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if case .ready(let snapshot) = store.selectedState, let extra = snapshot.extraFooter, !extra.isEmpty {
                HStack {
                    Spacer()
                    Text(extra)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
            }
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

    private func placeholderMeter(title: String) -> some View {
        UsageMeterRow(
            window: UsageWindow(title: title, remainingPercent: 80, resetAt: Date().addingTimeInterval(4000)),
            mode: .remaining,
            now: store.now
        )
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
