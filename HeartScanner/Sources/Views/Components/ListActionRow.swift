import SwiftUI

struct ListActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(isEnabled ? color : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .primary : .gray)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Image(systemName: "chevron.right")
            //     .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
