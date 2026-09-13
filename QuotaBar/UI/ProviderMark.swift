import AppKit
import SwiftUI

/// Same three bars as the menu-bar pill. Used for the All / Overall tab.
struct OverallMark: View {
    var size: CGFloat = 14

    var body: some View {
        let barWidth = size / 4.6
        let spacing = (size - barWidth * 3) / 2
        HStack(alignment: .bottom, spacing: spacing) {
            bar(heightFraction: 0.42, width: barWidth, color: Theme.logoBlue)
            bar(heightFraction: 0.68, width: barWidth, color: Theme.logoPurple)
            bar(heightFraction: 1.0, width: barWidth, color: Theme.logoGreen)
        }
        .frame(width: size, height: size, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func bar(heightFraction: CGFloat, width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.1, style: .continuous)
            .fill(color)
            .frame(width: width, height: size * heightFraction)
    }
}

/// Bundled official brand mark. Falls back to the SF Symbol if the asset is missing.
/// Marks render in original colors (light-on-dark kit variants). Tint applies only to the fallback.
struct ProviderMark: View {
    let provider: ProviderKind
    var size: CGFloat = 12
    var tint: Color = Theme.secondary

    var body: some View {
        Group {
            if NSImage(named: provider.brandAssetName) != nil {
                Image(provider.brandAssetName)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: provider.settingsSymbol)
                    .font(.system(size: size * 0.85, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tinted well used on the Settings provider list and account rows.
struct SettingsProviderWell: View {
    let provider: ProviderKind
    var size: CGFloat = 26
    var iconSize: CGFloat = 14

    var body: some View {
        let tint = Theme.settingsTint(for: provider)
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                ProviderMark(provider: provider, size: iconSize, tint: tint)
            }
            .accessibilityHidden(true)
    }
}

extension ProviderKind {
    var brandAssetName: String {
        switch self {
        case .cursor: return "BrandCursor"
        case .chatgpt: return "BrandChatGPT"
        case .glm: return "BrandGLM"
        case .grok: return "BrandGrok"
        case .opencodeGo: return "BrandOpenCode"
        }
    }
}
