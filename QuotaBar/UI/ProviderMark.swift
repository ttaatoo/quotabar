import AppKit
import SwiftUI

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
