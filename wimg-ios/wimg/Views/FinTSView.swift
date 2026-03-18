import SwiftUI

struct FinTSView: View {
    enum Stage {
        case bankSelect
        case credentials
        case tanChallenge
        case dateRange
        case fetching
        case result
    }

    @State private var stage: Stage = .bankSelect
    @State private var banks: [BankInfo] = []
    @State private var loadingBanks = false
    @State private var searchText = ""
    @State private var selectedBank: BankInfo?
    @State private var errorMessage: String?

    // Credentials
    @State private var kennung = ""
    @State private var pin = ""
    @State private var connecting = false

    // TAN
    @State private var challengeText = ""
    @State private var photoTanData: Data?
    @State private var showInvertedPhotoTan = false
    @State private var isDecoupledChallenge = false
    @State private var tanInput = ""
    @State private var sendingTan = false

    // Date range
    @State private var dateFrom = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    @State private var dateTo = Date()

    // Result
    @State private var importedCount = 0
    @State private var duplicateCount = 0

    private var photoTanImage: UIImage? {
        guard let data = photoTanData else { return nil }
        return UIImage(data: data)
    }

    private var filteredBanks: [BankInfo] {
        if searchText.isEmpty { return banks }
        let query = searchText.localizedLowercase
        return banks.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.blz.contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch stage {
                case .bankSelect:
                    bankSelectSection
                case .credentials:
                    credentialsSection
                case .tanChallenge:
                    tanChallengeSection
                case .dateRange:
                    dateRangeSection
                case .fetching:
                    fetchingSection
                case .result:
                    resultSection
                }

                if let error = errorMessage {
                    errorCard(error)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(WimgTheme.bg)
        .navigationTitle("Bankkonto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard banks.isEmpty else { return }
            loadingBanks = true
            Task.detached(priority: .userInitiated) {
                let loaded = LibWimg.fintsGetBanks()
                await MainActor.run {
                    banks = loaded
                    loadingBanks = false
                    // Restore saved bank + kennung from Keychain
                    if let savedBLZ = KeychainService.get(KeychainService.fintsBLZ),
                       let bank = loaded.first(where: { $0.blz == savedBLZ })
                    {
                        selectedBank = bank
                        kennung = KeychainService.get(KeychainService.fintsKennung) ?? ""
                        stage = .credentials
                    }
                }
            }
        }
    }

    // MARK: - Bank Select

    private var bankSelectSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.2))
                        .frame(width: 80, height: 80)
                    Image(systemName: "building.columns")
                        .font(.system(size: 32))
                        .foregroundStyle(WimgTheme.text)
                }

                VStack(spacing: 6) {
                    Text("Bank verbinden")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)

                    Text("Kontoauszüge direkt per FinTS abrufen")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WimgTheme.textSecondary)
                TextField("Bank suchen...", text: $searchText)
                    .font(.system(.subheadline, design: .rounded))
            }
            .padding(12)
            .background(WimgTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusSmall, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal)

            // Bank list — show max 50 results for performance
            let displayBanks = searchText.isEmpty ? Array(banks.prefix(50)) : Array(filteredBanks.prefix(50))

            VStack(spacing: 0) {
                if loadingBanks {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Lade Banken...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    Divider().padding(.leading, 70)
                }

                ForEach(displayBanks) { bank in
                    Button {
                        selectedBank = bank
                        errorMessage = nil
                        stage = .credentials
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.teal.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "building.columns")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.teal)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(bank.name)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                Text("BLZ: \(bank.blz)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(WimgTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 70)
                }

                if searchText.isEmpty {
                    Text("Suche eingeben, um alle Banken zu sehen")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .padding(.vertical, 12)
                }
            }
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.shield")
                        .font(.system(size: 28))
                        .foregroundStyle(.teal)
                }

                Text("Anmeldung")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                if let bank = selectedBank {
                    Text(bank.name)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                // BLZ (read-only)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLZ")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    Text(selectedBank?.blz ?? "")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(WimgTheme.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Kennung
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kennung")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    TextField("Benutzername / Anmeldekennung", text: $kennung)
                        .font(.subheadline)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // PIN
                VStack(alignment: .leading, spacing: 4) {
                    Text("PIN")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    SecureField("Online-Banking PIN", text: $pin)
                        .font(.subheadline)
                        .textContentType(.password)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Connect button
            Button {
                Task { await handleConnect() }
            } label: {
                Group {
                    if connecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Verbinden")
                    }
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(WimgTheme.text)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(connecting || kennung.isEmpty || pin.isEmpty)

            // Back button
            Button {
                resetToBank()
            } label: {
                Text("Andere Bank wählen")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .disabled(connecting)
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - TAN Challenge

    private var tanChallengeSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                }

                Text(isDecoupledChallenge ? "Freigabe in Banking-App" : "TAN-Eingabe")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
            }

            // photoTAN image
            if let uiImage = photoTanImage {
                VStack(spacing: 8) {
                    Text("photoTAN")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Group {
                        if showInvertedPhotoTan {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .colorInvert()
                        } else {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(maxWidth: 280, maxHeight: 280)
                    .padding(16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    Button(showInvertedPhotoTan ? "Normale Ansicht" : "Invertierte Ansicht") {
                        showInvertedPhotoTan.toggle()
                    }
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.textSecondary)
                    Text("Scannen Sie dieses Bild mit Ihrer photoTAN-App")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            }

            // Challenge text
            if !challengeText.isEmpty && photoTanImage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Challenge")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    Text(challengeText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WimgTheme.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if photoTanImage == nil && challengeText.localizedCaseInsensitiveContains("siehe grafik") {
                Text("Diese TAN-Freigabe erwartet eine scanbare Grafik. Wenn kein Bild angezeigt wird, liefert die Bank ggf. ein nicht direkt darstellbares photoTAN-Format.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if isDecoupledChallenge {
                VStack(spacing: 8) {
                    Text("Bitte in Ihrer Banking-App bestätigen.")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.text)
                        .multilineTextAlignment(.center)
                    Text("wimg prüft den Status automatisch. Falls nötig, können Sie manuell erneut prüfen.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(WimgTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                // TAN input
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAN")
                        .font(.caption2)
                        .foregroundStyle(WimgTheme.textSecondary)
                    TextField("TAN eingeben", text: $tanInput)
                        .font(.system(.subheadline, design: .monospaced))
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(WimgTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Button {
                Task { await handleSendTan() }
            } label: {
                Group {
                    if sendingTan {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isDecoupledChallenge ? "Status prüfen" : "TAN senden")
                    }
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(WimgTheme.text)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(sendingTan || (!isDecoupledChallenge && tanInput.isEmpty))
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: "calendar")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }

                Text("Zeitraum wählen")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                if let bank = selectedBank {
                    Text(bank.name)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            VStack(spacing: 12) {
                DatePicker("Von", selection: $dateFrom, displayedComponents: .date)
                    .font(.system(.subheadline, design: .rounded))
                    .environment(\.locale, Locale(identifier: "de_DE"))

                DatePicker("Bis", selection: $dateTo, displayedComponents: .date)
                    .font(.system(.subheadline, design: .rounded))
                    .environment(\.locale, Locale(identifier: "de_DE"))
            }
            .padding(12)
            .background(WimgTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                stage = .fetching
                Task { await handleFetch() }
            } label: {
                Label("Kontoauszüge abrufen", systemImage: "arrow.down.doc")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(WimgTheme.text)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Fetching

    private var fetchingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(WimgTheme.text)

            Text("Lade Kontoauszüge...")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)

            if let bank = selectedBank {
                Text(bank.name)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }

                Text("Abruf erfolgreich!")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    if let bank = selectedBank {
                        GridRow {
                            Text("Bank")
                                .foregroundStyle(WimgTheme.textSecondary)
                            Text(bank.name)
                                .fontWeight(.semibold)
                        }
                    }
                    GridRow {
                        Text("Importiert")
                            .foregroundStyle(WimgTheme.textSecondary)
                        Text("\(importedCount)")
                            .fontWeight(.semibold)
                    }
                    if duplicateCount > 0 {
                        GridRow {
                            Text("Duplikate")
                                .foregroundStyle(.orange)
                            Text("\(duplicateCount)")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(.subheadline, design: .rounded))
            }
            .padding(24)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)

            Button {
                resetToBank()
            } label: {
                Label("Weitere Bank verbinden", systemImage: "plus.circle")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(WimgTheme.text)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Error Card

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
            Text(error)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(WimgTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func handleConnect() async {
        guard let bank = selectedBank else { return }
        connecting = true
        errorMessage = nil

        do {
            // Run blocking FinTS/HTTP work on a dedicated queue to avoid
            // deadlocking the Swift cooperative thread pool (semaphore.wait
            // inside the HTTP callback blocks the current thread).
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LibWimg.fintsConnect(blz: bank.blz, user: kennung, pin: pin)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                connecting = false
                if result.isOk {
                    // Save credentials for next time (not PIN)
                    KeychainService.set(KeychainService.fintsBLZ, value: bank.blz)
                    KeychainService.set(KeychainService.fintsKennung, value: kennung)
                    stage = .dateRange
                } else if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else {
                    errorMessage = result.message ?? "Verbindung fehlgeschlagen"
                }
            }
        } catch {
            await MainActor.run {
                connecting = false
                errorMessage = friendlyError(error)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        print("[FinTS] Error: \(msg)")
        if msg.contains("HTTP request failed") || msg.contains("auth HTTP request failed") {
            return "Verbindung zur Bank fehlgeschlagen. Bitte prüfe deine Internetverbindung und versuche es erneut.\n\n(\(msg))"
        }
        if msg.contains("failed to build") {
            return "FinTS-Nachricht konnte nicht erstellt werden.\n\n(\(msg))"
        }
        if msg.contains("unknown BLZ") {
            return "Diese Bankleitzahl wird nicht unterstützt."
        }
        if msg.contains("auth") || msg.contains("Auth") {
            return "Anmeldung fehlgeschlagen. Bitte überprüfe Kennung und PIN."
        }
        return msg
    }

    private func handleSendTan() async {
        sendingTan = true
        errorMessage = nil

        do {
            let result: FintsStatusResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let outgoingTan = isDecoupledChallenge ? "" : tanInput
                        let r = try LibWimg.fintsSendTan(tan: outgoingTan)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                sendingTan = false
                if result.isOk {
                    // TAN accepted — dialog is active, fetch statements now
                    Task { await handleFetch() }
                } else if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? isDecoupledChallenge
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                } else {
                    errorMessage = result.message ?? "TAN fehlgeschlagen"
                }
            }
        } catch {
            await MainActor.run {
                sendingTan = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleFetch() async {
        errorMessage = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fromStr = formatter.string(from: dateFrom)
        let toStr = formatter.string(from: dateTo)

        do {
            let result: FintsFetchResult = try await withCheckedThrowingContinuation { continuation in
                // Use a Thread with 2MB stack (FinTS response parsing needs large stack buffers)
                let thread = Thread {
                    do {
                        let r = try LibWimg.fintsFetch(from: fromStr, to: toStr)
                        continuation.resume(returning: r)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                thread.stackSize = 2 * 1024 * 1024 // 2MB
                thread.qualityOfService = .userInitiated
                thread.start()
            }
            await MainActor.run {
                if result.needsTan {
                    isDecoupledChallenge = result.decoupled ?? false
                    challengeText = result.challenge ?? "TAN erforderlich"
                    if let b64 = result.phototan, let data = Data(base64Encoded: b64) {
                        photoTanData = data
                        showInvertedPhotoTan = false
                    } else {
                        photoTanData = nil
                        showInvertedPhotoTan = false
                    }
                    tanInput = ""
                    stage = .tanChallenge
                    if isDecoupledChallenge {
                        Task { await handleSendTan() }
                    }
                } else {
                    importedCount = result.imported ?? 0
                    duplicateCount = result.duplicates ?? 0
                    stage = .result
                    if importedCount > 0 {
                        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                stage = .dateRange
            }
        }
    }

    private func resetToBank() {
        stage = .bankSelect
        selectedBank = nil
        kennung = ""
        pin = ""
        tanInput = ""
        challengeText = ""
        isDecoupledChallenge = false
        showInvertedPhotoTan = false
        errorMessage = nil
        importedCount = 0
        duplicateCount = 0
        dateFrom = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        dateTo = Date()
    }
}
