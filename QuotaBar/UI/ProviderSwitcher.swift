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
                        .padding(.vertical, 5)
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

struct ChatGPTAccountSwitcher: View {
    let accounts: [ChatGPTAccount]
    @Binding var selectedID: UUID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(accounts) { account in
                    pill(account)
                }
            }
            .frame(height: Theme.accountRowHeight)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Theme.accountRowHeight)
    }

    private func pill(_ account: ChatGPTAccount) -> some View {
        Button {
            selectedID = account.id
        } label: {
            Text(account.label)
                .font(.system(size: 10.5, weight: selectedID == account.id ? .semibold : .medium))
                .foregroundStyle(selectedID == account.id ? Theme.primary : Theme.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxWidth: Theme.accountPillMaxWidth)
                .frame(height: Theme.accountRowHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedID == account.id ? Theme.switcherSelected : Theme.switcherIdle)
                )
        }
        .buttonStyle(.plain)
        .help(account.email ?? account.label)
    }
}
