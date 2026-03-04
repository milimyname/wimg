import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var isPickerPresented = false
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Drop zone
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
                        .disabled(isImporting)

                        if isImporting {
                            ProgressView("Importiere...")
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // Result
                    if let result = importResult {
                        resultCard(result)
                    }

                    // Error
                    if let error = errorMessage {
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
                }
                .padding(.top, 20)
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

    private func resultCard(_ result: ImportResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Import erfolgreich!")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Format")
                        .foregroundStyle(.secondary)
                    Text(result.format)
                        .fontWeight(.medium)
                }
                GridRow {
                    Text("Zeilen")
                        .foregroundStyle(.secondary)
                    Text("\(result.total_rows)")
                        .fontWeight(.medium)
                }
                GridRow {
                    Text("Importiert")
                        .foregroundStyle(.secondary)
                    Text("\(result.imported)")
                        .fontWeight(.medium)
                }
                if result.skipped_duplicates > 0 {
                    GridRow {
                        Text("Duplikate")
                            .foregroundStyle(.secondary)
                        Text("\(result.skipped_duplicates)")
                            .fontWeight(.medium)
                    }
                }
                if result.categorized > 0 {
                    GridRow {
                        Text("Kategorisiert")
                            .foregroundStyle(.secondary)
                        Text("\(result.categorized)")
                            .fontWeight(.medium)
                    }
                }
                if result.errors > 0 {
                    GridRow {
                        Text("Fehler")
                            .foregroundStyle(.red)
                        Text("\(result.errors)")
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importResult = nil
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Zugriff auf die Datei nicht möglich."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            isImporting = true
            do {
                let data = try Data(contentsOf: url)
                let result = try LibWimg.importCSV(data)
                importResult = result
                if result.imported > 0 {
                    NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
