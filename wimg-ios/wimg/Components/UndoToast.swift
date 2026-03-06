import SwiftUI

struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button("Rückgängig") {
                onUndo()
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(WimgTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(WimgTheme.text.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusSmall, style: .continuous))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
