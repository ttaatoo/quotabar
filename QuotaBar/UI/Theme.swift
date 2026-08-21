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

    /// Frozen popover chrome. Do not resize NSPopover after the first show.
    static let popoverWidth: CGFloat = 312
    static let popoverHeight: CGFloat = 300
    static let popoverHorizontalPadding: CGFloat = 12
    static let popoverPaddingTop: CGFloat = 10
    static let popoverPaddingBottom: CGFloat = 8
    static let popoverStackSpacing: CGFloat = 8
    static let headerMinHeight: CGFloat = 32
    static let providerSwitcherHeight: CGFloat = 24
    static let meterRowHeight: CGFloat = 38
    static let meterSpacing: CGFloat = 6
    static let compactMeterRowHeight: CGFloat = 34
    static let statusRowHeight: CGFloat = 20
    static let footerStackSpacing: CGFloat = 6
    static let footerButtonsHeight: CGFloat = 16
    static let footerDividerHeight: CGFloat = 1
    static let lowQuotaThreshold: Double = 25

    static var footerHeight: CGFloat {
        statusRowHeight
            + footerStackSpacing
            + footerDividerHeight
            + footerStackSpacing
            + footerButtonsHeight
    }

    static var popoverChromeSize: NSSize {
        NSSize(width: popoverWidth, height: popoverHeight)
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
    static let settingsHitTarget: CGFloat = 30
    static let settingsFieldHeight: CGFloat = 30
    static let settingsHairline = Color.primary.opacity(0.08)
    static let settingsCardFill = Color(nsColor: .controlBackgroundColor)
    static let settingsPageFill = Color(nsColor: .windowBackgroundColor)
    static let settingsFieldFill = Color.primary.opacity(0.045)

    static func settingsTint(for provider: ProviderKind) -> Color {
        switch provider {
        case .cursor: return logoBlue
        case .chatgpt: return logoPurple
        case .glm: return logoGreen
        }
    }
}
