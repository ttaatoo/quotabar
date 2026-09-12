import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case providers
    case cursor
    case chatgpt
    case opencodeGo
    case glm
    case grok
    case display
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: return "Providers"
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT"
        case .opencodeGo: return "OpenCode"
        case .glm: return "GLM"
        case .grok: return "Grok"
        case .display: return "Display"
        case .about: return "About"
        }
    }

    var paneTitle: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .providers: return "switch.2"
        case .cursor: return ProviderKind.cursor.settingsSymbol
        case .chatgpt: return ProviderKind.chatgpt.settingsSymbol
        case .opencodeGo: return ProviderKind.opencodeGo.settingsSymbol
        case .glm: return ProviderKind.glm.settingsSymbol
        case .grok: return ProviderKind.grok.settingsSymbol
        case .display: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    var group: SettingsNavGroup {
        switch self {
        case .providers: return .quota
        case .cursor, .chatgpt, .opencodeGo, .glm, .grok: return .accounts
        case .display, .about: return .app
        }
    }

    var provider: ProviderKind? {
        switch self {
        case .cursor: return .cursor
        case .chatgpt: return .chatgpt
        case .opencodeGo: return .opencodeGo
        case .glm: return .glm
        case .grok: return .grok
        default: return nil
        }
    }

    static func pane(for provider: ProviderKind) -> SettingsSection {
        switch provider {
        case .cursor: return .cursor
        case .chatgpt: return .chatgpt
        case .opencodeGo: return .opencodeGo
        case .glm: return .glm
        case .grok: return .grok
        }
    }
}

enum SettingsNavGroup: String, CaseIterable, Identifiable {
    case quota = "Quota"
    case accounts = "Accounts"
    case app = "App"

    var id: String { rawValue }

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

struct SettingsNavItem: View {
    let section: SettingsSection
    let selected: Bool
    var badge: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let provider = section.provider {
                        ProviderMark(
                            provider: provider,
                            size: 12,
                            tint: selected ? Theme.settingsAccent : Theme.settingsSecondary
                        )
                    } else {
                        Image(systemName: section.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? Theme.settingsAccent : Theme.settingsSecondary)
                    }
                }
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)
                Text(section.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.settingsPrimary : Theme.settingsSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.settingsTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.settingsSelectedFill : (hovering ? Theme.settingsHoverFill : Color.clear))
            )
        }
        .buttonStyle(SettingsPressStyle())
        .onHover { hovering = $0 }
        .help(section.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SettingsPaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.settingsPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.settingsSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.settingsGroupRadius, style: .continuous)
                .fill(Theme.settingsGroupFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.settingsGroupRadius, style: .continuous)
                .strokeBorder(Theme.settingsHairline, lineWidth: 1)
        )
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.settingsPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.settingsSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.settingsRowHeight)
    }
}

struct SettingsInsetHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.settingsHairline)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

struct SettingsCaption: View {
    let text: String
    var tone: Tone = .secondary

    enum Tone {
        case secondary
        case warning
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tone == .warning ? Theme.warning : Theme.settingsSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

struct SettingsLabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.settingsSecondary)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct SettingsSecretField: View {
    let placeholder: String
    @Binding var text: String
    var warning: Bool = false
    var focusID: String? = nil
    var focusedField: FocusState<String?>.Binding? = nil

    @State private var revealed = false
    @State private var hovering = false
    @FocusState private var localFocus: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.settingsPrimary)
            .textContentType(.password)
            .focusEffectDisabled()
            .modifier(SecretFocusModifier(
                localFocus: $localFocus,
                focusID: focusID,
                parentFocus: focusedField
            ))

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.settingsSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(revealed ? "Hide" : "Show")
            .accessibilityLabel(revealed ? "Hide secret" : "Show secret")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: Theme.settingsFieldHeight, maxHeight: Theme.settingsFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.settingsFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(borderColor, lineWidth: ringWidth)
        )
        .onHover { hovering = $0 }
    }

    private var isFocused: Bool {
        if let focusID, let focusedField {
            return focusedField.wrappedValue == focusID
        }
        return localFocus
    }

    private var borderColor: Color {
        if warning { return Theme.warning.opacity(0.75) }
        if isFocused { return Theme.settingsAccent.opacity(0.85) }
        if hovering { return Theme.settingsHairline.opacity(2.2) }
        return Theme.settingsHairline
    }

    private var ringWidth: CGFloat {
        (isFocused || warning) ? 1.5 : 1
    }
}

private struct SecretFocusModifier: ViewModifier {
    var localFocus: FocusState<Bool>.Binding
    let focusID: String?
    let parentFocus: FocusState<String?>.Binding?

    func body(content: Content) -> some View {
        Group {
            if let focusID, let parentFocus {
                content.focused(parentFocus, equals: focusID)
            } else {
                content.focused(localFocus)
            }
        }
    }
}

struct SettingsCodeEditor: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.settingsPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 88, maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.settingsFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focused
                            ? Theme.settingsAccent.opacity(0.85)
                            : (hovering ? Theme.settingsHairline.opacity(2.2) : Theme.settingsHairline),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
            .focused($focused)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}

struct SettingsPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var compact: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Theme.settingsPrimary)
                .padding(.horizontal, compact ? 10 : 12)
                .frame(minHeight: compact ? 26 : Theme.settingsHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.settingsAccent.opacity(fillOpacity))
                )
        }
        .buttonStyle(SettingsPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .onHover { hovering = $0 }
        .help(title)
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: compact ? 12 : 12.5, weight: .medium))
        }
    }

    private var fillOpacity: Double {
        if !enabled { return 0.35 }
        return hovering ? 1.0 : 0.88
    }
}

struct SettingsSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.settingsPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Theme.settingsHoverFill : Theme.settingsFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.settingsHairline, lineWidth: 1)
            )
        }
        .buttonStyle(SettingsPressStyle())
        .onHover { hovering = $0 }
        .help(title)
    }
}

struct SettingsIconButton: View {
    let systemName: String
    let help: String
    var destructive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: Theme.settingsIconButton, height: Theme.settingsIconButton)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Theme.settingsHoverFill : Theme.settingsFieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.settingsHairline, lineWidth: 1)
                )
        }
        .buttonStyle(SettingsPressStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var iconColor: Color {
        if destructive {
            return hovering ? Theme.settingsDanger : Theme.settingsDanger.opacity(0.88)
        }
        return hovering ? Theme.settingsPrimary : Theme.settingsSecondary
    }
}

struct SettingsEmptyState: View {
    var provider: ProviderKind? = nil
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let provider {
                    ProviderMark(provider: provider, size: 16, tint: Theme.settingsAccentSoft)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.settingsAccentSoft)
                }
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.settingsSelectedFill)
            )
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.settingsPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.settingsSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsPrimaryButton(title: actionTitle, systemImage: "plus", compact: true, action: action)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsAdvancedDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    expanded.toggle()
                } else {
                    withAnimation(.easeOut(duration: Theme.settingsMotion)) {
                        expanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.settingsSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsPressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                content()
                    .padding(.bottom, 10)
            }
        }
    }
}

struct SettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
    }
}

struct QuotaBarSettingsMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.2) {
            cap(Theme.logoBlue, 0.42)
            cap(Theme.logoPurple, 0.62)
            cap(Theme.logoGreen, 0.78)
            cap(Theme.logoTeal, 0.90)
            cap(Theme.logoAmber, 1.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: 40, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.settingsFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.settingsHairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func cap(_ color: Color, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
            .fill(color)
            .frame(width: 3.6, height: 20 * height)
    }
}
