import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.105, green: 0.105, blue: 0.112)
    static let elevated = Color(red: 0.165, green: 0.165, blue: 0.175)
    static let track = Color.white.opacity(0.10)
    static let primary = Color.white
    static let secondary = Color(white: 0.62)
    static let tertiary = Color(white: 0.42)
    static let warning = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let badgeFill = Color.white.opacity(0.10)
    static let switcherIdle = Color.white.opacity(0.055)
    static let switcherSelected = Color.white.opacity(0.145)
    static let hairline = Color.white.opacity(0.08)

    static let logoBlue = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let logoPurple = Color(red: 0.71, green: 0.42, blue: 1.0)
    static let logoGreen = Color(red: 0.24, green: 0.86, blue: 0.59)

    static let popoverWidth: CGFloat = 312
    static let popoverHorizontalPadding: CGFloat = 14
    static let popoverPaddingTop: CGFloat = 13
    static let popoverPaddingBottom: CGFloat = 11
    static let popoverStackSpacing: CGFloat = 12
    static let headerMinHeight: CGFloat = 34
    static let providerSwitcherHeight: CGFloat = 26
    /// Compact pill row under the provider switcher. Always reserved so tab height stays put.
    static let accountRowHeight: CGFloat = 22
    static let accountRowSpacing: CGFloat = 6
    static let accountPillMaxWidth: CGFloat = 168
    static let meterRowHeight: CGFloat = 52
    static let meterSpacing: CGFloat = 14
    static var meterStackHeight: CGFloat { (meterRowHeight * 2) + meterSpacing }
    /// Tall enough for 11.5pt copy + a ~22pt capsule action without clipping.
    static let statusRowHeight: CGFloat = 24
    static let footerStackSpacing: CGFloat = 8
    static let footerButtonsHeight: CGFloat = 18
    static let footerDividerHeight: CGFloat = 1
    static let lowQuotaThreshold: Double = 25

    static var switcherBlockHeight: CGFloat {
        providerSwitcherHeight + accountRowSpacing + accountRowHeight
    }

    static var footerHeight: CGFloat {
        statusRowHeight
            + footerStackSpacing
            + footerDividerHeight
            + footerStackSpacing
            + footerButtonsHeight
    }

    /// Tight CodexBar-style height with reserved account + status slots.
    static var popoverCompactHeight: CGFloat {
        popoverPaddingTop
            + headerMinHeight
            + popoverStackSpacing
            + switcherBlockHeight
            + popoverStackSpacing
            + meterStackHeight
            + popoverStackSpacing
            + footerHeight
            + popoverPaddingBottom
    }

    static var backgroundNSColor: NSColor {
        NSColor(srgbRed: 0.105, green: 0.105, blue: 0.112, alpha: 1)
    }

    // MARK: Settings (follows system appearance)

    static let settingsColumnWidth: CGFloat = 520
    static let settingsMinWidth: CGFloat = 480
    static let settingsMinHeight: CGFloat = 560
    static let settingsCardRadius: CGFloat = 11
    static let settingsPadding: CGFloat = 18
    static let settingsCardPadding: CGFloat = 16
    static let settingsHitTarget: CGFloat = 28
    static let settingsHairline = Color.primary.opacity(0.08)
    static let settingsCardFill = Color(nsColor: .controlBackgroundColor)
    static let settingsPageFill = Color(nsColor: .windowBackgroundColor)

    static func settingsTint(for provider: ProviderKind) -> Color {
        switch provider {
        case .cursor: return logoBlue
        case .chatgpt: return logoPurple
        case .glm: return logoGreen
        }
    }
}
