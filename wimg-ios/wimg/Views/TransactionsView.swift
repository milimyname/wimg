import SwiftUI

struct TransactionsView: View {
    @Binding var selectedAccount: String?
    @State private var transactions: [Transaction] = []
    @State private var searchText = ""
    @State private var filter: TxFilter = .all
    @State private var selectedTransaction: Transaction?
    @State private var undoMessage: String?
    @State private var showExcluded = false

    enum TxFilter: String, CaseIterable {
        case all = "Alle"
        case expenses = "Ausgaben"
        case income = "Einnahmen"
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

        if !searchText.isEmpty {
            result = result.filter {
                $0.description.localizedCaseInsensitiveContains(searchText)
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
            VStack(spacing: 0) {
                // Segmented filter
                Picker("Filter", selection: $filter) {
                    ForEach(TxFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)

                if grouped.isEmpty {
                    ContentUnavailableView(
                        "Keine Umsätze",
                        systemImage: "tray",
                        description: Text("Importiere eine CSV-Datei um loszulegen.")
                    )
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
                            } header: {
                                Text(formatDateHeader(date))
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(WimgTheme.bg)
            .navigationTitle("Umsätze")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExcluded.toggle()
                    } label: {
                        Image(systemName: showExcluded ? "eye" : "eye.slash")
                            .foregroundStyle(showExcluded ? WimgTheme.text : WimgTheme.textSecondary)
                    }
                }
            }
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

    private func reload() {
        transactions = LibWimg.getTransactionsFiltered(account: selectedAccount).sorted { $0.date > $1.date }
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
                    // Transaction info header
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

                    // Category grid
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

    private func categoryRow(_ cat: WimgCategory) -> some View {
        Button {
            try? LibWimg.setCategory(id: transaction.id, category: UInt8(cat.rawValue))
            onDismiss()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
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
