import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.primary)
                .buttonStyle(.plain)
        }
        .help(message)
        .frame(maxWidth: .infinity, minHeight: Theme.statusRowHeight, maxHeight: Theme.statusRowHeight)
    }
}
