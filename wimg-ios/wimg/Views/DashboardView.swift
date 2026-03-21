import SwiftUI
import Charts

struct DashboardView: View {
    @Binding var selectedAccount: String?
    @Binding var accounts: [Account]
    @State private var year: Int
    @State private var month: Int
    @State private var summary: MonthlySummary?
    @State private var recentTransactions: [Transaction] = []
    @State private var hasAnyData = false
    @State private var loadingDemo = false

    init(selectedAccount: Binding<String?>, accounts: Binding<[Account]>) {
        _selectedAccount = selectedAccount
        _accounts = accounts
        let cal = Calendar.current
        let now = Date()
        _year = State(initialValue: cal.component(.year, from: now))
        _month = State(initialValue: cal.component(.month, from: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !hasAnyData {
                    // Welcome empty state
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        ZStack {
                            Circle()
                                .fill(WimgTheme.accent.opacity(0.2))
                                .frame(width: 112, height: 112)
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(WimgTheme.text.opacity(0.6))
                        }

                        VStack(spacing: 8) {
                            Text("Willkommen bei wimg")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text("Importiere eine CSV-Datei oder lade Beispieldaten, um loszulegen.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(WimgTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        VStack(spacing: 12) {
                            NavigationLink(destination: ImportView()) {
                                Text("CSV importieren")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.heroText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(WimgTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            Button {
                                loadingDemo = true
                                DemoDataService.loadDemoData()
                                loadingDemo = false
                                reload()
                            } label: {
                                Text(loadingDemo ? "Lade..." : "Beispieldaten laden")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .disabled(loadingDemo)
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                VStack(spacing: 20) {
                    MonthPicker(year: $year, month: $month)
                        .padding(.top, 8)

                    // Hero: Verfügbares Einkommen
                    availableCard

                    // Income / Expenses row
                    HStack(spacing: 12) {
                        summaryCard(
                            title: "Einnahmen",
                            amount: summary?.income ?? 0,
                            icon: "arrow.down.circle.fill",
                            iconColor: .green
                        )
                        summaryCard(
                            title: "Ausgaben",
                            amount: summary?.expenses ?? 0,
                            icon: "arrow.up.circle.fill",
                            iconColor: .red
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
                .padding(.bottom, 24)
                }
            }
            .background(WimgTheme.bg)
            .navigationTitle("Übersicht")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountPicker(selectedAccount: $selectedAccount, accounts: accounts) {
                        accounts = LibWimg.getAccounts()
                    }
                }
            }
            .onChange(of: year) { reload() }
            .onChange(of: month) { reload() }
            .onChange(of: selectedAccount) { reload() }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
                reload()
            }
        }
    }

    // MARK: - Cards

    // expenses comes as positive from Zig (negated for display)
    private var sparquote: Int {
        let income = summary?.income ?? 0
        guard income > 0 else { return 0 }
        return Int(((income - (summary?.expenses ?? 0)) / income) * 100)
    }

    private var availableCard: some View {
        VStack(spacing: 12) {
            // Hero: Verfügbar
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                    .offset(x: 40, y: -40)

                VStack(spacing: 6) {
                    Text("Verfügbar")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.heroText.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(1)

                    Text(formatAmountShort(summary?.available ?? 0))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(WimgTheme.heroText)
                        .tracking(-1)

                    Text("\(summary?.tx_count ?? 0) Transaktionen")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.heroText.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
            .wimgHero()
            .padding(.horizontal)

            // Sparquote card
            if (summary?.income ?? 0) > 0 {
                HStack(spacing: 16) {
                    // Ring
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 4)
                            .frame(width: 52, height: 52)
                        Circle()
                            .trim(from: 0, to: min(max(Double(sparquote), 0), 100) / 100)
                            .stroke(
                                sparquote >= 20 ? Color.green : sparquote >= 0 ? Color.orange : Color.red,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                        Text("\(sparquote)%")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(WimgTheme.text)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sparquote")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        Text("Du sparst \(formatAmountShort(summary?.available ?? 0)) von \(formatAmountShort(summary?.income ?? 0))")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }

                    Spacer()
                }
                .padding(16)
                .wimgCard(radius: WimgTheme.radiusMedium)
                .padding(.horizontal)
            }
        }
    }

    private func summaryCard(title: String, amount: Double, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Text(formatAmountShort(amount))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .wimgCard(radius: WimgTheme.radiusMedium)
    }

    // MARK: - Donut

    private func donutSection(_ categories: [CategoryBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ausgaben nach Kategorie")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal, 20)
                .coachmark(key: "dashboard_donut", text: "Gehe zur Analyse für Details")

            ZStack {
                Chart(categories) { cat in
                    SectorMark(
                        angle: .value("Betrag", abs(cat.amount)),
                        innerRadius: .ratio(0.58),
                        angularInset: 1
                    )
                    .foregroundStyle(WimgCategory.from(cat.id).color)
                }
                .chartLegend(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

                // Center total overlay
                VStack(spacing: 2) {
                    Text("Total")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(formatAmountShort(categories.reduce(0) { $0 + $1.amount }))
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(WimgTheme.text)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)

            // Legend
            VStack(spacing: 0) {
                ForEach(categories.prefix(5)) { cat in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(WimgCategory.from(cat.id).color)
                            .frame(width: 10, height: 10)
                        Text(cat.name)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(WimgTheme.text)
                        Spacer()
                        Text(formatAmountShort(cat.amount))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    if cat.id != categories.prefix(5).last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Recent Transactions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Letzte Umsätze")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.text)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(recentTransactions.prefix(5)) { tx in
                    TransactionCard(transaction: tx)

                    if tx.id != recentTransactions.prefix(5).last?.id {
                        Divider().padding(.leading, 78)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .wimgCard(radius: WimgTheme.radiusLarge)
        .padding(.horizontal)
    }

    // MARK: - Data

    private func reload() {
        let allTx = (try? LibWimg.getTransactions()) ?? []
        hasAnyData = !allTx.isEmpty
        summary = LibWimg.getSummaryFiltered(year: year, month: month, account: selectedAccount)
        let all = (try? LibWimg.getTransactionsFiltered(account: selectedAccount)) ?? []
        let monthStr = String(format: "%04d-%02d", year, month)
        recentTransactions = all
            .filter { $0.date.hasPrefix(monthStr) }
            .sorted { $0.date > $1.date }
    }
}
