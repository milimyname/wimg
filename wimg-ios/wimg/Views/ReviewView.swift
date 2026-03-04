import SwiftUI

struct ReviewView: View {
    @Binding var selectedAccount: String?
    @State private var year: Int
    @State private var month: Int
    @State private var summary: MonthlySummary?
    @State private var prevSummary: MonthlySummary?
    @State private var monthTransactions: [Transaction] = []

    private let monthNames = [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember",
    ]

    init(selectedAccount: Binding<String?>) {
        _selectedAccount = selectedAccount
        let cal = Calendar.current
        let now = Date()
        _year = State(initialValue: cal.component(.year, from: now))
        _month = State(initialValue: cal.component(.month, from: now))
    }

    private var saved: Double {
        (summary?.income ?? 0) + (summary?.expenses ?? 0)
    }

    private var savingsDelta: Int? {
        let prevSaved = (prevSummary?.income ?? 0) + (prevSummary?.expenses ?? 0)
        guard prevSaved != 0 else { return nil }
        return Int(((saved - prevSaved) / abs(prevSaved)) * 100)
    }

    private var topCategories: [CategoryBreakdown] {
        (summary?.by_category ?? [])
            .filter { $0.id != 10 && $0.id != 11 && $0.amount != 0 }
            .sorted { abs($0.amount) > abs($1.amount) }
            .prefix(5)
            .map { $0 }
    }

    private var checklist: [(description: String, amount: Double, date: String)] {
        let recurringCats = [4, 5, 9, 13] // Housing, Utilities, Insurance, Subscriptions
        var items: [(String, Double, String)] = []

        for catId in recurringCats {
            let txns = monthTransactions.filter { $0.category == catId && $0.isExpense }
            if let biggest = txns.max(by: { abs($0.amount) < abs($1.amount) }) {
                items.append((biggest.description, biggest.amount, biggest.date))
            }
        }
        return items.sorted { $0.2 < $1.2 }
    }

    private var anomalies: [(category: Int, current: Double, previous: Double, increase: Double)] {
        guard let cats = summary?.by_category, let prevCats = prevSummary?.by_category else { return [] }
        var results: [(Int, Double, Double, Double)] = []

        for cat in cats {
            if cat.id == 10 || cat.id == 11 { continue }
            guard let prev = prevCats.first(where: { $0.id == cat.id }), prev.amount != 0 else { continue }
            let increase = abs(cat.amount) - abs(prev.amount)
            let pct = (increase / abs(prev.amount)) * 100
            if increase > 5 && pct > 10 {
                results.append((cat.id, abs(cat.amount), abs(prev.amount), increase))
            }
        }
        return results.sorted { $0.3 > $1.3 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    if (summary?.tx_count ?? 0) > 0 {
                        savingsCard
                        incomeExpenseRow

                        if !topCategories.isEmpty {
                            topCategoriesSection
                        }

                        if !checklist.isEmpty {
                            checklistSection
                        }

                        anomalySection

                        statsGrid
                    } else {
                        ContentUnavailableView(
                            "Keine Daten",
                            systemImage: "doc.text",
                            description: Text("Keine Transaktionen für diesen Monat.")
                        )
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(monthNames[month - 1]) Rückblick")
            .onChange(of: year) { reload() }
            .onChange(of: month) { reload() }
            .onChange(of: selectedAccount) { reload() }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                reload()
            }
        }
    }

    // MARK: - Savings Card

    private var savingsCard: some View {
        VStack(spacing: 8) {
            Text(saved >= 0 ? "Gespart" : "Defizit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatAmountShort(abs(saved)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(saved >= 0 ? .green : .red)

                if let delta = savingsDelta {
                    Text("\(delta >= 0 ? "+" : "")\(delta)%")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(delta >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                        .clipShape(Capsule())
                }
            }

            Text(savingsMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var savingsMessage: String {
        if saved > 0 { return "Dein Sparziel wurde erreicht. Super!" }
        if saved == 0 { return "Einnahmen und Ausgaben waren ausgeglichen." }
        return "Diesen Monat hast du mehr ausgegeben als eingenommen."
    }

    // MARK: - Income / Expenses

    private var incomeExpenseRow: some View {
        HStack(spacing: 12) {
            statBox(title: "Einnahmen", amount: summary?.income ?? 0, color: .green)
            statBox(title: "Ausgaben", amount: abs(summary?.expenses ?? 0), color: .red)
        }
        .padding(.horizontal)
    }

    private func statBox(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(formatAmountShort(amount))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Kategorien")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(topCategories) { cat in
                    let category = WimgCategory.from(cat.id)
                    let pct = abs(summary?.expenses ?? 1) > 0
                        ? abs(cat.amount) / abs(summary?.expenses ?? 1)
                        : 0

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: category.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(category.color)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(cat.name)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(formatAmountShort(abs(cat.amount)))
                                    .font(.subheadline)
                            }
                            ProgressView(value: pct)
                                .tint(category.color)
                            HStack {
                                Text("\(cat.count) Umsätze")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.0f%%", pct * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if cat.id != topCategories.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zahlungs-Checkliste")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(checklist, id: \.description) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.description)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text("am \(formatDateShort(item.date))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(formatAmountShort(abs(item.amount)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Anomalies

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anomalien")
                .font(.headline)
                .padding(.horizontal)

            if anomalies.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keine Auffälligkeiten")
                            .font(.subheadline.bold())
                        Text("Keine ungewöhnlichen Preiserhöhungen erkannt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            } else {
                ForEach(anomalies, id: \.category) { item in
                    let category = WimgCategory.from(item.category)
                    let pct = item.previous > 0 ? Int((item.increase / item.previous) * 100) : 0

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(category.name): +\(formatAmountShort(item.increase))")
                                .font(.subheadline.bold())
                            Text("\(pct)% mehr als im Vormonat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                Text("Vorher: \(formatAmountShort(item.previous))")
                                Text("Jetzt: \(formatAmountShort(item.current))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistiken")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statTile(title: "Transaktionen", value: "\(summary?.tx_count ?? 0)")
                statTile(title: "Kategorien", value: "\((summary?.by_category ?? []).filter { $0.count > 0 }.count)")
                statTile(
                    title: "Ausgaben/Tag",
                    value: formatAmountShort(
                        abs(summary?.expenses ?? 0) / Double(daysInMonth)
                    )
                )

                let rate = (summary?.income ?? 0) > 0
                    ? Int((saved / (summary?.income ?? 1)) * 100)
                    : 0
                statTile(title: "Sparquote", value: "\(rate)%", color: rate >= 0 ? .green : .red)
            }
            .padding(.horizontal)
        }
    }

    private func statTile(title: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            return Calendar.current.date(from: comps) ?? Date()
        }())?.count ?? 30
    }

    // MARK: - Data

    private func reload() {
        summary = LibWimg.getSummaryFiltered(year: year, month: month, account: selectedAccount)

        let pm = month == 1 ? 12 : month - 1
        let py = month == 1 ? year - 1 : year
        prevSummary = LibWimg.getSummaryFiltered(year: py, month: pm, account: selectedAccount)

        let all = LibWimg.getTransactionsFiltered(account: selectedAccount)
        let prefix = String(format: "%04d-%02d", year, month)
        monthTransactions = all.filter { $0.date.hasPrefix(prefix) }
    }

    private func formatDateShort(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]), let m = Int(parts[1]),
              m >= 1, m <= 12 else { return dateStr }
        let shortMonths = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        return "\(day). \(shortMonths[m - 1])"
    }
}
