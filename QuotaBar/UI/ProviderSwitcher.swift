import SwiftUI

struct ProviderSwitcher: View {
    let tabs: [PopoverTab]
    @Binding var selected: PopoverTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            equalWidthRow
            scrollableRow
        }
        .frame(height: Theme.providerSwitcherHeight)
        .animation(.easeOut(duration: 0.16), value: selected)
    }

    private var equalWidthRow: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                ProviderSwitcherChip(
                    title: tab.shortTitle,
                    isSelected: selected == tab,
                    fillsWidth: true
                ) {
                    selected = tab
                }
            }
        }
    }

    private var scrollableRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(tabs) { tab in
                    ProviderSwitcherChip(
                        title: tab.shortTitle,
                        isSelected: selected == tab,
                        fillsWidth: false
                    ) {
                        selected = tab
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ProviderSwitcherChip: View {
    let title: String
    let isSelected: Bool
    var fillsWidth: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: providersFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected || hovering ? Theme.primary : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.vertical, 3)
                .padding(.horizontal, fillsWidth ? 1 : 7)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Theme.switcherSelected : Theme.switcherIdle)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var providersFontSize: CGFloat { 10 }
}
