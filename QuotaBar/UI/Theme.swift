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
    /// Tight CodexBar-style starting height (header + switcher + two meters + footer).
    static let popoverCompactHeight: CGFloat = 280
    static let meterRowHeight: CGFloat = 48
    static let meterSpacing: CGFloat = 14
    static var meterStackHeight: CGFloat { (meterRowHeight * 2) + meterSpacing }
    static let accountRowHeight: CGFloat = 22
    static let statusRowHeight: CGFloat = 16
    static let lowQuotaThreshold: Double = 25

    static var backgroundNSColor: NSColor {
        NSColor(srgbRed: 0.105, green: 0.105, blue: 0.112, alpha: 1)
    }
}
