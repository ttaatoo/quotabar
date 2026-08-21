import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "key")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.primary)
                .padding(.top, 4)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 6)
    }
}
