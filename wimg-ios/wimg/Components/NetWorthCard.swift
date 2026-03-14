import SwiftUI
import Charts

struct NetWorthCard: View {
    private var snapshots: [Snapshot] {
        LibWimg.getSnapshots()
    }

    private var chartData: [(date: String, cumulative: Double, monthIdx: Int)] {
        let sorted = snapshots.sorted { $0.date < $1.date }
        var cumulative = 0.0
        return sorted.map { s in
            cumulative += s.net_worth
            let month = Int(s.date.split(separator: "-").dropFirst().first ?? "1") ?? 1
            return (date: s.date, cumulative: cumulative, monthIdx: month - 1)
        }
    }

    private static let monthNames = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    var body: some View {
        let data = chartData
        guard data.count >= 2 else { return AnyView(EmptyView()) }

        let currentValue = data.last?.cumulative ?? 0
        let highest = data.max(by: { $0.cumulative < $1.cumulative })
        let lowest = data.min(by: { $0.cumulative < $1.cumulative })
        let average = data.reduce(0.0) { $0 + $1.cumulative } / Double(data.count)

        return AnyView(
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vermögen")
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.text)
                        Text(formatAmountShort(currentValue))
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(WimgTheme.text)
                            .tracking(-1)
                    }
                    Spacer()
                }

                // Chart
                Chart(data, id: \.date) { point in
                    AreaMark(
                        x: .value("Monat", point.date),
                        y: .value("Vermögen", point.cumulative)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [WimgTheme.accent.opacity(0.6), WimgTheme.accent.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Monat", point.date),
                        y: .value("Vermögen", point.cumulative)
                    )
                    .foregroundStyle(WimgTheme.text)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Monat", point.date),
                        y: .value("Vermögen", point.cumulative)
                    )
                    .foregroundStyle(WimgTheme.text)
                    .symbolSize(20)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 160)

                // Month labels
                HStack {
                    ForEach(data, id: \.date) { point in
                        Text(Self.monthNames[point.monthIdx])
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary.opacity(0.5))
                            .textCase(.uppercase)
                        if point.date != data.last?.date {
                            Spacer()
                        }
                    }
                }

                Divider()

                // Stats grid
                HStack(spacing: 0) {
                    if let h = highest {
                        statItem("Höchster", "\(Self.monthNames[h.monthIdx]) (\(formatAmountShort(h.cumulative)))")
                    }
                    if let l = lowest {
                        statItem("Niedrigster", "\(Self.monthNames[l.monthIdx]) (\(formatAmountShort(l.cumulative)))")
                    }
                    statItem("Durchschnitt", formatAmountShort(average))
                }
            }
            .padding(20)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)
        )
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(WimgTheme.textSecondary.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WimgTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
