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
    static let fieldFill = Color.white.opacity(0.06)

    static let logoBlue = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let logoPurple = Color(red: 0.71, green: 0.42, blue: 1.0)
    static let logoGreen = Color(red: 0.24, green: 0.86, blue: 0.59)
    static let logoAmber = Color(red: 0.95, green: 0.62, blue: 0.22)
    static let logoTeal = Color(red: 0.22, green: 0.78, blue: 0.82)

    /// Frozen compact chrome. Constant across every provider and account count.
    /// Tall enough for ~2 two-window cards or ~3 weekly-only cards; extras scroll.
    /// Do not rewrite NSPopover.contentSize after the first setup.
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 360
    static let popoverHorizontalPadding: CGFloat = 10
    static let popoverPaddingTop: CGFloat = 10
    static let popoverPaddingBottom: CGFloat = 10
    static let popoverStackSpacing: CGFloat = 8
    static let headerMinHeight: CGFloat = 28
    static let providerSwitcherHeight: CGFloat = 22
    static let meterRowHeight: CGFloat = 34
    static let meterSpacing: CGFloat = 3
    static let compactMeterRowHeight: CGFloat = 24
    static let accountCardPadding: CGFloat = 7
    static let accountCardSpacing: CGFloat = 4
    static let accountCardListSpacing: CGFloat = 6
    static let accountCardRadius: CGFloat = 9
    static let resetChipHeight: CGFloat = 16
    static let footerStackSpacing: CGFloat = 6
    static let footerButtonsHeight: CGFloat = 18
    static let footerDividerHeight: CGFloat = 1
    static let statusRowHeight: CGFloat = 22
    static let lowQuotaThreshold: Double = 25

    static func isFreePlan(_ plan: String) -> Bool {
        plan.localizedCaseInsensitiveContains("free")
    }

    static func planBadgeFill(_ plan: String) -> Color {
        isFreePlan(plan) ? badgeFill : logoPurple.opacity(0.16)
    }

    static func planBadgeForeground(_ plan: String) -> Color {
        isFreePlan(plan)
            ? secondary
            : Color(red: 0.84, green: 0.72, blue: 1.0)
    }

    static var popoverChromeSize: NSSize {
        NSSize(width: popoverWidth, height: popoverHeight)
    }

    static var backgroundNSColor: NSColor {
        NSColor(srgbRed: 0.105, green: 0.105, blue: 0.112, alpha: 1)
    }

    static var elevatedNSColor: NSColor {
        NSColor(srgbRed: 0.165, green: 0.165, blue: 0.175, alpha: 1)
    }

    // MARK: Settings (Night Menu Extra: violet-tinted neutrals, popover meters unchanged)

    static let settingsWindowWidth: CGFloat = 680
    static let settingsWindowHeight: CGFloat = 560
    static let settingsColumnWidth: CGFloat = 680
    static let settingsMinWidth: CGFloat = 620
    static let settingsMinHeight: CGFloat = 480
    static let settingsSidebarWidth: CGFloat = 172
    static let settingsContentPadding: CGFloat = 22
    static let settingsContentMaxWidth: CGFloat = 560
    static let settingsGroupRadius: CGFloat = 10
    static let settingsCardRadius: CGFloat = 10
    static let settingsRowHeight: CGFloat = 36
    static let settingsHitTarget: CGFloat = 28
    static let settingsFieldHeight: CGFloat = 30
    static let settingsIconButton: CGFloat = 28
    static let settingsMotion: Double = 0.16

    /// Page canvas. Slightly violet vs popover `background`.
    static let settingsPageFill = Color(red: 0.102, green: 0.098, blue: 0.122)
    /// Sidebar rail. One step darker than the page.
    static let settingsSidebarFill = Color(red: 0.086, green: 0.082, blue: 0.110)
    /// Grouped preference rows.
    static let settingsGroupFill = Color(red: 0.141, green: 0.133, blue: 0.173)
    static let settingsCardFill = settingsGroupFill
    static let settingsFieldFill = Color(red: 0.071, green: 0.067, blue: 0.102)
    static let settingsPrimary = Color(red: 0.957, green: 0.945, blue: 0.973)
    static let settingsSecondary = Color(red: 0.659, green: 0.639, blue: 0.710)
    static let settingsTertiary = Color(red: 0.478, green: 0.455, blue: 0.533)
    static let settingsHairline = Color(red: 0.706, green: 0.667, blue: 0.784).opacity(0.18)
    static let settingsAccent = logoPurple
    static let settingsAccentSoft = Color(red: 0.84, green: 0.72, blue: 1.0)
    static let settingsDanger = Color(red: 0.949, green: 0.400, blue: 0.380)
    static let settingsHoverFill = Color(red: 0.957, green: 0.945, blue: 0.973).opacity(0.06)
    static let settingsSelectedFill = logoPurple.opacity(0.16)
    static let settingsPadding: CGFloat = 22
    static let settingsCardPadding: CGFloat = 12

    static var settingsPageFillNSColor: NSColor {
        NSColor(srgbRed: 0.102, green: 0.098, blue: 0.122, alpha: 1)
    }

    static var settingsSidebarFillNSColor: NSColor {
        NSColor(srgbRed: 0.086, green: 0.082, blue: 0.110, alpha: 1)
    }

    static func settingsTint(for provider: ProviderKind) -> Color {
        switch provider {
        case .cursor: return logoBlue
        case .chatgpt: return logoPurple
        case .glm: return logoGreen
        case .grok: return logoAmber
        case .opencodeGo: return logoTeal
        }
    }
}
