import SwiftUI

struct AboutView: View {
    @State private var expandedFAQ: String?

    private let faqs: [(q: String, a: String)] = [
        (
            "Sind meine Daten sicher?",
            "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext."
        ),
        (
            "Welche Banken werden unterstützt?",
            "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden."
        ),
        (
            "Wie funktioniert der Import?",
            "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln."
        ),
        (
            "Ist wimg wirklich kostenlos?",
            "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten."
        ),
        (
            "Wo werden die Daten gespeichert?",
            "Im Browser: OPFS (Origin Private File System). Auf iOS: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt."
        ),
        (
            "Was ist der MCP-Server?",
            "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen, Kategorien setzen und Schulden verwalten — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert."
        ),
        (
            "Wie kann ich beitragen?",
            "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen."
        ),
    ]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Hero
                VStack(spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(WimgTheme.text)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                            .overlay {
                                Image(systemName: "creditcard")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.white)
                            }

                        Circle()
                            .fill(.green)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 4, y: 4)
                    }

                    VStack(spacing: 4) {
                        Text("wimg")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)

                        Text("Persönliche Finanzverwaltung.\nLokal. Privat. Offen.")
                            .font(.subheadline)
                            .foregroundStyle(WimgTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                // MARK: - About Text
                Text("Ein Open-Source-Projekt von **Komiljon Maksudov**. Gebaut mit **Zig**, **SwiftUI** und **SQLite**.")
                    .font(.subheadline)
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // MARK: - Privacy Badge
                HStack(spacing: 16) {
                    Circle()
                        .fill(.green)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privatsphäre zuerst")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text("Keine Werbung. Kein Tracking. Niemals.")
                            .font(.caption)
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // MARK: - GitHub Button
                Link(destination: URL(string: "https://github.com/milimyname/wimg")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.subheadline)
                        Text("GitHub")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(WimgTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WimgTheme.text, lineWidth: 2)
                    }
                }

                // MARK: - FAQ
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text("Häufig gestellte Fragen")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }

                    VStack(spacing: 8) {
                        ForEach(faqs, id: \.q) { faq in
                            VStack(spacing: 0) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        expandedFAQ = expandedFAQ == faq.q ? nil : faq.q
                                    }
                                } label: {
                                    HStack {
                                        Text(faq.q)
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(WimgTheme.text)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(WimgTheme.textSecondary)
                                            .rotationEffect(.degrees(expandedFAQ == faq.q ? 180 : 0))
                                    }
                                    .padding(16)
                                }
                                .buttonStyle(.plain)

                                if expandedFAQ == faq.q {
                                    Text(faq.a)
                                        .font(.subheadline)
                                        .foregroundStyle(WimgTheme.textSecondary)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 16)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .wimgCard()
                        }
                    }
                }

                // MARK: - Footer
                VStack(spacing: 8) {
                    Link("Was ist neu?", destination: URL(string: WimgConfig.releasesURL)!)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)

                    Text("Version \(appVersion)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(WimgTheme.textSecondary.opacity(0.6))
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(WimgTheme.bg)
        .navigationTitle("Über wimg")
        .navigationBarTitleDisplayMode(.inline)
    }
}
