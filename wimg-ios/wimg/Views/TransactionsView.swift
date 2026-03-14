import SwiftUI

struct TransactionsView: View {
    @Binding var selectedAccount: String?
    @State private var transactions: [Transaction] = []
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var filter: TxFilter = .all
    @State private var selectedTransaction: Transaction?
    @State private var undoMessage: String?
    @State private var showExcluded = false
    @State private var selectedCategory: Int?
    @State private var showFilterSheet = false
    @State private var filterCategorySet: Set<Int> = []
    @State private var dateQuick: String?
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    @State private var amountMin: Double = 0
    @State private var amountMax: Double = 1000

    private let quickCategories: [WimgCategory] = [
        .groceries, .dining, .transport, .shopping, .entertainment,
    ]

    private let allFilterCategories: [WimgCategory] = [
        .groceries, .dining, .transport, .housing, .utilities,
        .entertainment, .shopping, .health, .insurance, .subscriptions,
        .travel, .education, .cash, .transfer, .income, .other,
    ]

    enum TxFilter: String, CaseIterable {
        case all = "Alle"
        case expenses = "Ausgaben"
        case income = "Einnahmen"
    }

    private var activeFilterCount: Int {
        (dateQuick != nil || dateFrom != nil || dateTo != nil ? 1 : 0)
            + (amountMin > 0 || amountMax < 1000 ? 1 : 0)
            + (!filterCategorySet.isEmpty ? 1 : 0)
            + (!searchText.isEmpty ? 1 : 0)
    }

