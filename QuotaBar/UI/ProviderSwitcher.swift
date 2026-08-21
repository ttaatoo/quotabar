import SwiftUI

struct ProviderSwitcher: View {
    let providers: [ProviderKind]
    @Binding var selected: ProviderKind

    var body: some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                Button {
                    selected = provider
                } label: {
                    Text(provider.shortTitle)
                        .font(.system(size: 10, weight: selected == provider ? .semibold : .medium))
                        .foregroundStyle(selected == provider ? Theme.primary : Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected == provider ? Theme.switcherSelected : Theme.switcherIdle)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Theme.providerSwitcherHeight)
    }
}
