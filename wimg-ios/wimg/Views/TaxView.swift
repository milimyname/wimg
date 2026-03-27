import SwiftUI

struct TaxView: View {
    @State private var year: Int
    @State private var km: Double = 0
    @State private var workDays: Double = 220
    @State private var homeofficeDays: Double = 0

    private var transactions: [Transaction] {
        (try? LibWimg.getTransactions()) ?? []
    }

    init() {
        _year = State(initialValue: Calendar.current.component(.year, from: Date()))
    }

    // Tax categories with keywords
    private static let taxCategories: [(id: String, label: String, icon: String, color: Color, keywords: [String])] = [
        ("arbeitsmittel", "Arbeitsmittel", "💻", .blue, ["apple", "mediamarkt", "saturn", "büro", "computer", "laptop", "monitor", "tastatur", "logitech", "dell", "lenovo", "thinkpad", "macbook", "ipad"]),
        ("fortbildung", "Fortbildung", "📚", .green, ["udemy", "coursera", "kurs", "seminar", "weiterbildung", "fortbildung", "schulung", "linkedin learning", "pluralsight"]),
        ("fachliteratur", "Fachliteratur", "📖", .purple, ["fachbuch", "o'reilly", "manning", "apress", "springer", "thalia fach"]),
        ("fahrtkosten", "Fahrtkosten", "🚆", .orange, ["deutsche bahn", "db fernverkehr", "db regio", "flixbus", "flixtrain", "bvg", "mvv", "hvv", "rheinbahn", "kvb"]),
        ("versicherung", "Versicherungen", "🛡️", .pink, ["berufshaftpflicht", "rechtsschutz", "berufsunfähigkeit"]),
    ]

    private var taggedTransactions: [(tx: Transaction, category: String, label: String, icon: String, color: Color)] {
        let yearStr = String(year)
        var results: [(tx: Transaction, category: String, label: String, icon: String, color: Color)] = []

        for tx in transactions {
            guard tx.date.hasPrefix(yearStr), tx.amount < 0 else { continue }
            let lower = tx.description.lowercased()
            for cat in Self.taxCategories {
                if cat.keywords.contains(where: { lower.contains($0) }) {
                    results.append((tx: tx, category: cat.id, label: cat.label, icon: cat.icon, color: cat.color))
                    break
                }
            }
        }

        return results.sorted { $0.tx.date > $1.tx.date }
    }

    private var pendlerpauschale: Double {
        guard km > 0, workDays > 0 else { return 0 }
        let first20 = min(km, 20) * 0.30
        let beyond20 = max(km - 20, 0) * 0.38
        return (first20 + beyond20) * workDays
    }

    private var homeofficePauschale: Double {
        min(max(homeofficeDays, 0), 210) * 6
    }

    private var werbungskosten: Double {
        taggedTransactions.reduce(0) { $0 + abs($1.tx.amount) }
    }

    private var gesamtabzug: Double {
        werbungskosten + pendlerpauschale + homeofficePauschale
    }

    private var availableYears: [Int] {
        let years = Set(transactions.compactMap { Int($0.date.prefix(4)) })
        return years.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if transactions.isEmpty {
                        VStack(spacing: 8) {
                            Text("🧾")
                                .font(.system(size: 48))
                            Text("Keine Transaktionen")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text("Importiere Bankdaten um steuerrelevante Ausgaben zu finden")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(WimgTheme.textSecondary)
                                .multilineTextAlignment(.center)

                            NavigationLink(destination: ImportView()) {
                                Text("CSV importieren")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.bg)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(WimgTheme.text)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 40)
                        .padding(.horizontal)
                    } else {
                    // Hero card
                    heroCard

                    // Summary grid
                    summaryGrid

                    // Pendlerpauschale
                    pendlerCard

                    // Homeoffice
                    homeofficeCard

                    // Tagged transactions
                    if !taggedTransactions.isEmpty {
                        transactionsSection
                    }
                    } // end else transactions.isEmpty
                }
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Steuern")
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 100, height: 100)
                .blur(radius: 30)
                .offset(x: 30, y: -30)

            VStack(spacing: 12) {
                HStack {
                    Text("Absetzbare Ausgaben")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.heroText.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    Picker("Jahr", selection: $year) {
                        ForEach(availableYears.isEmpty ? [year] : availableYears, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tint(WimgTheme.heroText)
                }

                Text(formatAmountShort(gesamtabzug))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(WimgTheme.heroText)
                    .tracking(-1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Geschätztes Steuerjahr \(String(year))")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.heroText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .wimgHero()
        .padding(.horizontal)
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        HStack(spacing: 12) {
            statBox("Werbung", value: werbungskosten)
            statBox("Pauschalen", value: pendlerpauschale + homeofficePauschale)
            statBox("Gesamt", value: gesamtabzug)
        }
        .padding(.horizontal)
    }

    private func statBox(_ label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(WimgTheme.textSecondary)
                .textCase(.uppercase)
            Text(formatAmountShort(value))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .wimgCard()
    }

    // MARK: - Pendlerpauschale

    private var pendlerCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.blue)
                    }
                Text("Pendlerpauschale")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("km")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                    TextField("0", value: $km, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tage")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                    TextField("220", value: $workDays, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if pendlerpauschale > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pendlerFormula)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .italic()
                        Text(formatAmountShort(pendlerpauschale))
                            .font(.system(.title2, design: .rounded, weight: .black))
                    }
                    Spacer()
                    Text("Aktiv")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    private var pendlerFormula: String {
        if km <= 20 {
            return "\(Int(km))km × 0,30€ × \(Int(workDays)) Tage"
        }
        return "20km × 0,30€ + \(Int(km - 20))km × 0,38€ × \(Int(workDays)) Tage"
    }

    // MARK: - Homeoffice

    private var homeofficeCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "house")
                            .foregroundStyle(.purple)
                    }
                Text("Homeoffice")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Homeoffice-Tage")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .textCase(.uppercase)
                TextField("0", value: $homeofficeDays, format: .number)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Text("6 €/Tag (max. 210 Tage)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.textSecondary)
                Spacer()
                Text(formatAmountShort(homeofficePauschale))
                    .font(.system(.headline, design: .rounded, weight: .black))
            }
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Erkannte Ausgaben")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(WimgTheme.text)
                Spacer()
                Text("\(taggedTransactions.count)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
            }
            .padding(.horizontal)

            ForEach(taggedTransactions, id: \.tx.id) { item in
                HStack(spacing: 12) {
                    Text(item.icon)
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                        .background(item.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.tx.description)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                            .lineLimit(1)
                        Text(item.label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(item.color)
                            .textCase(.uppercase)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.color.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(formatAmountShort(abs(item.tx.amount)))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                }
                .padding(16)
                .wimgCard(radius: WimgTheme.radiusMedium)
                .padding(.horizontal)
            }
        }
    }
}
