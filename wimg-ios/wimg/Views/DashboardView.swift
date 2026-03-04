import SwiftUI
import Charts

struct DashboardView: View {
    @State private var year: Int
    @State private var month: Int
    @State private var summary: MonthlySummary?
    @State private var recentTransactions: [Transaction] = []

    init() {
        let cal = Calendar.current
        let now = Date()
        _year = State(initialValue: cal.component(.year, from: now))
        _month = State(initialValue: cal.component(.month, from: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    // Hero: Verfügbares Einkommen
                    availableCard

                    // Income / Expenses row
                    HStack(spacing: 12) {
                        summaryCard(
                            title: "Einnahmen",
                            amount: summary?.income ?? 0,
                            color: .green,
                            icon: "arrow.down.circle"
                        )
                        summaryCard(
                            title: "Ausgaben",
                            amount: summary?.expenses ?? 0,
                            color: .red,
                            icon: "arrow.up.circle"
                        )
                    }
                    .padding(.horizontal)

                    // Category donut chart
                    if let cats = summary?.by_category, !cats.isEmpty {
                        donutSection(cats)
                    }

                    // Recent transactions
                    if !recentTransactions.isEmpty {
                        recentSection
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Übersicht")
            .onChange(of: year) { reload() }
            .onChange(of: month) { reload() }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                reload()
            }
        }
    }

    // MARK: - Cards

    private var availableCard: some View {
        VStack(spacing: 4) {
            Text("Verfügbar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formatAmountShort(summary?.available ?? 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    (summary?.available ?? 0) >= 0 ? Color.primary : Color.red
                )
            Text("\(summary?.tx_count ?? 0) Transaktionen")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func summaryCard(title: String, amount: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(formatAmountShort(amount))
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Donut

    private func donutSection(_ categories: [CategoryBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ausgaben nach Kategorie")
                .font(.headline)
                .padding(.horizontal)

            Chart(categories) { cat in
                SectorMark(
                    angle: .value("Betrag", cat.amount),
                    innerRadius: .ratio(0.6),
                    angularInset: 1
                )
                .foregroundStyle(WimgCategory.from(cat.id).color)
            }
            .frame(height: 200)
            .padding(.horizontal)

            // Legend
            ForEach(categories.prefix(5)) { cat in
                HStack {
                    Circle()
                        .fill(WimgCategory.from(cat.id).color)
                        .frame(width: 10, height: 10)
                    Text(cat.name)
                        .font(.subheadline)
                    Spacer()
                    Text(formatAmountShort(cat.amount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Recent Transactions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Letzte Umsätze")
                .font(.headline)
                .padding(.horizontal)

            ForEach(recentTransactions.prefix(5)) { tx in
                TransactionCard(transaction: tx)
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Data

    private func reload() {
        summary = LibWimg.getSummary(year: year, month: month)
        let all = LibWimg.getTransactions()
        let monthStr = String(format: "%04d-%02d", year, month)
        recentTransactions = all
            .filter { $0.date.hasPrefix(monthStr) }
            .sorted { $0.date > $1.date }
    }
}
