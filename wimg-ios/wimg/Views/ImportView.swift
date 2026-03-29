import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    var onViewTransactions: (() -> Void)?

    enum Stage {
        case idle
        case preview
        case imported
    }

    @State private var stage: Stage = .idle
    @State private var isPickerPresented = false
    @State private var isParsing = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    // Preview state
    @State private var parseResult: ParseResult?
    @State private var csvData: Data?

    // Post-import state
    @State private var importResult: ImportResult?

    // Multi-file queue
    @State private var fileQueue: [URL] = []
    @State private var queueIndex = 0

    // Auto-categorize state
    @State private var rulesCategorizedCount: Int?

    private var previewTotals: (income: Double, expenses: Double) {
        guard let txns = parseResult?.transactions else { return (0, 0) }
        var income = 0.0
        var expenses = 0.0
        for txn in txns {
            if txn.amount >= 0 { income += txn.amount }
            else { expenses += txn.amount }
        }
        return (income, expenses)
    }

    var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if fileQueue.count > 1 {
                        Text("Datei \(queueIndex + 1) von \(fileQueue.count)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }

                    if stage == .idle || stage == .preview {
                        filePickerCard
                    }

                    if let error = errorMessage {
                        errorCard(error)
                    }

                    if stage == .preview, let result = parseResult {
                        previewSection(result)
                    }

                    if stage == .imported, let result = importResult {
                        importedSection(result)
                        categorizationSection
                    }

                    if stage == .idle {
                        supportedFormats
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv")!],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
    }

    // MARK: - File Picker Card

    private var filePickerCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(WimgTheme.accent.opacity(0.2))
                    .frame(width: 80, height: 80)
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 32))
                    .foregroundStyle(WimgTheme.text)
            }

            VStack(spacing: 6) {
                Text("CSV-Datei importieren")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                Text("Comdirect, Trade Republic oder Scalable Capital")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isPickerPresented = true
            } label: {
                Label("Datei auswählen", systemImage: "folder")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(WimgTheme.text)
                    .foregroundStyle(WimgTheme.bg)
                    .clipShape(Capsule())
            }
            .disabled(isParsing || isImporting)

            if isParsing {
                ProgressView("Analysiere...")
                    .font(.system(.caption, design: .rounded))
            }
        }
        .padding(28)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Preview Section

    private func previewSection(_ result: ParseResult) -> some View {
        VStack(spacing: 16) {
            // Format badge
            if result.format != "unknown" {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(formatLabel(result.format)) CSV erkannt")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text("\(result.total_rows) Zeilen gelesen")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.green.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusMedium, style: .continuous))
                .padding(.horizontal)
            }

            // Summary
            VStack(spacing: 8) {
                Text("\(result.transactions.count) Buchungen gefunden")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                HStack(spacing: 16) {
                    if previewTotals.income > 0 {
                        Label(formatAmountShort(previewTotals.income), systemImage: "arrow.down.circle.fill")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    if previewTotals.expenses < 0 {
                        Label(formatAmountShort(previewTotals.expenses), systemImage: "arrow.up.circle.fill")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .wimgCard(radius: WimgTheme.radiusMedium)
            .padding(.horizontal)

            // Transaction preview list
            VStack(spacing: 0) {
                ForEach(result.transactions.prefix(10)) { txn in
                    TransactionCard(transaction: txn)
                    if txn.id != result.transactions.prefix(10).last?.id {
                        Divider().padding(.leading, 78)
                    }
                }

                if result.transactions.count > 10 {
                    Text("... und \(result.transactions.count - 10) weitere")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .padding(.vertical, 14)
                }
            }
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    confirmImport()
                } label: {
                    Group {
                        if isImporting {
                            ProgressView()
                                .tint(WimgTheme.heroText)
                        } else {
                            Text("Importieren (\(result.transactions.count))")
                        }
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(WimgTheme.accent)
                    .foregroundStyle(WimgTheme.heroText)
                    .clipShape(Capsule())
                }
                .disabled(isImporting)

                Button {
                    cancelPreview()
                } label: {
                    Text("Abbrechen")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray5))
                        .foregroundStyle(WimgTheme.text)
                        .clipShape(Capsule())
                }
                .disabled(isImporting)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Imported Section

    private func importedSection(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            // Success card
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }

                Text("Import erfolgreich!")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Format")
                            .foregroundStyle(WimgTheme.textSecondary)
                        Text(formatLabel(result.format))
                            .fontWeight(.semibold)
                    }
                    GridRow {
                        Text("Importiert")
                            .foregroundStyle(WimgTheme.textSecondary)
                        Text("\(result.imported)")
                            .fontWeight(.semibold)
                    }
                    if result.categorized > 0 {
                        GridRow {
                            Text("Kategorisiert")
                                .foregroundStyle(WimgTheme.textSecondary)
                            Text("\(result.categorized)")
                                .fontWeight(.semibold)
                        }
                    }
                    if result.skipped_duplicates > 0 {
                        GridRow {
                            Text("Duplikate")
                                .foregroundStyle(.orange)
                            Text("\(result.skipped_duplicates)")
                                .fontWeight(.semibold)
                        }
                    }
                    if result.errors > 0 {
                        GridRow {
                            Text("Fehler")
                                .foregroundStyle(.red)
                            Text("\(result.errors)")
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .font(.system(.subheadline, design: .rounded))
            }
            .padding(24)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)

            // Next file in queue
            if fileQueue.count > 1 && queueIndex < fileQueue.count - 1 {
                Button {
                    loadNextFile()
                } label: {
                    Text("Nächste Datei laden (\(queueIndex + 2)/\(fileQueue.count))")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(WimgTheme.text)
                        .foregroundStyle(WimgTheme.bg)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
            }

            // Import another
            Button {
                fileQueue = []
                queueIndex = 0
                resetToIdle()
            } label: {
                Label("Weitere Datei importieren", systemImage: "plus.circle")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(WimgTheme.text)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            if let onViewTransactions {
                Button {
                    onViewTransactions()
                } label: {
                    Label("Transaktionen ansehen", systemImage: "list.bullet")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(WimgTheme.accent)
                        .foregroundStyle(WimgTheme.heroText)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Categorization Section

    private var categorizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kategorisierung")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            // Rules Engine
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Regel-Engine")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text("Keyword-Regeln anwenden")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }

                    Spacer()

                    Button("Starten") {
                        let count = LibWimg.autoCategorize()
                        rulesCategorizedCount = count
                        if count > 0 {
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                        }
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.heroText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WimgTheme.accent)
                    .clipShape(Capsule())
                }

                if let count = rulesCategorizedCount {
                    Text("\(count) Buchungen kategorisiert")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.leading, 58)
                }
            }
            .padding(16)
            .wimgCard(radius: WimgTheme.radiusMedium)
            .padding(.horizontal)

        }
    }

    // MARK: - Error

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

    // MARK: - Supported Formats

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unterstützte Formate")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)

            formatRow(icon: "building.columns", name: "Comdirect", detail: "Semikolon, ISO-8859-1", color: .blue)
            formatRow(icon: "chart.line.uptrend.xyaxis", name: "Trade Republic", detail: "Komma, UTF-8", color: .green)
            formatRow(icon: "arrow.up.right", name: "Scalable Capital", detail: "Semikolon, UTF-8", color: .purple)
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    private func formatRow(icon: String, name: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                TText(name)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                TText(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            fileQueue = urls
            queueIndex = 0
            processURL(urls[0])

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func processURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Zugriff auf die Datei nicht möglich."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isParsing = true
        do {
            let data = try Data(contentsOf: url)
            csvData = data
            parseResult = try LibWimg.parseCSV(data)
            stage = .preview
        } catch {
            errorMessage = error.localizedDescription
            stage = .idle
        }
        isParsing = false
    }

    private func loadNextFile() {
        queueIndex += 1
        stage = .idle
        importResult = nil
        parseResult = nil
        csvData = nil
        errorMessage = nil
        rulesCategorizedCount = nil
        processURL(fileQueue[queueIndex])
    }

    private func confirmImport() {
        guard let data = csvData else { return }
        isImporting = true
        errorMessage = nil

        do {
            let result = try LibWimg.importCSV(data)
            importResult = result
            csvData = nil
            parseResult = nil
            stage = .imported

            if result.imported > 0 {
                LibWimg.detectRecurring()
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }

    private func cancelPreview() {
        parseResult = nil
        csvData = nil
        stage = .idle
    }

    private func resetToIdle() {
        stage = .idle
        importResult = nil
        parseResult = nil
        csvData = nil
        errorMessage = nil
        rulesCategorizedCount = nil
    }

    private func formatLabel(_ format: String) -> String {
        switch format {
        case "comdirect": "Comdirect"
        case "trade_republic": "Trade Republic"
        case "scalable_capital": "Scalable Capital"
        default: format
        }
    }
}
