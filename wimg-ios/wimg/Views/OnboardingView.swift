import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let cards: [(title: String, subtitle: String, icon: String, iconColor: Color, bgColor: Color)] = [
        (
            "Deine Finanzen, auf deinem Gerät",
            "Keine Cloud, kein Konto. Deine Daten bleiben auf deinem Gerät — lokal, privat, offline.",
            "lock.shield.fill",
            .green,
            Color.green.opacity(0.12)
        ),
        (
            "Importiere deine Bankdaten",
            "Lade eine CSV-Datei von Comdirect, Trade Republic oder Scalable Capital hoch.",
            "icloud.and.arrow.up.fill",
            .blue,
            Color.blue.opacity(0.12)
        ),
        (
            "Sparziele & Vermögen",
            "Setze Sparziele, verfolge deinen Fortschritt und sieh dein Nettovermögen über die Zeit.",
            "star.fill",
            .teal,
            Color.teal.opacity(0.12)
        ),
        (
            "Steuern & Sync",
            "Finde absetzbare Ausgaben für deine Steuererklärung. Synchronisiere optional zwischen Geräten — Ende-zu-Ende verschlüsselt.",
            "doc.text.fill",
            .orange,
            Color.orange.opacity(0.12)
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Überspringen") {
                    complete()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Card content
            TabView(selection: $step) {
                ForEach(0..<cards.count, id: \.self) { i in
                    VStack(spacing: 24) {
                        // Icon circle
                        ZStack {
                            Circle()
                                .fill(cards[i].bgColor)
                                .frame(width: 100, height: 100)
                            Image(systemName: cards[i].icon)
                                .font(.system(size: 36))
                                .foregroundStyle(cards[i].iconColor)
                        }

                        VStack(spacing: 12) {
                            TText(cards[i].title)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WimgTheme.text)

                            TText(cards[i].subtitle)
                                .font(.system(.body, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WimgTheme.textSecondary)
                                .padding(.horizontal, 24)
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 340)

            Spacer()

            // Action button
            Button {
                if step < cards.count - 1 {
                    withAnimation { step += 1 }
                } else {
                    complete()
                }
            } label: {
                TText(step < cards.count - 1 ? "Weiter" : "Los geht's")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.heroText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WimgTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(WimgTheme.bg)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "wimg_onboarding_completed")
        dismiss()
    }
}
