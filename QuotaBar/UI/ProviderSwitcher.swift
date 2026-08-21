import SwiftUI

struct ProviderSwitcher: View {
    let providers: [ProviderKind]
    @Binding var selected: ProviderKind

    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers) { provider in
                Button {
                    selected = provider
                } label: {
                    Text(provider.shortTitle)
                        .font(.system(size: 11, weight: selected == provider ? .semibold : .medium))
                        .foregroundStyle(selected == provider ? Theme.primary : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected == provider ? Theme.switcherSelected : Theme.switcherIdle)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Theme.providerSwitcherHeight)
    }
}
