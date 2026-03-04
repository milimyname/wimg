import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
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

    // Auto-categorize state
    @State private var rulesCategorizedCount: Int?
    @State private var claudeLoading = false
    @State private var claudeResult: ClaudeResult?
    @State private var showApiKeyInput = false
    @State private var apiKeyDraft = ""

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - File Picker Card

    private var filePickerCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("CSV-Datei importieren")
                .font(.title3.bold())

            Text("Comdirect, Trade Republic oder Scalable Capital")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isPickerPresented = true
            } label: {
                Label("Datei auswählen", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isParsing || isImporting)

            if isParsing {
                ProgressView("Analysiere...")
            }
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Preview Section

    private func previewSection(_ result: ParseResult) -> some View {
        VStack(spacing: 16) {
            // Format badge
            if result.format != "unknown" {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(formatLabel(result.format)) CSV erkannt")
                            .font(.subheadline.bold())
                        Text("\(result.total_rows) Zeilen gelesen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            // Summary
            VStack(spacing: 8) {
                Text("\(result.transactions.count) Buchungen gefunden")
                    .font(.headline)

                HStack(spacing: 16) {
                    if previewTotals.income > 0 {
                        Label(formatAmountShort(previewTotals.income), systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if previewTotals.expenses < 0 {
                        Label(formatAmountShort(previewTotals.expenses), systemImage: "arrow.up.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Transaction preview list
            VStack(spacing: 0) {
                ForEach(result.transactions.prefix(10)) { txn in
                    TransactionCard(transaction: txn)
                    if txn.id != result.transactions.prefix(10).last?.id {
                        Divider().padding(.leading, 52)
                    }
                }

                if result.transactions.count > 10 {
                    Text("... und \(result.transactions.count - 10) weitere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    confirmImport()
                } label: {
                    Group {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Importieren (\(result.transactions.count))")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isImporting)

                Button {
                    cancelPreview()
                } label: {
                    Text("Abbrechen")
                        .font(.headline)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)

                Text("Import erfolgreich!")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Format").foregroundStyle(.secondary)
                        Text(formatLabel(result.format)).fontWeight(.medium)
                    }
                    GridRow {
                        Text("Importiert").foregroundStyle(.secondary)
                        Text("\(result.imported)").fontWeight(.medium)
                    }
                    if result.categorized > 0 {
                        GridRow {
                            Text("Kategorisiert").foregroundStyle(.secondary)
                            Text("\(result.categorized)").fontWeight(.medium)
                        }
                    }
                    if result.skipped_duplicates > 0 {
                        GridRow {
                            Text("Duplikate").foregroundStyle(.orange)
                            Text("\(result.skipped_duplicates)").fontWeight(.medium)
                        }
                    }
                    if result.errors > 0 {
                        GridRow {
                            Text("Fehler").foregroundStyle(.red)
                            Text("\(result.errors)").fontWeight(.medium).foregroundStyle(.red)
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            // Import another
            Button {
                resetToIdle()
            } label: {
                Label("Weitere Datei importieren", systemImage: "plus.circle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Categorization Section

    private var categorizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kategorisierung")
                .font(.headline)
                .padding(.horizontal)

            // Rules Engine
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Regel-Engine").font(.subheadline.bold())
                        Text("Keyword-Regeln auf unkategorisierte Buchungen anwenden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Starten") {
                        let count = LibWimg.autoCategorize()
                        rulesCategorizedCount = count
                        if count > 0 {
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                }

                if let count = rulesCategorizedCount {
                    Text("\(count) Buchungen kategorisiert")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.leading, 48)
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Claude AI
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.purple)
                        .frame(width: 36, height: 36)
                        .background(.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Claude AI").font(.subheadline.bold())
                            if ClaudeAPI.hasKey {
                                Text("Aktiv")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("KI-Kategorisierung für verbleibende Buchungen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // API Key Input
                if !ClaudeAPI.hasKey || showApiKeyInput {
                    HStack(spacing: 8) {
                        SecureField("sk-ant-...", text: $apiKeyDraft)
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)

                        Button("Speichern") {
                            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                ClaudeAPI.setKey(trimmed)
                                showApiKeyInput = false
                                apiKeyDraft = ""
                            }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.leading, 48)

                    Text("Nur lokal gespeichert. Wird nur an die Anthropic API gesendet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 48)
                }

                // Actions when key exists
                if ClaudeAPI.hasKey {
                    HStack(spacing: 8) {
                        Button {
                            runClaudeCategorize()
                        } label: {
                            if claudeLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Mit Claude kategorisieren")
                            }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(claudeLoading)

                        Button(showApiKeyInput ? "Abbrechen" : "Key ändern") {
                            showApiKeyInput.toggle()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !showApiKeyInput {
                            Button("Entfernen") {
                                ClaudeAPI.removeKey()
                                showApiKeyInput = false
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.leading, 48)
                }

                // Claude Result
                if let result = claudeResult {
                    VStack(alignment: .leading, spacing: 4) {
                        if result.categorized > 0 {
                            Text("\(result.categorized) Buchungen von Claude kategorisiert")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if result.errors.isEmpty {
                            Text("Keine unkategorisierten Buchungen gefunden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.errors, id: \.self) { err in
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.leading, 48)
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func runClaudeCategorize() {
        claudeLoading = true
        claudeResult = nil

        Task {
            let transactions = LibWimg.getTransactions()
            let result = await ClaudeAPI.categorize(transactions: transactions)
            await MainActor.run {
                claudeResult = result
                claudeLoading = false
                if result.categorized > 0 {
                    NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                }
            }
        }
    }

    // MARK: - Error

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.red)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Supported Formats

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unterstützte Formate")
                .font(.headline)

            formatRow(code: "CD", name: "Comdirect", detail: "Semikolon, ISO-8859-1", color: .blue)
            formatRow(code: "TR", name: "Trade Republic", detail: "Komma, UTF-8", color: .green)
            formatRow(code: "SC", name: "Scalable Capital", detail: "Semikolon, UTF-8", color: .purple)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func formatRow(code: String, name: String, detail: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(code)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
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

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
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
        claudeResult = nil
        claudeLoading = false
        showApiKeyInput = false
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
