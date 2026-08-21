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
    }
}

struct ChatGPTAccountSwitcher: View {
    let accounts: [ChatGPTAccount]
    @Binding var selectedID: UUID

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { account in
                        pill(account)
                    }
                }
            }
        }
    }

    private var rows: [[ChatGPTAccount]] {
        stride(from: 0, to: accounts.count, by: 3).map { start in
            Array(accounts[start..<min(start + 3, accounts.count)])
        }
    }

    private func pill(_ account: ChatGPTAccount) -> some View {
        Button {
            selectedID = account.id
        } label: {
            Text(account.label)
                .font(.system(size: 10.5, weight: selectedID == account.id ? .semibold : .medium))
                .foregroundStyle(selectedID == account.id ? Theme.primary : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedID == account.id ? Theme.switcherSelected : Theme.switcherIdle)
                )
        }
        .buttonStyle(.plain)
        .help(account.email ?? account.label)
    }
}
