import SwiftUI

struct UsageMeterRow: View {
    let window: UsageWindow
    let mode: DisplayMode
    let now: Date

    var body: some View {
        let low = window.isLow(mode: mode, threshold: Theme.lowQuotaThreshold)
        let fill = min(max(window.displayedPercent(mode: mode) / 100, 0), 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(low ? Theme.warning : Theme.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    Capsule()
                        .fill(low ? Theme.warning : Color.white)
                        .frame(width: max(2, geo.size.width * fill))
                }
            }
            .frame(height: 3)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                Text(footerLeading)
                Spacer(minLength: 8)
                if let extra = window.extra, !extra.isEmpty {
                    Text(extra)
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.secondary)
        }
    }

    private var valueText: String {
        if window.unlimited { return "Unlimited" }
        let percent = Int(window.displayedPercent(mode: mode).rounded())
        switch mode {
        case .remaining: return "\(percent)% left"
        case .used: return "\(percent)% used"
        }
    }

    private var footerLeading: String {
        if let reset = window.resetAt {
            return TimeFormatting.countdown(until: reset, now: now, prefix: window.title)
        }
        return "\(window.title) reset unknown"
    }
}
