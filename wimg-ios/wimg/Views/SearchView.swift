import SwiftUI

struct SearchView: View {
    @Binding var selectedAccount: String?
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var transactions: [Transaction] = []
    @State private var loadingTransactions = false
    @State private var reloadToken: UUID = .init()
    @State private var selectedTransaction: Transaction?
    @State private var undoMessage: String?
    @State private var showFeedback = false
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    @State private var amountMin: Double = 0
    @State private var amountMax: Double = 1000
    @State private var filterCategories: Set<Int> = []

    private static let isoFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private let allCategories: [WimgCategory] = [
        .groceries, .dining, .transport, .housing, .utilities,
        .entertainment, .shopping, .health, .insurance, .subscriptions,
        .travel, .education, .cash, .transfer, .income, .other,
    ]

    private var filtered: [Transaction] {
        var result = transactions

        if !debouncedSearch.isEmpty {
            result = result.filter {
                $0.description.localizedCaseInsensitiveContains(debouncedSearch)
            }
        }

        if !filterCategories.isEmpty {
            result = result.filter { filterCategories.contains($0.category) }
        }

        if let dateFrom {
            let fromStr = Self.isoFormatter.string(from: dateFrom)
            result = result.filter { $0.date >= fromStr }
        }
        if let dateTo {
            let toStr = Self.isoFormatter.string(from: dateTo)
            result = result.filter { $0.date <= toStr }
        }

        if amountMin > 0 || amountMax < 1000 {
            result = result.filter {
                let abs = Swift.abs($0.amount)
                return abs >= amountMin && (amountMax >= 1000 || abs <= amountMax)
            }
        }

        return result
    }

    private var grouped: [(String, [Transaction])] {
        Dictionary(grouping: filtered) { $0.date }
            .sorted { $0.key > $1.key }
    }

    private var hasActiveFilters: Bool {
        dateFrom != nil || dateTo != nil || amountMin > 0 || amountMax < 1000 || !filterCategories.isEmpty
    }

