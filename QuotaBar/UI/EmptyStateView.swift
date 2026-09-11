import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var onSelect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?() }
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.badgeFill)
                        )
                }
                .buttonStyle(.plain)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
