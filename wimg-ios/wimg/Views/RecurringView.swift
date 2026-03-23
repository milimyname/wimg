import SwiftUI

struct RecurringView: View {
    @State private var patterns: [RecurringPattern] = []
    @State private var detecting = false
    @State private var tab = 0 // 0 = subscriptions, 1 = calendar

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

    // MARK: - Calendar Data

    private struct FuturePayment: Identifiable {
        let id = UUID()
        let date: Date
        let dateStr: String
        let merchant: String
        let amount: Double
        let category: Int
        let interval: String
    }

    private var futurePayments: [FuturePayment] {
        let now = Date()
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .year, value: 1, to: now) else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var payments: [FuturePayment] = []

        for p in activePatterns {
            guard let nextDue = p.next_due, let startDate = df.date(from: nextDue) else { continue }
            var d = startDate
            // Step forward if overdue
            while d < now {
                d = addInterval(d, p.interval)
            }
            while d <= end {
                payments.append(FuturePayment(
                    date: d,
                    dateStr: df.string(from: d),
                    merchant: p.merchant,
                    amount: p.amount,
                    category: p.category,
                    interval: p.interval
                ))
                d = addInterval(d, p.interval)
            }
        }
        return payments.sorted { $0.date < $1.date }
    }

    private func addInterval(_ date: Date, _ interval: String) -> Date {
        let cal = Calendar.current
        switch interval {
        case "weekly": return cal.date(byAdding: .day, value: 7, to: date) ?? date
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date) ?? date
        case "quarterly": return cal.date(byAdding: .month, value: 3, to: date) ?? date
        case "annual": return cal.date(byAdding: .year, value: 1, to: date) ?? date
        default: return cal.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }

    private var paymentsByMonth: [(String, [FuturePayment])] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        var dict: [String: [FuturePayment]] = [:]
        for p in futurePayments {
            let key = df.string(from: p.date)
            dict[key, default: []].append(p)
        }
        return dict.sorted { $0.key < $1.key }
    }

    private var next30DaysPayments: [FuturePayment] {
        let now = Date()
        let limit = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        return futurePayments.filter { $0.date >= now && $0.date <= limit }
    }

    private var next30DaysTotal: Double {
        next30DaysPayments.reduce(0) { $0 + abs($1.amount) }
    }

    private struct MonthOverview: Identifiable {
        let id: String // "2026-04"
        let label: String
        let total: Double
    }

    private var monthlyOverview: [MonthOverview] {
        let cal = Calendar.current
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE")
        let labelFmt = DateFormatter()
        labelFmt.locale = locale

        var months: [MonthOverview] = []
        for i in 0..<12 {
            guard let monthDate = cal.date(byAdding: .month, value: i, to: now) else { continue }
            let key = df.string(from: monthDate)
            if i == 0 || cal.component(.month, from: monthDate) == 1 {
                labelFmt.dateFormat = "MMM yy"
            } else {
                labelFmt.dateFormat = "MMM"
            }
            let label = labelFmt.string(from: monthDate)
            let total = paymentsByMonth
                .first { $0.0 == key }?
                .1.reduce(0) { $0 + abs($1.amount) } ?? 0
            months.append(MonthOverview(id: key, label: label, total: total))
        }
        return months
    }

    private var maxMonthlyTotal: Double {
        max(monthlyOverview.map(\.total).max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Segmented control
                if !activePatterns.isEmpty {
                    Picker("Tab", selection: $tab) {
                        Text("Abonnements").tag(0)
                        Text("Kalender").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                if tab == 0 {
                    subscriptionsTab
                } else {
                    calendarTab
                }
            }
            .padding(.bottom, 24)
        }
        .background(WimgTheme.bg)
        .navigationTitle("Wiederkehrend")
        .onAppear { reload() }
    }

    // MARK: - Subscriptions Tab

    @ViewBuilder
    private var subscriptionsTab: some View {
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

    // MARK: - Calendar Tab

    @ViewBuilder
    private var calendarTab: some View {
        // Hero card: Next 30 days
        calendarHeroCard

        // 12-month overview
        VStack(alignment: .leading, spacing: 12) {
            Text("12-Monats-Übersicht")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(Array(monthlyOverview.enumerated()), id: \.element.id) { i, month in
                    HStack(spacing: 8) {
                        Text(month.label)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .frame(width: 50, alignment: .leading)

                        GeometryReader { geo in
                            let barWidth = month.total > 0
                                ? max(geo.size.width * month.total / maxMonthlyTotal, 4)
                                : 0
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(i == 0 ? Color.orange : WimgTheme.accent)
                                .frame(width: barWidth)
                        }
                        .frame(height: 20)

                        Text(month.total > 0 ? formatAmountShort(month.total) : "–")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .wimgCard(radius: WimgTheme.radiusMedium)
            .padding(.horizontal)
        }

        // Timeline
        VStack(alignment: .leading, spacing: 12) {
            Text("Anstehende Zahlungen")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal)

            if futurePayments.isEmpty {
                VStack(spacing: 8) {
                    Text("📆")
                        .font(.system(size: 48))
                    Text("Keine anstehenden Zahlungen")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                    Text("Erkenne zuerst wiederkehrende Muster im Abonnements-Tab.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        tab = 0
                    } label: {
                        Text("Zu Abonnements")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.heroText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(WimgTheme.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 40)
            } else {
                ForEach(paymentsByMonth, id: \.0) { monthKey, payments in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatMonthHeading(monthKey))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal)

                        ForEach(payments) { payment in
                            paymentCard(payment)
                        }
                    }
                }
            }
        }
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

    // MARK: - Calendar Hero Card

    private var calendarHeroCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 40, y: -40)

            VStack(spacing: 12) {
                Text("Nächste 30 Tage")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(formatAmountShort(next30DaysTotal))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-1)

                let count = next30DaysPayments.count
                Text("\(count) \(count == 1 ? "Zahlung" : "Zahlungen")")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color.orange)
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

    // MARK: - Payment Card

    private func paymentCard(_ payment: FuturePayment) -> some View {
        let cat = WimgCategory.from(payment.category)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cat.color.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: cat.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(cat.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(payment.merchant)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(formatDayLabel(payment.date))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                    Text("·")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary.opacity(0.5))
                    Text(intervalLabels[payment.interval] ?? payment.interval)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            Spacer()

            Text(formatAmountShort(abs(payment.amount)))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
        }
        .padding(16)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func formatDayLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0

        if days == 0 { return "Heute" }
        if days == 1 { return "Morgen" }
        if days <= 7 { return "In \(days) Tagen" }

        let df = DateFormatter()
        df.dateFormat = "d. MMM"
        df.locale = Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE")
        return df.string(from: date)
    }

    private func formatMonthHeading(_ key: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        guard let date = df.date(from: key) else { return key }
        let display = DateFormatter()
        display.dateFormat = "LLLL yyyy"
        display.locale = Locale(identifier: UserDefaults.standard.string(forKey: "wimg_locale") == "en" ? "en_US" : "de_DE")
        return display.string(from: date)
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
