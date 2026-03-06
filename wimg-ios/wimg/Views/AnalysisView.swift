import SwiftUI
import Charts

struct AnalysisView: View {
    @Binding var selectedAccount: String?
    @State private var year: Int
    @State private var month: Int
    @State private var summary: MonthlySummary?

    init(selectedAccount: Binding<String?>) {
        _selectedAccount = selectedAccount
        let cal = Calendar.current
        let now = Date()
        _year = State(initialValue: cal.component(.year, from: now))
        _month = State(initialValue: cal.component(.month, from: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    if let cats = summary?.by_category, !cats.isEmpty {
                        // Donut chart card
                        VStack(spacing: 16) {
                            Chart(cats) { cat in
                                SectorMark(
                                    angle: .value("Betrag", cat.amount),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(WimgCategory.from(cat.id).color)
                                .cornerRadius(4)
                            }
                            .frame(height: 220)
                            .padding(.horizontal, 20)

                            // Total
                            Text("Gesamt: \(formatAmountShort(summary?.expenses ?? 0))")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                        }
                        .padding(.vertical, 20)
                        .wimgCard(radius: WimgTheme.radiusLarge)
                        .padding(.horizontal)

                        // Category breakdown
                        VStack(spacing: 0) {
                            ForEach(cats) { cat in
                                categoryRow(cat, total: summary?.expenses ?? 1)
                                if cat.id != cats.last?.id {
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                        .wimgCard(radius: WimgTheme.radiusLarge)
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "Keine Ausgaben",
                            systemImage: "chart.pie",
                            description: Text("Keine Daten für diesen Monat.")
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Analyse")
            .onChange(of: year) { reload() }
            .onChange(of: month) { reload() }
            .onChange(of: selectedAccount) { reload() }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                reload()
            }
        }
    }

    private func categoryRow(_ cat: CategoryBreakdown, total: Double) -> some View {
        let category = WimgCategory.from(cat.id)
        let pct = total > 0 ? cat.amount / total : 0

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(cat.name)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                    Spacer()
                    Text(formatAmountShort(cat.amount))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(category.color)
                            .frame(width: geo.size.width * pct, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(cat.count) Umsätze")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func reload() {
        summary = LibWimg.getSummaryFiltered(year: year, month: month, account: selectedAccount)
    }
}
