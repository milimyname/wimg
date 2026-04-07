import SwiftUI
import WidgetKit

private let accent = Color(red: 1.0, green: 0.914, blue: 0.49) // #FFE97D
private let heroText = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A

private func formatAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "de_DE")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return (formatter.string(from: NSNumber(value: value)) ?? "0,00") + " \u{20AC}"
}

// MARK: - Small Widget (2x2)

struct WimgSmallWidgetView: View {
    let entry: WimgEntry

    private var sparColor: Color {
        let rate = entry.data.savingsRate
        if rate >= 20 { return .green }
        if rate >= 0 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verfügbar")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(heroText.opacity(0.6))
                .textCase(.uppercase)

            if entry.data.hasData {
                Text(formatAmount(entry.data.available))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(heroText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(sparColor)
                        .frame(width: 8, height: 8)
                    Text("Sparquote \(entry.data.savingsRate)%")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(heroText.opacity(0.7))
                }
            } else {
                Spacer()
                Text("Öffne wimg")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(heroText.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(accent.gradient, for: .widget)
    }
}

// MARK: - Lock Screen Widget (.accessoryRectangular)

struct WimgLockScreenWidgetView: View {
    let entry: WimgEntry

    var body: some View {
        Group {
            if entry.data.hasData {
                VStack(alignment: .leading, spacing: 2) {
                    Text("wimg")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .widgetAccentable()
                    Text(formatAmount(entry.data.available))
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text("Sparquote \(entry.data.savingsRate)%")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("wimg — Öffne App")
                    .font(.system(.caption, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Medium Widget (4x2)

struct WimgMediumWidgetView: View {
    let entry: WimgEntry

    private var sparColor: Color {
        let rate = entry.data.savingsRate
        if rate >= 20 { return .green }
        if rate >= 0 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: available + savings rate
            VStack(alignment: .leading, spacing: 6) {
                Text("Verfügbar")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(heroText.opacity(0.6))
                    .textCase(.uppercase)

                if entry.data.hasData {
                    Text(formatAmount(entry.data.available))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(heroText)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(sparColor)
                            .frame(width: 8, height: 8)
                        Text("Sparquote \(entry.data.savingsRate)%")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(heroText.opacity(0.7))
                    }
                } else {
                    Spacer()
                    Text("Öffne wimg")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(heroText.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: next recurring
            if let merchant = entry.data.nextMerchant,
               let amount = entry.data.nextAmount {
                Divider()
                    .frame(height: 50)
                    .padding(.horizontal, 12)
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nächste Zahlung")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText.opacity(0.6))
                        .textCase(.uppercase)

                    Text(merchant)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText)
                        .lineLimit(1)

                    Spacer()

                    Text(formatAmount(abs(amount)))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText.opacity(0.8))

                    if let dateStr = entry.data.nextDateFormatted {
                        Text(dateStr)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(heroText.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(accent.gradient, for: .widget)
    }
}

// MARK: - Large Widget (4x4)

struct WimgLargeWidgetView: View {
    let entry: WimgEntry

    private var sparColor: Color {
        let rate = entry.data.savingsRate
        if rate >= 20 { return .green }
        if rate >= 0 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VERFÜGBAR")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText.opacity(0.6))
                    Text(formatAmount(entry.data.available))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(heroText)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(sparColor).frame(width: 8, height: 8)
                    Text("Sparquote \(entry.data.savingsRate)%")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(heroText.opacity(0.7))
                }
            }

            Divider().opacity(0.2)

            // Income / Expenses
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EINNAHMEN")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText.opacity(0.5))
                    Text(formatAmount(entry.data.income))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.green.opacity(0.8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUSGABEN")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(heroText.opacity(0.5))
                    Text(formatAmount(abs(entry.data.expenses)))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer()
            }

            Divider().opacity(0.2)

            // Recent transactions
            Text("LETZTE BUCHUNGEN")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(heroText.opacity(0.5))

            if entry.data.recentTransactions.isEmpty {
                Text("Keine Transaktionen")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(heroText.opacity(0.4))
            } else {
                ForEach(Array(entry.data.recentTransactions.prefix(5).enumerated()), id: \.offset) { _, tx in
                    HStack {
                        Text(tx.desc)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(heroText)
                            .lineLimit(1)
                        Spacer()
                        Text(formatAmount(tx.amount))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(tx.amount >= 0 ? .green.opacity(0.8) : heroText)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(accent.gradient, for: .widget)
    }
}
