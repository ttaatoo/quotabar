import SwiftUI

struct ProviderSwitcher: View {
    let providers: [ProviderKind]
    @Binding var selected: ProviderKind

    var body: some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                ProviderSwitcherChip(
                    title: provider.shortTitle,
                    isSelected: selected == provider
                ) {
                    selected = provider
                }
            }
        }
        .frame(height: Theme.providerSwitcherHeight)
        .animation(.easeOut(duration: 0.16), value: selected)
    }
}

private struct ProviderSwitcherChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected || hovering ? Theme.primary : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .padding(.horizontal, 1)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Theme.switcherSelected : Theme.switcherIdle)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
