import SwiftUI

/// Compact All-tab list: one row per displayable account, grouped by provider.
struct OverallListView: View {
    @ObservedObject var store: AppStore
    var reduceMotion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.overallSectionSpacing) {
            ForEach(store.overallSections) { section in
                VStack(alignment: .leading, spacing: Theme.overallRowListSpacing) {
                    Text(section.provider.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.leading, 2)

                    ForEach(section.rows) { row in
                        OverallAccountRowView(
                            row: row,
                            mode: store.settings.displayMode,
                            now: store.now,
                            treatIdleAsUpdating: store.isRefreshing,
                            reduceMotion: reduceMotion,
                            onOpen: { store.openOverallRow(row) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 2)
    }
}

private struct OverallAccountRowView: View {
    let row: OverallAccountRow
    let mode: DisplayMode
    let now: Date
    let treatIdleAsUpdating: Bool
    var reduceMotion: Bool = false
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 8) {
                ProviderMark(
                    provider: row.provider,
                    size: 14,
                    tint: Theme.settingsTint(for: row.provider)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.card.displayTitle(for: row.provider))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(secondaryText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if let window = primaryWindow {
                    primaryMeter(window)
                }
            }
            .padding(Theme.overallRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.overallRowRadius, style: .continuous)
                    .fill(hovering ? Color(red: 0.19, green: 0.19, blue: 0.205) : Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.overallRowRadius, style: .continuous)
                    .strokeBorder(hovering ? Color.white.opacity(0.16) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .accessibilityLabel([
            row.card.displayTitle(for: row.provider),
            row.provider.title,
            secondaryText
        ].joined(separator: ", "))
        .accessibilityHint("Show this account")
    }

    private var primaryWindow: UsageWindow? {
        guard case .ready(let snapshot) = row.card.state else { return nil }
        return snapshot.tightestWindow
    }

    private var secondaryText: String {
        row.card.compactStatus(treatIdleAsUpdating: treatIdleAsUpdating) ?? row.hint
    }

    @ViewBuilder
    private func primaryMeter(_ window: UsageWindow) -> some View {
        let low = window.isLow(mode: mode, threshold: Theme.lowQuotaThreshold)
        let fill = min(max(window.displayedPercent(mode: mode) / 100, 0), 1)
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text(percentText(window))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(low ? Theme.warning : Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ResetChip(text: resetChipText(window), accessibilityLabel: resetAccessibility(window))
                    .accessibilityHidden(true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    if fill > 0 {
                        Capsule()
                            .fill(low ? Theme.warning : Color.white.opacity(0.92))
                            .frame(width: max(2, geo.size.width * fill))
                    }
                }
            }
            .frame(width: Theme.overallMeterWidth, height: Theme.overallMeterBarHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meterAccessibility(window))
    }

    private func percentText(_ window: UsageWindow) -> String {
        if window.unlimited { return "Unlimited" }
        let percent = Int(window.displayedPercent(mode: mode).rounded())
        switch mode {
        case .remaining: return "\(percent)% left"
        case .used: return "\(percent)% used"
        }
    }

    private func resetChipText(_ window: UsageWindow) -> String {
        if let reset = window.resetAt {
            return TimeFormatting.resetChip(until: reset, now: now)
        }
        return "unknown"
    }

    private func resetAccessibility(_ window: UsageWindow) -> String {
        if let reset = window.resetAt {
            return TimeFormatting.countdown(until: reset, now: now, prefix: window.title)
        }
        return "\(window.title) reset unknown"
    }

    private func meterAccessibility(_ window: UsageWindow) -> String {
        [window.title, percentText(window), resetAccessibility(window)].joined(separator: ", ")
    }
}
