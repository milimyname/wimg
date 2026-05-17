import SwiftUI
import WimgI18n

struct CategoryBadge: View {
    let category: WimgCategory

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.icon)
                .font(.caption2)
            Text(L(category.name))
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(category.color.opacity(0.12))
        .foregroundStyle(category.color)
        .clipShape(Capsule())
    }
}
