import SwiftUI

struct UsageMeterRow: View {
    let title: String
    let window: UsageWindow?
    let mode: DisplayMode
    let now: Date

    init(window: UsageWindow, mode: DisplayMode, now: Date) {
        self.title = window.title
        self.window = window
        self.mode = mode
        self.now = now
    }

    init(title: String, window: UsageWindow?, mode: DisplayMode, now: Date) {
        self.title = title
        self.window = window
        self.mode = mode
        self.now = now
    }

    var body: some View {
        let active = window != nil
        let low = window?.isLow(mode: mode, threshold: Theme.lowQuotaThreshold) ?? false
        let fill = min(max((window?.displayedPercent(mode: mode) ?? 0) / 100, 0), 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? Theme.primary : Theme.secondary)
                Spacer()
                Text(active ? valueText : "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(valueColor(active: active, low: low))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    if active {
                        Capsule()
                            .fill(low ? Theme.warning : Color.white)
                            .frame(width: max(2, geo.size.width * fill))
                    }
                }
            }
            .frame(height: 3)

            HStack(spacing: 5) {
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
        .frame(height: Theme.meterRowHeight, alignment: .top)
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
}