    private var isSearching: Bool {
        !debouncedSearch.isEmpty || hasActiveFilters
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Active filter chips
                if hasActiveFilters {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if dateFrom != nil || dateTo != nil {
                                filterChip("Zeitraum") {
                                    dateFrom = nil
                                    dateTo = nil
                                }
                            }
                            if amountMin > 0 || amountMax < 1000 {
                                filterChip("\(Int(amountMin))–\(amountMax >= 1000 ? "∞" : String(Int(amountMax))) €") {
                                    amountMin = 0
                                    amountMax = 1000
                                }
                            }
                            if !filterCategories.isEmpty {
                                filterChip("\(filterCategories.count) Kategorien") {
                                    filterCategories.removeAll()
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                if isSearching {
                    // Search results
                    if filtered.isEmpty {
                        if loadingTransactions {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Lade Transaktionen...")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WimgTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        List {
                            ForEach(grouped, id: \.0) { date, txs in
                                Section {
                                    ForEach(txs) { tx in
                                        TransactionCard(transaction: tx) {
                                            selectedTransaction = tx
                                        }
                                        .listRowInsets(EdgeInsets())
                                        .opacity(tx.isExcluded ? 0.4 : 1.0)
                                    }
                                } header: {
                                    Text(date)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(WimgTheme.textSecondary)
                                        .textCase(.uppercase)
                                        .tracking(0.8)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                } else {
                    // Navigation + Quick actions when not searching
                    quickActionsView
                }
            }
            .background(WimgTheme.bg)
            .navigationTitle("Suche")
            .searchable(text: $searchText, prompt: "Transaktionen suchen...")
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                debouncedSearch = searchText
            }
            .toolbar { filterToolbar }
            .onAppear { reload() }
            .onChange(of: selectedAccount) { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                reload()
            }
            .sheet(item: $selectedTransaction) { tx in
                CategoryEditorSheet(transaction: tx) {
                    reload()
                    showUndo("Kategorie geändert")
                }
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackSheetView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .bottom) {
                if let msg = undoMessage {
                    UndoToast(message: msg) {
                        if LibWimg.undo() != nil {
                            reload()
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                        }
                        withAnimation { undoMessage = nil }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Navigation
                actionSection("Navigation") {
                    navLink("Analyse", icon: "chart.bar", color: .indigo) {
                        AnalysisView(selectedAccount: $selectedAccount)
                    }
                    navLink("Schulden", icon: "creditcard", color: .pink, feature: "debts") {
                        DebtsView()
                    }
                    navLink("Sparziele", icon: "target", color: .yellow, feature: "goals") {
                        GoalsView()
                    }
                    navLink("Wiederkehrend", icon: "arrow.triangle.2.circlepath", color: .green, feature: "recurring") {
                        RecurringView()
                    }
                    navLink("Steuern", icon: "doc.text", color: .orange, feature: "tax") {
                        TaxView()
                    }
                    navLink("Rückblick", icon: "calendar", color: .purple, feature: "review") {
                        ReviewView(selectedAccount: $selectedAccount)
                    }
                    navLink("Bankverbindung", icon: "building.columns", color: .teal) {
                        FinTSView()
                    }
                    navLink("Import", icon: "square.and.arrow.down", color: .blue) {
                        ImportView()
                    }
                    navLink("Einstellungen", icon: "gearshape", color: .gray) {
                        SettingsView()
                    }
                    navLink("Über wimg", icon: "info.circle", color: .gray) {
                        AboutView()
                    }
                    actionButton("Feedback senden", icon: "bubble.left.and.bubble.right", color: .indigo) {
                        showFeedback = true
                    }
                }

                // Help / FAQ
                actionSection("Hilfe") {
                    navLink("Sind meine Daten sicher?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Sind meine Daten sicher?")
                    }
                    navLink("Welche Banken werden unterstützt?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Welche Banken werden unterstützt?")
                    }
                    navLink("Wie funktioniert der Import?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie funktioniert der Import?")
                    }
                    navLink("Wie funktioniert die Kategorisierung?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie funktioniert die Kategorisierung?")
                    }
                    navLink("Ist wimg wirklich kostenlos?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Ist wimg wirklich kostenlos?")
                    }
                    navLink("Wo werden die Daten gespeichert?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wo werden die Daten gespeichert?")
                    }
                    navLink("Was ist der MCP-Server?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Was ist der MCP-Server?")
                    }
                    navLink("Wie funktioniert Auto-Learn?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie funktioniert Auto-Learn?")
                    }
                    navLink("Was zeigt das Vermögens-Diagramm?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Was zeigt das Vermögens-Diagramm?")
                    }
                    navLink("Wie synchronisiere ich?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie synchronisiere ich zwischen Geräten?")
                    }
                    navLink("Wie funktionieren Sparziele?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie funktionieren Sparziele?")
                    }
                    navLink("Wie erkennt wimg Abos?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie erkennt wimg Abos und wiederkehrende Zahlungen?")
                    }
                    navLink("Funktioniert wimg offline?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Funktioniert wimg offline?")
                    }
                    navLink("Gibt es einen Dark Mode?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Gibt es einen Dark Mode?")
                    }
                    navLink("Kann ich mehrere Konten verwalten?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Kann ich mehrere Konten verwalten?")
                    }
                    navLink("Kann ich Änderungen rückgängig machen?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Kann ich Änderungen rückgängig machen?")
                    }
                    navLink("Was kann die Steuern-Seite?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Was kann die Steuern-Seite?")
                    }
                    navLink("Wie lösche ich meine Daten?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie lösche ich meine Daten?")
                    }
                    navLink("Was ist die Sparquote?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Was ist die Sparquote?")
                    }
                    navLink("Was zeigt die Ausgaben-Heatmap?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Was zeigt die Ausgaben-Heatmap?")
                    }
                    navLink("Wie kann ich beitragen?", icon: "questionmark.circle", color: .orange) {
                        AboutView(scrollToFAQ: "Wie kann ich beitragen?")
                    }
                    navLink("MCP-Verbindung einrichten", icon: "link", color: .purple) {
                        AboutView()
                    }
                }

                // Categorization
                actionSection("Kategorisierung") {
                    actionButton("Auto-Kategorisieren", icon: "tag", color: .orange) {
                        let n = LibWimg.autoCategorize()
                        showUndo(n > 0 ? "\(n) kategorisiert" : "Keine neuen Kategorien")
                    }
                    actionButton("Wiederkehrende erkennen", icon: "arrow.triangle.2.circlepath", color: .green) {
                        let n = LibWimg.detectRecurring()
                        showUndo(n > 0 ? "\(n) Muster erkannt" : "Keine neuen Muster")
                    }
                }

                // Data
                actionSection("Daten") {
                    actionButton("Snapshot erstellen", icon: "camera", color: .blue) {
                        let now = Date()
                        let cal = Calendar.current
                        try? LibWimg.takeSnapshot(
                            year: cal.component(.year, from: now),
                            month: cal.component(.month, from: now)
                        )
                        showUndo("Snapshot erstellt")
                    }
                    actionButton("Snapshots für alle Monate", icon: "camera.fill", color: .blue) {
                        let txns = (try? LibWimg.getTransactions()) ?? []
                        guard !txns.isEmpty else {
                            showUndo("Keine Transaktionen vorhanden")
                            return
                        }
                        var months = Set<String>()
                        for tx in txns { months.insert(String(tx.date.prefix(7))) }
                        var count = 0
                        for m in months {
                            let parts = m.split(separator: "-").compactMap { Int($0) }
                            guard parts.count == 2 else { continue }
                            try? LibWimg.takeSnapshot(year: parts[0], month: parts[1])
                            count += 1
                        }
                        showUndo("\(count) Snapshots erstellt")
                    }
                    actionButton("CSV exportieren", icon: "square.and.arrow.up", color: .indigo) {
                        exportCsv()
                    }
                    actionButton("Datenbank exportieren", icon: "externaldrive", color: .purple) {
                        exportDb()
                    }
                }

                // Undo/Redo
                actionSection("Bearbeiten") {
                    actionButton("Rückgängig", icon: "arrow.uturn.backward", color: .gray) {
                        if let result = LibWimg.undo() {
                            reload()
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                            showUndo("Rückgängig: \(result.op) \(result.table)")
                        }
                    }
                    actionButton("Wiederherstellen", icon: "arrow.uturn.forward", color: .gray) {
                        if let result = LibWimg.redo() {
                            reload()
                            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                            showUndo("Wiederhergestellt: \(result.op) \(result.table)")
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
    }

    private func actionSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .wimgCard()
        }
    }

    @ViewBuilder
    private func navLink<V: View>(_ label: String, icon: String, color: Color, feature: String? = nil, @ViewBuilder destination: @escaping () -> V) -> some View {
        if let feature, !FeatureFlags.shared.isEnabled(feature) {
            EmptyView()
        } else {
            NavigationLink {
                LazyDestination(destination)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(color.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(color)
                    }

                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.text)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
        }
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Filter Toolbar

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu("Zeitraum") {
                    Button("Letzte 30 Tage") {
                        dateFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                        dateTo = nil
                    }
                    Button("Aktueller Monat") {
                        dateFrom = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
                        dateTo = nil
                    }
                    Button("Letztes Quartal") {
                        dateFrom = Calendar.current.date(byAdding: .month, value: -3, to: Date())
                        dateTo = nil
                    }
                    if dateFrom != nil {
                        Divider()
                        Button("Zurücksetzen", role: .destructive) {
                            dateFrom = nil
                            dateTo = nil
                        }
                    }
                }

                Menu("Betrag") {
                    Button("< 50 €") { amountMin = 0; amountMax = 50 }
                    Button("50 – 200 €") { amountMin = 50; amountMax = 200 }
                    Button("> 200 €") { amountMin = 200; amountMax = 1000 }
                    if amountMin > 0 || amountMax < 1000 {
                        Divider()
                        Button("Zurücksetzen", role: .destructive) { amountMin = 0; amountMax = 1000 }
                    }
                }

                Menu("Kategorien") {
                    ForEach(allCategories) { cat in
                        Button {
                            if filterCategories.contains(cat.rawValue) {
                                filterCategories.remove(cat.rawValue)
                            } else {
                                filterCategories.insert(cat.rawValue)
                            }
                        } label: {
                            Label(cat.name, systemImage: filterCategories.contains(cat.rawValue) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    if !filterCategories.isEmpty {
                        Divider()
                        Button("Zurücksetzen", role: .destructive) { filterCategories.removeAll() }
                    }
                }

                if hasActiveFilters {
                    Divider()
                    Button("Alle Filter zurücksetzen", role: .destructive) {
                        dateFrom = nil
                        dateTo = nil
                        amountMin = 0
                        amountMax = 1000
                        filterCategories.removeAll()
                    }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(hasActiveFilters ? WimgTheme.text : WimgTheme.textSecondary)
                    if hasActiveFilters {
                        Circle()
                            .fill(WimgTheme.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func filterChip(_ label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
            Button {
                withAnimation { onRemove() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(WimgTheme.heroText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(WimgTheme.accent)
        .clipShape(Capsule())
    }

    private func reload() {
        let token = UUID()
        reloadToken = token
        loadingTransactions = true
        let account = selectedAccount
        Task.detached(priority: .userInitiated) {
            let loaded = ((try? LibWimg.getTransactionsFiltered(account: account)) ?? [])
                .sorted { $0.date > $1.date }
            await MainActor.run {
                // Ignore stale completions if a newer reload started.
                guard reloadToken == token else { return }
                transactions = loaded
                loadingTransactions = false
            }
        }
    }

    private func showUndo(_ message: String) {
        withAnimation { undoMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if undoMessage == message { undoMessage = nil } }
        }
    }

    private func exportCsv() {
        guard let csv = LibWimg.exportCsv() else { return }
        shareText(csv, filename: "wimg-export.csv")
    }

    private func exportDb() {
        guard let json = LibWimg.exportDb() else { return }
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        shareText(json, filename: "wimg-backup-\(date).json")
    }

    private func shareText(_ content: String, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

/// Defers view creation until navigation occurs.
private struct LazyDestination<Content: View>: View {
    let build: () -> Content
    init(_ build: @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}
