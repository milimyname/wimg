import SwiftUI

struct CoachmarkModifier: ViewModifier {
    let key: String
    let text: String

    @State private var visible: Bool

    init(key: String, text: String) {
        self.key = key
        self.text = text
        _visible = State(initialValue: CoachmarkManager.shared.shouldShow(key))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if visible {
                    VStack(spacing: 0) {
                        // Arrow pointing up
                        Triangle()
                            .fill(Color(.systemGray6))
                            .frame(width: 12, height: 6)

                        HStack(spacing: 10) {
                            Text(text)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(WimgTheme.text)

                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    visible = false
                                }
                                CoachmarkManager.shared.dismiss(key)
                            } label: {
                                Text("OK")
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.bg)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(WimgTheme.text)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    }
                    .offset(y: 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    func coachmark(key: String, text: String) -> some View {
        modifier(CoachmarkModifier(key: key, text: text))
    }
}
