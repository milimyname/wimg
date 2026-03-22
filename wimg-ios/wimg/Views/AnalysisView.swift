import SwiftUI
import Charts

struct AnalysisView: View {
    @Binding var selectedAccount: String?
    @State private var year: Int
    @State private var month: Int
    @State private var summary: MonthlySummary?
    @State private var hasAnyData = false
    @State private var selectedAngle: Double?

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
                    if !hasAnyData {
                        // Empty DB state
                        VStack(spacing: 24) {
                            Spacer().frame(height: 40)

                            ZStack {
                                Circle()
                                    .fill(WimgTheme.accent.opacity(0.2))
                                    .frame(width: 112, height: 112)
                                Image(systemName: "chart.pie.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(WimgTheme.text.opacity(0.6))
                            }

                            VStack(spacing: 8) {
                                Text("Noch keine Daten")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                Text("Importiere eine CSV-Datei, um deine Ausgaben zu analysieren.")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            NavigationLink(destination: ImportView()) {
                                Text("CSV importieren")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.heroText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WimgTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                    } else {

                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    if let cats = summary?.by_category, !cats.isEmpty {
                        // Donut chart card
                        VStack(spacing: 16) {
                            ZStack {
                                Chart(cats) { cat in
                                    SectorMark(
                                        angle: .value("Betrag", abs(cat.amount)),
                                        innerRadius: .ratio(0.58),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(WimgCategory.from(cat.id).color)
                                    .opacity(selectedCategory(cats) == nil || selectedCategory(cats)?.id == cat.id ? 1 : 0.4)
                                }
                                .chartLegend(.hidden)
                                .chartAngleSelection(value: $selectedAngle)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)

                                // Center: selected category or total
                                VStack(spacing: 2) {
                                    if let sel = selectedCategory(cats) {
                                        let wmCat = WimgCategory.from(sel.id)
                                        Image(systemName: wmCat.icon)
                                            .font(.system(size: 16))
                                            .foregroundStyle(wmCat.color)
                                        TText(sel.name)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(WimgTheme.text)
                                        Text(formatAmountShort(sel.amount))
                                            .font(.system(.headline, design: .rounded, weight: .black))
                                            .foregroundStyle(WimgTheme.text)
                                        let pct = abs(summary?.expenses ?? 1) > 0
                                            ? Int(abs(sel.amount) / abs(summary?.expenses ?? 1) * 100) : 0
                                        Text("\(pct)%")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(WimgTheme.textSecondary)
                                    } else {
                                        Text("Gesamt")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(WimgTheme.textSecondary)
                                            .textCase(.uppercase)
                                            .tracking(0.5)
                                        Text(formatAmountShort(summary?.expenses ?? 0))
                                            .font(.system(.headline, design: .rounded, weight: .black))
                                            .foregroundStyle(WimgTheme.text)
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 20)
                        .wimgCard(radius: WimgTheme.radiusLarge)
                        .padding(.horizontal)

                        // Net Worth chart
                        NetWorthCard()

                        // Spending Heatmap
                        SpendingHeatmap()

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
                        .coachmark(key: "analysis_category", text: "Tippe auf das Diagramm oder eine Kategorie")
                    } else {
                        ContentUnavailableView(
                            "Keine Ausgaben",
                            systemImage: "chart.pie",
                            description: Text("Keine Daten für diesen Monat.")
                        )
                    }

                    } // end else hasAnyData
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
                    TText(cat.name)
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

    private func selectedCategory(_ cats: [CategoryBreakdown]) -> CategoryBreakdown? {
        guard let angle = selectedAngle else { return nil }
        var cumulative = 0.0
        for cat in cats {
            cumulative += abs(cat.amount)
            if angle <= cumulative {
                return cat
            }
        }
        return cats.last
    }

    private func reload() {
        hasAnyData = ((try? LibWimg.getTransactions()) ?? []).count > 0
        summary = LibWimg.getSummaryFiltered(year: year, month: month, account: selectedAccount)
        selectedAngle = nil
    }
}
