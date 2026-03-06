import SwiftUI

// MARK: - Friendly Finance Design System

enum WimgTheme {
    // Colors
    static let accent = Color(red: 1.0, green: 0.914, blue: 0.49)        // #FFE97D
    static let accentHover = Color(red: 1.0, green: 0.878, blue: 0.322)  // #FFE052
    static let bg = Color(red: 0.98, green: 0.976, blue: 0.965)          // #FAF9F6
    static let text = Color(red: 0.102, green: 0.102, blue: 0.102)       // #1A1A1A
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
    static let border = Color(red: 0.941, green: 0.925, blue: 0.902)     // #f0ece6
    static let cardBg = Color.white

    // Corner Radii
    static let radiusSmall: CGFloat = 20
    static let radiusMedium: CGFloat = 24
    static let radiusLarge: CGFloat = 28
    static let radiusXL: CGFloat = 32
}

// MARK: - Card Style Modifier

struct WimgCardStyle: ViewModifier {
    var radius: CGFloat = WimgTheme.radiusMedium

    func body(content: Content) -> some View {
        content
            .background(WimgTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct WimgHeroStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WimgTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusXL, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
    }
}

extension View {
    func wimgCard(radius: CGFloat = WimgTheme.radiusMedium) -> some View {
        modifier(WimgCardStyle(radius: radius))
    }

    func wimgHero() -> some View {
        modifier(WimgHeroStyle())
    }
}
