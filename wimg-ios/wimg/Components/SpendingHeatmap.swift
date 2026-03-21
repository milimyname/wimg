import SwiftUI

struct SpendingHeatmap: View {
    @State private var selectedCell: (year: Int, month: Int)?

    private let months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    private let cellSize: CGFloat = 28
    private let gap: CGFloat = 3

    private var snapshots: [Snapshot] {
        LibWimg.getSnapshots()
    }

    private var grid: (years: [Int], cells: [(year: Int, month: Int, amount: Double)], max: Double) {
        var map: [String: Double] = [:]
        for s in snapshots {
            let key = String(s.date.prefix(7))
            map[key] = abs(s.expenses)
        }

        let years = Array(Set(snapshots.compactMap { Int($0.date.prefix(4)) })).sorted()
        guard !years.isEmpty else { return ([], [], 0) }

        var cells: [(Int, Int, Double)] = []
        var maxVal = 0.0
        for year in years {
            for m in 0..<12 {
                let key = String(format: "%04d-%02d", year, m + 1)
                let amount = map[key] ?? 0
                if amount > maxVal { maxVal = amount }
                cells.append((year, m, amount))
            }
        }
        return (years, cells, maxVal)
    }

    private func cellColor(_ amount: Double, max: Double) -> Color {
        guard amount > 0, max > 0 else {
            return Color(.systemGray6)
        }
        let t = amount / max
        if t < 0.25 { return Color(red: 0.78, green: 0.82, blue: 0.99) } // indigo-200
        if t < 0.5 { return Color(red: 0.506, green: 0.549, blue: 0.973) } // indigo-400
        if t < 0.75 { return Color(red: 0.388, green: 0.4, blue: 0.945) } // indigo-500
        return Color(red: 0.263, green: 0.22, blue: 0.792) // indigo-700
    }

    var body: some View {
        let data = grid
        guard data.years.count >= 1, data.cells.contains(where: { $0.2 > 0 }) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ausgaben-Heatmap")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(WimgTheme.text)
                    Text("Monatliche Ausgaben im Zeitverlauf")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                // Grid
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Year headers
                        HStack(spacing: gap) {
                            // Spacer for month labels
                            Text("")
                                .frame(width: 32)
                            ForEach(data.years, id: \.self) { year in
                                Text(String(year))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .frame(width: cellSize)
                            }
                        }
                        .padding(.bottom, 4)

                        // Month rows
                        ForEach(0..<12, id: \.self) { monthIdx in
                            HStack(spacing: gap) {
                                Text(months[monthIdx])
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WimgTheme.textSecondary)
                                    .frame(width: 32, alignment: .trailing)

                                ForEach(data.years, id: \.self) { year in
                                    let cell = data.cells.first { $0.0 == year && $0.1 == monthIdx }
                                    let amount = cell?.2 ?? 0
                                    let isSelected = selectedCell?.year == year && selectedCell?.month == monthIdx

                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(cellColor(amount, max: data.max))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(isSelected ? WimgTheme.text : .clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if isSelected {
                                                    selectedCell = nil
                                                } else {
                                                    selectedCell = (year: year, month: monthIdx)
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, gap / 2)
                        }
                    }
                }

                // Selected cell info
                if let sel = selectedCell,
                   let cell = data.cells.first(where: { $0.0 == sel.year && $0.1 == sel.month }) {
                    HStack(spacing: 8) {
                        Text("\(months[sel.month]) \(String(sel.year))")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Spacer()
                        Text(formatAmountShort(cell.2))
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
                }

                // Legend
                HStack(spacing: 6) {
                    Spacer()
                    Text("Wenig")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(.systemGray6)).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.78, green: 0.82, blue: 0.99)).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.506, green: 0.549, blue: 0.973)).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.388, green: 0.4, blue: 0.945)).frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.263, green: 0.22, blue: 0.792)).frame(width: 10, height: 10)
                    }
                    Text("Viel")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }
            .padding(20)
            .wimgCard(radius: WimgTheme.radiusLarge)
            .padding(.horizontal)
        )
    }
}
