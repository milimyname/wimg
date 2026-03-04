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
                VStack(spacing: 16) {
                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    if let cats = summary?.by_category, !cats.isEmpty {
                        // Donut
                        Chart(cats) { cat in
                            SectorMark(
                                angle: .value("Betrag", cat.amount),
                                innerRadius: .ratio(0.6),
                                angularInset: 1
                            )
                            .foregroundStyle(WimgCategory.from(cat.id).color)
                        }
                        .frame(height: 220)
                        .padding(.horizontal)

                        // Total
                        Text("Gesamt: \(formatAmountShort(summary?.expenses ?? 0))")
                            .font(.title3.bold())

                        // Category breakdown
                        VStack(spacing: 0) {
                            ForEach(cats) { cat in
                                categoryRow(cat, total: summary?.expenses ?? 1)
                                if cat.id != cats.last?.id {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "Keine Ausgaben",
                            systemImage: "chart.pie",
                            description: Text("Keine Daten für diesen Monat.")
                        )
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
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

        return HStack(spacing: 12) {
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
                    Text(formatAmountShort(cat.amount))
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
    }

    private func reload() {
        summary = LibWimg.getSummaryFiltered(year: year, month: month, account: selectedAccount)
    }
}
