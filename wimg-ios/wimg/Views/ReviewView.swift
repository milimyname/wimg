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
        let recurringCats = [4, 5, 9, 13]
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
                VStack(spacing: 20) {
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
                        VStack(spacing: 8) {
                            Text("\u{1F4CB}")
                                .font(.system(size: 48))
                            Text("Keine Daten für diesen Monat")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text("Importiere Bankdaten um den Rückblick zu sehen")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(WimgTheme.textSecondary)

                            NavigationLink(destination: ImportView()) {
                                Text("CSV importieren")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(WimgTheme.text)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
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
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 40, y: -40)

            VStack(spacing: 8) {
                Text(saved >= 0 ? "Gespart" : "Defizit")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.heroText.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(formatAmountShort(abs(saved)))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(WimgTheme.heroText)
                    .tracking(-1)

                if let delta = savingsDelta {
                    HStack(spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(delta >= 0 ? "+" : "")\(delta)% vs. \(monthNames[month == 1 ? 11 : month - 2])")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WimgTheme.heroText)
                    .clipShape(Capsule())
                    .padding(.top, 4)
                }

                Text(savingsMessage)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.heroText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .wimgHero()
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Einnahmen")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formatAmountShort(summary?.income ?? 0))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .wimgCard(radius: WimgTheme.radiusMedium)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ausgaben")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formatAmountShort(abs(summary?.expenses ?? 0)))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .wimgCard(radius: WimgTheme.radiusMedium)
        }
        .padding(.horizontal)
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Kategorien")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(topCategories) { cat in
                    let category = WimgCategory.from(cat.id)
                    let pct = abs(summary?.expenses ?? 1) > 0
                        ? abs(cat.amount) / abs(summary?.expenses ?? 1)
                        : 0

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: category.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(category.color)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TText(cat.name)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                Spacer()
                                Text(formatAmountShort(abs(cat.amount)))
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                            }

                            HStack(spacing: 8) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(category.color)
                                            .frame(width: geo.size.width * pct, height: 6)
                                    }
                                }
                                .frame(height: 6)

                                Text(String(format: "%.0f%%", pct * 100))
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                    .padding(16)
                    .wimgCard(radius: WimgTheme.radiusMedium)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zahlungs-Checkliste")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(checklist, id: \.description) { item in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 48, height: 48)
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.green)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.description)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .lineLimit(1)
                                .foregroundStyle(WimgTheme.text)
                            Text("am \(formatDateShort(item.date))")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(WimgTheme.textSecondary)
                        }

                        Spacer()

                        Text(formatAmountShort(abs(item.amount)))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                    }
                    .padding(16)
                    .wimgCard(radius: WimgTheme.radiusMedium)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Anomalies

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markierte Anomalien")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            if anomalies.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keine Auffälligkeiten")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("Keine ungewöhnlichen Preiserhöhungen erkannt.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.green.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.green.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusLarge, style: .continuous))
                .padding(.horizontal)
            } else {
                ForEach(anomalies, id: \.category) { item in
                    let category = WimgCategory.from(item.category)
                    let pct = item.previous > 0 ? Int((item.increase / item.previous) * 100) : 0

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Preiserhöhung erkannt")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(category.name): +\(formatAmountShort(item.increase)) (\(pct)% mehr)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        HStack(spacing: 16) {
                            Text("Vormonat: \(formatAmountShort(item.previous))")
                            Text("Aktuell: \(formatAmountShort(item.current))")
                        }
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(WimgTheme.heroText)
                    .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusLarge, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistiken")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color ?? WimgTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .wimgCard(radius: WimgTheme.radiusMedium)
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

        let all = (try? LibWimg.getTransactionsFiltered(account: selectedAccount)) ?? []
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
