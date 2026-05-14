import SwiftUI

/// Tiny "i" icon that pops a one-sentence explanation when tapped.
/// Replaces the dedicated About FAQ for first-encounter inline help.
struct InfoTooltip: View {
    let text: String
    @State private var show = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .top) {
            TText(text)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(WimgTheme.text)
                .padding(14)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}
