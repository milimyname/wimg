import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // Feedback sheet
    @State private var showFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Hero
                VStack(spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(WimgTheme.heroText)
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

                // MARK: - Privacy Details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Datenschutz im Detail")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)

                    privacyRow("lock.fill", "Lokal gespeichert", "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig.")
                    privacyRow("key.fill", "Ende-zu-Ende verschlüsselt", "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext.")
                    privacyRow("building.columns", "FinTS direkt zur Bank", "Kein Drittanbieter zwischen dir und deiner Bank.")
                    privacyRow("eye.slash.fill", "Kein Tracking", "Keine Analytics, kein Sentry, kein Google. Null Telemetrie.")
                    privacyRow("person.fill.xmark", "Kein Account", "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität.")
                    privacyRow("brain.head.profile", "KI sieht keine Klarnamen", "MCP-Antworten werden von IBANs, BICs und Namen bereinigt.")
                }
                .padding(16)
                .background(WimgTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

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

                // MARK: - MCP Connection Guide
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.title3)
                            .foregroundStyle(.purple)
                        Text("MCP-Verbindung")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }

                    Text("Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per MCP-Protokoll Zugriff auf deine Finanzdaten geben.")
                        .font(.subheadline)
                        .foregroundStyle(WimgTheme.textSecondary)

                    // Steps
                    VStack(spacing: 8) {
                        mcpStep(number: 1, title: "Sync aktivieren", detail: "Unter Einstellungen einen Sync-Schlüssel erstellen.")
                        mcpStep(number: 2, title: "MCP-Client konfigurieren", detail: "In Claude Desktop oder Claude Code die folgende Konfiguration hinzufügen:")
                    }

                    // Config code block
                    Text("""
                    {
                      "mcpServers": {
                        "wimg": {
                          "command": "npx",
                          "args": [
                            "mcp-remote",
                            "https://wimg-sync.mili-my.name/mcp",
                            "--header",
                            "Authorization: Bearer DEIN-SYNC-SCHLÜSSEL"
                          ]
                        }
                      }
                    }
                    """)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WimgTheme.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    mcpStep(number: 3, title: "Nutzen", detail: "Frage Claude z.B. \"Zeig mir meine Ausgaben diesen Monat\" oder \"Kategorisiere meine letzten Transaktionen\".")

                    // Privacy warning
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Datenschutz-Hinweis")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.orange.opacity(0.9))
                            Text("Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten an diesen Client weitergegeben. Die Daten sind Ende-zu-Ende verschlüsselt zwischen deinen Geräten und dem Server, aber der MCP-Client selbst kann die entschlüsselten Daten lesen. Verwende nur vertrauenswürdige MCP-Clients und teile deinen Sync-Schlüssel niemals mit Dritten.")
                                .font(.caption)
                                .foregroundStyle(Color.orange.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    }
                }

                // MARK: - Feedback Button
                Button {
                    showFeedback = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.subheadline)
                        Text("Feedback senden")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .sheet(isPresented: $showFeedback) {
                    FeedbackSheetView()
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
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

    private func privacyRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                TText(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(WimgTheme.text)
                TText(detail)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
    }

    private func mcpStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.heroText)
                .frame(width: 28, height: 28)
                .background(WimgTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                TText(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(WimgTheme.text)
                TText(detail)
                    .font(.caption)
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .wimgCard()
    }
}