    private var filtered: [Transaction] {
        var result = transactions

        if !showExcluded {
            result = result.filter { !$0.isExcluded }
        }

        switch filter {
        case .all: break
        case .expenses: result = result.filter { $0.isExpense }
        case .income: result = result.filter { $0.isIncome }
        }

        // Single quick category OR multi-select from filter sheet
        if !filterCategorySet.isEmpty {
            result = result.filter { filterCategorySet.contains($0.category) }
        } else if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Date range filter
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let dateQuick {
            let today = Date()
            let calendar = Calendar.current
            let fromDate: Date?
            switch dateQuick {
            case "30d":
                fromDate = calendar.date(byAdding: .day, value: -30, to: today)
            case "month":
                fromDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))
            case "quarter":
                fromDate = calendar.date(byAdding: .month, value: -3, to: today)
            default:
                fromDate = nil
            }
            if let fromDate {
                let fromStr = fmt.string(from: fromDate)
                result = result.filter { $0.date >= fromStr }
            }
        } else {
            if let dateFrom {
                let fromStr = fmt.string(from: dateFrom)
                result = result.filter { $0.date >= fromStr }
            }
            if let dateTo {
                let toStr = fmt.string(from: dateTo)
                result = result.filter { $0.date <= toStr }
            }
        }

        // Amount range filter
        if amountMin > 0 || amountMax < 1000 {
            result = result.filter {
                let abs = Swift.abs($0.amount)
                return abs >= amountMin && (amountMax >= 1000 || abs <= amountMax)
            }
        }

        return result
    }

    private var grouped: [(String, [Transaction])] {
        let dict = Dictionary(grouping: filtered) { $0.date }
        return dict.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .background(WimgTheme.bg)
                .navigationTitle("Umsätze")
                .toolbar { filterToolbar }
                .searchable(text: $searchText, prompt: "Suchen...")
                .onChange(of: selectedAccount) { reload() }
                .onAppear { reload() }
                .refreshable { reload() }
                .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                    reload()
                }
                .sheet(item: $selectedTransaction) { tx in
                    CategoryEditorSheet(transaction: tx) {
                        reload()
                        showUndo("Kategorie geändert")
                    }
                }
                .sheet(isPresented: $showFilterSheet) {
                    AdvancedFilterSheet(
                        searchText: $searchText,
                        dateQuick: $dateQuick,
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        amountMin: $amountMin,
                        amountMax: $amountMax,
                        filterCategorySet: $filterCategorySet,
                        showExcluded: $showExcluded,
                        allCategories: allFilterCategories
                    )
                }
                .overlay(alignment: .bottom) {
                    if let msg = undoMessage {
                        UndoToast(message: msg) {
                            performUndo()
                        }
                        .padding(.bottom, 8)
                    }
                }
        }
    }

    // MARK: - Extracted Subviews

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            segmentedFilter
            quickCategoryBar

            if let loadError {
                errorView(loadError)
            } else if grouped.isEmpty {
                ContentUnavailableView(
                    "Keine Umsätze",
                    systemImage: "tray",
                    description: Text("Importiere eine CSV-Datei um loszulegen.")
                )
            } else {
                transactionList
            }
        }
    }

    private var segmentedFilter: some View {
        Picker("Filter", selection: $filter) {
            ForEach(TxFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var quickCategoryBar: some View {
        HStack {
            ForEach(quickCategories) { cat in
                let active = selectedCategory == cat.rawValue
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = active ? nil : cat.rawValue
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(cat.color.opacity(0.12))
                                .frame(width: 52, height: 52)
                            if active {
                                Circle()
                                    .stroke(cat.color, lineWidth: 2.5)
                                    .frame(width: 52, height: 52)
                            }
                            Image(systemName: cat.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(cat.color)
                        }
                        Text(cat.name)
                            .font(.system(size: 10, weight: active ? .bold : .medium, design: .rounded))
                            .foregroundStyle(active ? WimgTheme.text : WimgTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transactionList: some View {
        List {
            ForEach(grouped, id: \.0) { date, txs in
                Section {
                    ForEach(txs) { tx in
                        transactionRow(tx)
                    }
                } header: {
                    Text(formatDateHeader(date))
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

    private func transactionRow(_ tx: Transaction) -> some View {
        TransactionCard(transaction: tx) {
            selectedTransaction = tx
        }
        .listRowInsets(EdgeInsets())
        .opacity(tx.isExcluded ? 0.4 : 1.0)
        .swipeActions(edge: .trailing) {
            Button {
                toggleExcluded(tx)
            } label: {
                Label(
                    tx.isExcluded ? "Einblenden" : "Ausblenden",
                    systemImage: tx.isExcluded ? "eye" : "eye.slash"
                )
            }
            .tint(tx.isExcluded ? .blue : .orange)
        }
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showFilterSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(activeFilterCount > 0 ? WimgTheme.text : WimgTheme.textSecondary)
                    if activeFilterCount > 0 {
                        Circle()
                            .fill(WimgTheme.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            loadError = nil
            transactions = try LibWimg.getTransactionsFiltered(account: selectedAccount).sorted { $0.date > $1.date }
        } catch {
            loadError = error.localizedDescription
            transactions = []
        }
    }

    private func showUndo(_ message: String) {
        withAnimation { undoMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if undoMessage == message { undoMessage = nil } }
        }
    }

    private func toggleExcluded(_ tx: Transaction) {
        let newExcluded = !tx.isExcluded
        try? LibWimg.setExcluded(id: tx.id, excluded: newExcluded)
        reload()
        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
        showUndo(newExcluded ? "Ausgeblendet" : "Eingeblendet")
    }

    private func performUndo() {
        if LibWimg.undo() != nil {
            reload()
            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
        }
        withAnimation { undoMessage = nil }
    }

    private func formatDateHeader(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }

        let monthNames = [
            "Januar", "Februar", "März", "April", "Mai", "Juni",
            "Juli", "August", "September", "Oktober", "November", "Dezember",
        ]
        if let day = Int(parts[2]),
           let monthIdx = Int(parts[1]),
           monthIdx >= 1, monthIdx <= 12 {
            return "\(day). \(monthNames[monthIdx - 1]) \(parts[0])"
        }
        return dateStr
    }
}

// MARK: - Category Editor Sheet

struct CategoryEditorSheet: View {
    let transaction: Transaction
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let expenseCategories: [WimgCategory] = [
        .groceries, .dining, .transport, .housing, .utilities,
        .entertainment, .shopping, .health, .insurance, .subscriptions,
        .travel, .education, .cash, .transfer, .other,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    transactionHeader
                    categoryList
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var transactionHeader: some View {
        VStack(spacing: 8) {
            Text(transaction.description)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatAmount(transaction.amount))
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(transaction.isIncome ? .green : WimgTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .wimgHero()
        .padding(.horizontal)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kategorie wählen")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                if transaction.isIncome {
                    categoryRow(.income)
                    Divider().padding(.leading, 60)
                }
                ForEach(expenseCategories) { cat in
                    categoryRow(cat)
                    if cat.id != expenseCategories.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .wimgCard(radius: WimgTheme.radiusMedium)
            .padding(.horizontal)
        }
    }

    private func categoryRow(_ cat: WimgCategory) -> some View {
        Button {
            try? LibWimg.setCategory(id: transaction.id, category: UInt8(cat.rawValue))
            onDismiss()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cat.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: cat.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(cat.color)
                }

                Text(cat.name)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.text)

                Spacer()

                if transaction.category == cat.rawValue {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WimgTheme.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Advanced Filter Sheet

struct AdvancedFilterSheet: View {
    @Binding var searchText: String
    @Binding var dateQuick: String?
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var amountMin: Double
    @Binding var amountMax: Double
    @Binding var filterCategorySet: Set<Int>
    @Binding var showExcluded: Bool
    let allCategories: [WimgCategory]

    @Environment(\.dismiss) private var dismiss

    private var hasActiveFilters: Bool {
        dateQuick != nil || dateFrom != nil || dateTo != nil || amountMin > 0 || amountMax < 1000 || !filterCategorySet.isEmpty || !searchText.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                filterContent
            }
            .background(WimgTheme.bg)
            .navigationTitle("Erweiterte Suche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                filterFooter
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Extracted Subviews

    private var filterContent: some View {
        VStack(spacing: 28) {
            searchField
            dateSection
            categorySection
            amountSection
            excludedToggle
        }
        .padding()
        .padding(.bottom, 80)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WimgTheme.textSecondary)
            TextField("Suchen nach...", text: $searchText)
                .font(.system(.body, design: .rounded))
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zeitraum")
                .font(.system(.headline, design: .rounded, weight: .bold))

            HStack(spacing: 8) {
                dateChip("30d", label: "Letzte 30 Tage")
                dateChip("month", label: "Aktueller Monat")
                dateChip("quarter", label: "Letztes Quartal")
            }

            // Custom date range
            if dateQuick == nil {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Von")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                        DatePicker("", selection: Binding(
                            get: { dateFrom ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())! },
                            set: { dateFrom = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bis")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                        DatePicker("", selection: Binding(
                            get: { dateTo ?? Date() },
                            set: { dateTo = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }
                if dateFrom != nil || dateTo != nil {
                    Button("Datum zurücksetzen") {
                        dateFrom = nil
                        dateTo = nil
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kategorien")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if !filterCategorySet.isEmpty {
                    Button("Zurücksetzen") {
                        filterCategorySet.removeAll()
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            categoryGrid
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            ForEach(allCategories) { cat in
                categoryButton(cat)
            }
        }
    }

    private func categoryButton(_ cat: WimgCategory) -> some View {
        let active = filterCategorySet.contains(cat.rawValue)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if active {
                    filterCategorySet.remove(cat.rawValue)
                } else {
                    filterCategorySet.insert(cat.rawValue)
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cat.color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    if active {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cat.color, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                    }
                    Image(systemName: cat.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(cat.color)
                }
                Text(cat.name)
                    .font(.system(size: 10, weight: active ? .bold : .medium, design: .rounded))
                    .foregroundStyle(active ? WimgTheme.text : WimgTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Betrag")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Text("\(Int(amountMin)) – \(amountMax >= 1000 ? "∞" : String(Int(amountMax))) €")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Min")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                    Slider(value: $amountMin, in: 0...500, step: 10)
                        .tint(WimgTheme.accent)
                    Text("\(Int(amountMin)) €")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .frame(width: 50, alignment: .trailing)
                }
                HStack {
                    Text("Max")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                    Slider(value: $amountMax, in: 50...1000, step: 50)
                        .tint(WimgTheme.accent)
                    Text(amountMax >= 1000 ? "∞" : "\(Int(amountMax)) €")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var excludedToggle: some View {
        Toggle(isOn: $showExcluded) {
            Text("Ausgeblendete anzeigen")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(WimgTheme.textSecondary)
        }
        .tint(WimgTheme.accent)
    }

    private var filterFooter: some View {
        VStack(spacing: 10) {
            if hasActiveFilters {
                Button {
                    searchText = ""
                    dateQuick = nil
                    dateFrom = nil
                    dateTo = nil
                    amountMin = 0
                    amountMax = 1000
                    filterCategorySet.removeAll()
                } label: {
                    Text("Zurücksetzen")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            Button {
                dismiss()
            } label: {
                Text("Ergebnisse anzeigen")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(WimgTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func dateChip(_ id: String, label: String) -> some View {
        let active = dateQuick == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                dateQuick = active ? nil : id
                dateFrom = nil
                dateTo = nil
            }
        } label: {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(active ? WimgTheme.accent : .white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(active ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
