import SwiftUI

struct UsageMeterRow: View {
    let title: String
    let window: UsageWindow?
    let mode: DisplayMode
    let now: Date
    var compact: Bool = false

    init(window: UsageWindow, mode: DisplayMode, now: Date, compact: Bool = false) {
        self.title = window.title
        self.window = window
        self.mode = mode
        self.now = now
        self.compact = compact
    }

    init(title: String, window: UsageWindow?, mode: DisplayMode, now: Date, compact: Bool = false) {
        self.title = title
        self.window = window
        self.mode = mode
        self.now = now
        self.compact = compact
    }

    var body: some View {
        let active = window != nil
        let low = window?.isLow(mode: mode, threshold: Theme.lowQuotaThreshold) ?? false
        let fill = min(max((window?.displayedPercent(mode: mode) ?? 0) / 100, 0), 1)
        let titleSize: CGFloat = compact ? 11 : 13

        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(active ? Theme.primary : Theme.secondary)
                Spacer(minLength: 4)
                Text(active ? valueText : "—")
                    .font(.system(size: titleSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(valueColor(active: active, low: low))
                if compact, let extra = window?.extra, !extra.isEmpty {
                    Text(extra)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .lineLimit(1)
                }
                if compact {
                    ResetChip(text: resetChipText, accessibilityLabel: resetAccessibility)
                        .accessibilityHidden(true)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    if active, fill > 0 {
                        Capsule()
                            .fill(low ? Theme.warning : Color.white.opacity(0.92))
                            .frame(width: max(2, geo.size.width * fill))
                    }
                }
            }
            .frame(height: compact ? 3 : 3.5)

            if !compact {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                    Text(active ? footerLeading : "—")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let extra = window?.extra, !extra.isEmpty {
                        Text(extra)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondary)
                .opacity(active ? 1 : 0.7)
            }
        }
        .frame(minHeight: compact ? Theme.compactMeterRowHeight : Theme.meterRowHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compact ? compactAccessibility : title)
    }

    private func valueColor(active: Bool, low: Bool) -> Color {
        if !active { return Theme.tertiary }
        return low ? Theme.warning : Theme.primary
    }

    private var valueText: String {
        guard let window else { return "—" }
        if window.unlimited { return "Unlimited" }
        let percent = Int(window.displayedPercent(mode: mode).rounded())
        switch mode {
        case .remaining: return "\(percent)% left"
        case .used: return "\(percent)% used"
        }
    }

    private var footerLeading: String {
        guard let window else { return "—" }
        if let reset = window.resetAt {
            return TimeFormatting.countdown(until: reset, now: now, prefix: window.title)
        }
        return "\(window.title) reset unknown"
    }

    private var resetChipText: String {
        guard let window else { return "—" }
        if let reset = window.resetAt {
            return TimeFormatting.resetChip(until: reset, now: now)
        }
        return "unknown"
    }

    private var resetAccessibility: String {
        guard let window else { return "\(title) reset unknown" }
        if let reset = window.resetAt {
            return TimeFormatting.countdown(until: reset, now: now, prefix: window.title)
        }
        return "\(window.title) reset unknown"
    }

    private var compactAccessibility: String {
        var parts = [title, valueText]
        if let extra = window?.extra, !extra.isEmpty {
            parts.append(extra)
        }
        parts.append(resetAccessibility)
        return parts.joined(separator: ", ")
    }
}

/// Per-window reset, chip-sized so it sits on the meter title row.
struct ResetChip: View {
    let text: String
    var accessibilityLabel: String = ""

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 5)
        .frame(height: Theme.resetChipHeight)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityLabel.isEmpty ? "Reset \(text)" : accessibilityLabel)
    }
}
