import SwiftUI
import WidgetKit
import WimgI18n

struct SettingsView: View {
    @State private var syncEnabled = false
    @State private var syncKey = ""
    @State private var linkInput = ""
    @State private var syncing = false
    @State private var syncError = ""
    @State private var syncSuccess = ""
    @State private var lastSync = 0

    // Locale
    @State private var currentLocale: String = UserDefaults.standard.string(forKey: "wimg_locale") ?? "de"
    private let localeOptions: [(code: String, label: String)] = [
        ("de", "Deutsch"),
        ("en", "English"),
    ]

    // Export
    @State private var showExportSheet = false

    // Data reset
    @State private var confirmReset = false
    @State private var resetting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Sync Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.orange)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(#L("Synchronisierung"))
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                if syncEnabled {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.shield.fill")
                                            .font(.system(size: 9))
                                        Text("E2E-verschlüsselt")
                                    }
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.green.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                            }
                            Text(#L("Daten zwischen Geräten synchronisieren"))
                                .font(.caption2)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }

                    if !syncError.isEmpty {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !syncSuccess.isEmpty {
                        Text(syncSuccess)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !syncEnabled {
                        Button {
                            Task { await handleEnableSync() }
                        } label: {
                            Text(syncing ? #L("Aktiviere...") : #L("Sync aktivieren"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.bg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(WimgTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(syncing)
                    } else {
                        VStack(spacing: 12) {
                            // Sync Key
                            VStack(alignment: .leading, spacing: 4) {
                                Text(#L("Sync-Schlüssel"))
                                    .font(.caption2)
                                    .foregroundStyle(WimgTheme.textSecondary)

                                HStack(spacing: 8) {
                                    Text(syncKey)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(WimgTheme.text)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(WimgTheme.bg)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button {
                                        UIPasteboard.general.string = syncKey
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                            .foregroundStyle(WimgTheme.textSecondary)
                                            .padding(10)
                                            .background(WimgTheme.bg)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }

                            // Status
                            HStack {
                                Text(#L("Letzte Sync"))
                                    .font(.subheadline)
                                    .foregroundStyle(WimgTheme.textSecondary)
                                Spacer()
                                Text(formatLastSync(lastSync))
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    .foregroundStyle(WimgTheme.text)
                            }
                            .padding(.vertical, 4)

                            Button {
                                Task { await handleSyncNow() }
                            } label: {
                                HStack(spacing: 8) {
                                    if syncing {
                                        ProgressView()
                                            .tint(WimgTheme.bg)
                                            .scaleEffect(0.8)
                                    }
                                    Text(syncing ? #L("Synchronisiere...") : #L("Jetzt synchronisieren"))
                                }
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.bg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(WimgTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .disabled(syncing)

                            // Link Device
                            VStack(alignment: .leading, spacing: 4) {
                                Text(#L("Gerät verknüpfen"))
                                    .font(.caption2)
                                    .foregroundStyle(WimgTheme.textSecondary)

                                HStack(spacing: 8) {
                                    TextField(#L("Sync-Schlüssel einfügen"), text: $linkInput)
                                        .font(.subheadline)
                                        .padding(10)
                                        .background(WimgTheme.bg)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button {
                                        Task { await handleLink() }
                                    } label: {
                                        Text(#L("Verknüpfen"))
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.orange)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .disabled(syncing || linkInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .wimgCard()

                // MARK: - Theme Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "moon.circle")
                                    .foregroundStyle(.purple)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(#L("Design"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text(#L("Hell, Dunkel oder System"))
                                .font(.caption2)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }

                    Picker("Design", selection: Binding(
                        get: { ThemeManager.shared.mode },
                        set: { ThemeManager.shared.mode = $0 }
                    )) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(L(mode.label)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(20)
                .wimgCard(radius: WimgTheme.radiusMedium)

                // MARK: - Language Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.cyan.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "globe")
                                    .foregroundStyle(.cyan)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(#L("Sprache"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text(#L("Language / Sprache"))
                                .font(.caption2)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }

                    Picker(#L("Sprache"), selection: $currentLocale) {
                        ForEach(localeOptions, id: \.code) { lang in
                            Text(L(lang.label)).tag(lang.code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: currentLocale) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "wimg_locale")
                        UserDefaults(suiteName: "group.com.wimg.app")?.set(newValue, forKey: "wimg_locale")
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
                .padding(20)
                .wimgCard(radius: WimgTheme.radiusMedium)

                // MARK: - Security Section
                securitySection

                // MARK: - About Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.gray)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(#L("Über"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text(#L("Version & Links"))
                                .font(.caption2)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }

                    Divider()

                    HStack {
                        Text(#L("Version"))
                            .font(.subheadline)
                            .foregroundStyle(WimgTheme.textSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .font(.system(.subheadline, design: .monospaced, weight: .medium))
                            .foregroundStyle(WimgTheme.text)
                    }

                    Divider()

                    Button {
                        showExportSheet = true
                    } label: {
                        HStack {
                            Text(#L("Daten exportieren"))
                                .font(.subheadline)
                                .foregroundStyle(WimgTheme.textSecondary)
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }
                    .confirmationDialog(#L("Daten exportieren"), isPresented: $showExportSheet) {
                        Button(#L("Transaktionen (CSV)")) { exportData(format: "csv") }
                        Button(#L("Backup (JSON)")) { exportData(format: "json") }
                        Button(#L("Abbrechen"), role: .cancel) {}
                    } message: {
                        Text(#L("Wähle ein Export-Format"))
                    }

                    Divider()

                    Link(destination: URL(string: WimgConfig.releasesURL)!) {
                        HStack {
                            Text("GitHub")
                                .font(.subheadline)
                                .foregroundStyle(WimgTheme.textSecondary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }
                }
                .padding(20)
                .wimgCard()

                // MARK: - Demo Data Section
                if DemoDataService.isDemoLoaded {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "flask.fill")
                                        .foregroundStyle(.orange)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(#L("Demo-Daten"))
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(WimgTheme.text)
                                    Text(#L("Aktiv"))
                                        .font(.system(.caption2, design: .rounded, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                Text(#L("Beispieldaten sind geladen"))
                                    .font(.caption2)
                                    .foregroundStyle(WimgTheme.textSecondary)
                            }
                        }

                        Button {
                            handleResetData()
                        } label: {
                            Text(#L("Demo-Daten löschen"))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                                }
                        }
                    }
                    .padding(20)
                    .wimgCard()
                }

                // MARK: - Danger Zone
                Button {
                    confirmReset = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text(#L("Alle Daten löschen"))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .confirmationDialog(#L("Alle Daten löschen?"),
                    isPresented: $confirmReset,
                    titleVisibility: .visible
                ) {
                    Button(#L("Ja, alles löschen"), role: .destructive) {
                        handleResetData()
                    }
                    Button(#L("Abbrechen"), role: .cancel) {}
                } message: {
                    Text(#L("Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden."))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(WimgTheme.bg)
        .navigationTitle(#L("Einstellungen"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                if let key = await SyncService.shared.syncKey {
                    syncEnabled = true
                    syncKey = key
                }
                lastSync = await SyncService.shared.lastSyncTimestamp
            }
        }
    }

    // MARK: - Security Section

    @ObservedObject private var biometricLock = BiometricLock.shared
    @AppStorage("wimg_lock_enabled") private var lockEnabled = false

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: lockIconName)
                            .foregroundStyle(.blue)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(#L("App-Sperre"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                    Text(lockSubtitle)
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                }
                Spacer()
            }
            Toggle(isOn: Binding(
                get: { lockEnabled },
                set: { newValue in
                    lockEnabled = newValue
                    biometricLock.setEnabled(newValue)
                }
            )) {
                Text(#L("App beim Öffnen sperren"))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.text)
            }
            .tint(WimgTheme.accent)
            .disabled(biometricLock.availableMethod == .none)

            if biometricLock.availableMethod == .none {
                Text(#L("Kein biometrischer Schutz auf diesem Gerät verfügbar."))
                    .font(.caption2)
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusMedium)
    }

    private var lockIconName: String {
        switch biometricLock.availableMethod {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .passcode: return "lock.fill"
        case .none: return "lock.slash"
        }
    }

    private var lockSubtitle: String {
        switch biometricLock.availableMethod {
        case .faceID: return #L("Mit Face ID schützen")
        case .touchID: return #L("Mit Touch ID schützen")
        case .passcode: return #L("Mit Gerätecode schützen")
        case .none: return #L("Nicht verfügbar")
        }
    }

    // MARK: - Actions

    private func handleEnableSync() async {
        let key = UUID().uuidString
        SyncService.shared.setSyncKey(key)
        syncKey = key
        syncEnabled = true
        syncError = ""
        syncSuccess = ""
        syncing = true

        do {
            _ = try await SyncService.shared.push()
            await SyncService.shared.connectWebSocket()
            syncSuccess = "Sync aktiviert & Daten hochgeladen"
            lastSync = await SyncService.shared.lastSyncTimestamp
        } catch {
            syncError = error.localizedDescription
        }
        syncing = false
    }

    private func handleSyncNow() async {
        guard !syncKey.isEmpty else { return }
        syncing = true
        syncError = ""
        syncSuccess = ""

        do {
            let (pushed, pulled) = try await SyncService.shared.syncFull()
            syncSuccess = "Synchronisiert (\(pushed) gesendet, \(pulled) empfangen)"
            lastSync = await SyncService.shared.lastSyncTimestamp
        } catch {
            syncError = error.localizedDescription
        }
        syncing = false
    }

    private func handleLink() async {
        let key = linkInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        SyncService.shared.setSyncKey(key)
        syncKey = key
        syncEnabled = true
        linkInput = ""
        syncing = true
        syncError = ""
        syncSuccess = ""

        do {
            let pulled = try await SyncService.shared.pull()
            await SyncService.shared.connectWebSocket()
            syncSuccess = "Verknüpft & \(pulled) Einträge empfangen"
            lastSync = await SyncService.shared.lastSyncTimestamp
            if pulled > 0 {
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }
        } catch {
            syncError = error.localizedDescription
        }
        syncing = false
    }

    private func handleResetData() {
        resetting = true
        LibWimg.isResetting = true

        // Defer close to next runloop tick so in-flight SwiftUI body evaluations
        // see isResetting=true and bail out before we tear down the DB.
        DispatchQueue.main.async {
            LibWimg.close()

            let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("wimg.db").path
            try? FileManager.default.removeItem(atPath: dbPath)

            Task { await SyncService.shared.disconnectWebSocket() }
            SyncService.shared.clearSyncKey()
            KeychainService.deleteAll()
            UserDefaults.standard.removeObject(forKey: "wimg_sync_last_ts")
            DemoDataService.clearDemoFlag()
            UserDefaults.standard.removeObject(forKey: "wimg_onboarding_completed")

            // Re-init with fresh DB
            try? LibWimg.initialize()
            LibWimg.isResetting = false
            syncEnabled = false
            syncKey = ""
            confirmReset = false
            resetting = false

            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
        }
    }

    private func exportData(format: String) {
        let content: String?
        let filename: String
        let date = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        if format == "csv" {
            content = LibWimg.exportCsv()
            filename = "wimg-transaktionen-\(date).csv"
        } else {
            content = LibWimg.exportDb()
            filename = "wimg-backup-\(date).json"
        }

        guard let content, let data = content.data(using: .utf8) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func formatLastSync(_ ts: Int) -> String {
        if ts == 0 { return "Noch nie" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let formatter = DateFormatter()
        let loc = UserDefaults.standard.string(forKey: "wimg_locale") ?? "de"
        formatter.locale = Locale(identifier: loc == "en" ? "en_US" : "de_DE")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
