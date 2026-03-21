import SwiftUI

struct RecurringView: View {
    @State private var patterns: [RecurringPattern] = []
    @State private var detecting = false

    private var activePatterns: [RecurringPattern] {
        patterns.filter(\.isActive)
    }

    private var priceAlerts: [RecurringPattern] {
        activePatterns.filter(\.hasPriceChange)
    }

    private var monthlyTotal: Double {
        activePatterns
            .filter { $0.interval == "monthly" }
            .reduce(0) { $0 + abs($1.amount) }
    }

    private var grouped: [(String, [RecurringPattern])] {
        let order = ["weekly", "monthly", "quarterly", "annual"]
        var dict: [String: [RecurringPattern]] = [:]
        for p in activePatterns {
            dict[p.interval, default: []].append(p)
        }
        return order.compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    private let intervalLabels: [String: String] = [
        "weekly": "Wöchentlich",
        "monthly": "Monatlich",
        "quarterly": "Vierteljährlich",
        "annual": "Jährlich",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero card
                if !activePatterns.isEmpty {
                    heroCard
                }

                // Price alerts
                if !priceAlerts.isEmpty {
                    priceAlertsSection
                }

                // Section header
                HStack {
                    Text("Abonnements")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(WimgTheme.text)
                    Spacer()

                    Button {
                        handleDetect()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text(detecting ? "Erkennung..." : "Erkennen")
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.heroText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WimgTheme.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(detecting)
                }
                .padding(.horizontal)

                if activePatterns.isEmpty {
                    VStack(spacing: 8) {
                        Text("🔄")
                            .font(.system(size: 48))
                        Text("Keine Muster erkannt")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text("Importiere Transaktionen und tippe auf Erkennen")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(grouped, id: \.0) { interval, items in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(intervalLabels[interval] ?? interval)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal)

                            ForEach(items) { pattern in
                                patternCard(pattern)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(WimgTheme.bg)
        .navigationTitle("Wiederkehrend")
        .onAppear { reload() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 40, y: -40)

            VStack(spacing: 12) {
                Text("Monatliche Fixkosten")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(formatAmountShort(monthlyTotal))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-1)

                Text("\(activePatterns.count) erkannte Muster")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color.green.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusXL, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .padding(.horizontal)
    }

    // MARK: - Price Alerts

    private var priceAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preisänderungen")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            ForEach(priceAlerts) { alert in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(alert.isPriceUp ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: alert.isPriceUp ? "arrow.up" : "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(alert.isPriceUp ? .red : .green)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.merchant)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                            .lineLimit(1)
                        Text("\(formatAmountShort(abs(alert.prev_amount ?? 0))) → \(formatAmountShort(abs(alert.amount)))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }

                    Spacer()

                    Text("\(alert.isPriceUp ? "+" : "")\(formatAmountShort(alert.price_change ?? 0))")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(alert.isPriceUp ? .red : .green)
                }
                .padding(16)
                .wimgCard(radius: WimgTheme.radiusSmall)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Pattern Card

    private func patternCard(_ pattern: RecurringPattern) -> some View {
        let cat = WimgCategory.from(pattern.category)

        return HStack(spacing: 12) {
            // Category icon
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cat.color.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: cat.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(cat.color)
                }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.merchant)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let nextDue = pattern.nextDueFormatted {
                        Text(nextDue)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    Text("· Zuletzt: \(pattern.lastSeenFormatted)")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatAmountShort(abs(pattern.amount)))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                if pattern.hasPriceChange {
                    Text("\(pattern.isPriceUp ? "+" : "")\(formatAmountShort(pattern.price_change ?? 0))")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(pattern.isPriceUp ? .red : .green)
                }
            }
        }
        .padding(16)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    private func reload() {
        patterns = LibWimg.getRecurring()
    }

    private func handleDetect() {
        detecting = true
        LibWimg.detectRecurring()
        reload()
        detecting = false
    }
}
