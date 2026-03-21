import SwiftUI

struct DebtsView: View {
    @State private var debts: [Debt] = []
    @State private var showAddSheet = false
    @State private var payDebtId: String?
    @State private var payAmount = ""
    @State private var undoMessage: String?

    private var totalDebt: Double {
        debts.reduce(0) { $0 + $1.total }
    }

    private var totalPaid: Double {
        debts.reduce(0) { $0 + $1.paid }
    }

    private var overallProgress: Double {
        totalDebt > 0 ? totalPaid / totalDebt : 0
    }

    private var activeCount: Int {
        debts.filter { $0.total - $0.paid > 0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Overall progress hero
                    if !debts.isEmpty {
                        heroCard
                    }

                    // Section header
                    HStack {
                        Text("Deine Schulden")
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.text)
                        Spacer()

                        if !debts.isEmpty {
                            Text("\(activeCount) Aktiv")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.heroText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(WimgTheme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)

                    if debts.isEmpty && !showAddSheet {
                        VStack(spacing: 8) {
                            Text("\u{1F4B3}")
                                .font(.system(size: 48))
                            Text("Keine Schulden")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text("Füge Schulden hinzu um den Fortschritt zu tracken")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(WimgTheme.textSecondary)

                            Button {
                                showAddSheet = true
                            } label: {
                                Text("Schuld hinzufügen")
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
                    } else {
                        ForEach(debts) { debt in
                            debtCard(debt)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Schulden")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.bold)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDebtSheet {
                    reload()
                    showUndo("Schuld hinzugefügt")
                }
            }
            .alert("Zahlung eintragen", isPresented: .init(
                get: { payDebtId != nil },
                set: { if !$0 { payDebtId = nil; payAmount = "" } }
            )) {
                TextField("Betrag (\u{20AC})", text: $payAmount)
                    .keyboardType(.decimalPad)
                Button("Bezahlen") {
                    if let id = payDebtId,
                       let amount = Double(payAmount.replacingOccurrences(of: ",", with: ".")) {
                        let cents = Int(amount * 100)
                        try? LibWimg.markDebtPaid(id: id, amountCents: cents)
                        payDebtId = nil
                        payAmount = ""
                        reload()
                        showUndo("Zahlung eingetragen")
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    payDebtId = nil
                    payAmount = ""
                }
            }
            .onAppear { reload() }
            .overlay(alignment: .bottom) {
                if let msg = undoMessage {
                    UndoToast(message: msg) {
                        performUndo()
                    }
                    .padding(.bottom, 8)
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
                Text("Verbleibende Schulden")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.heroText.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(formatAmountShort(totalDebt - totalPaid))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(WimgTheme.heroText)
                    .tracking(-1)

                VStack(spacing: 8) {
                    HStack {
                        Text("Fortschritt")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.heroText.opacity(0.6))
                        Spacer()
                        Text(String(format: "%.0f%%", overallProgress * 100))
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.heroText)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.4))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(WimgTheme.heroText)
                                .frame(width: geo.size.width * overallProgress, height: 12)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .wimgHero()
        .padding(.horizontal)
    }

    // MARK: - Debt Card

    private func debtCard(_ debt: Debt) -> some View {
        let remaining = debt.total - debt.paid
        let pct = debt.total > 0 ? debt.paid / debt.total : 0
        let isPaidOff = remaining <= 0

        return VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                    if debt.monthly > 0 {
                        Text("Monatlich: \(formatAmountShort(debt.monthly))")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                }
                Spacer()

                if isPaidOff {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Abbezahlt")
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                } else {
                    Button {
                        payDebtId = debt.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text("Bezahlt")
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.heroText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WimgTheme.accent)
                        .clipShape(Capsule())
                    }
                }
            }

            // Progress
            VStack(spacing: 6) {
                HStack {
                    Text("\(formatAmountShort(remaining)) übrig")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text(String(format: "%.0f%% erledigt", pct * 100))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isPaidOff ? Color.green : WimgTheme.text)
                            .frame(width: geo.size.width * pct, height: 10)
                    }
                }
                .frame(height: 10)
            }

            // Delete action
            HStack {
                Spacer()
                Menu {
                    Button("Zahlung eintragen") {
                        payDebtId = debt.id
                    }
                    Button("Löschen", role: .destructive) {
                        try? LibWimg.deleteDebt(id: debt.id)
                        reload()
                        showUndo("Schuld gelöscht")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(20)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    private func reload() {
        debts = LibWimg.getDebts()
    }

    private func showUndo(_ message: String) {
        withAnimation { undoMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if undoMessage == message { undoMessage = nil } }
        }
    }

    private func performUndo() {
        if LibWimg.undo() != nil {
            reload()
            NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
        }
        withAnimation { undoMessage = nil }
    }
}

// MARK: - Add Debt Sheet

struct AddDebtSheet: View {
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var total = ""
    @State private var monthly = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        TextField("z.B. FOM, Klarna", text: $name)
                            .font(.system(.body, design: .rounded))
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gesamtbetrag")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        TextField("z.B. 1234,56", text: $total)
                            .font(.system(.body, design: .rounded))
                            .keyboardType(.decimalPad)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Monatliche Rate (optional)")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        TextField("z.B. 50,00", text: $monthly)
                            .font(.system(.body, design: .rounded))
                            .keyboardType(.decimalPad)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        save()
                    } label: {
                        Text("Hinzufügen")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(WimgTheme.accent)
                            .foregroundStyle(WimgTheme.heroText)
                            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusSmall, style: .continuous))
                    }
                    .disabled(name.isEmpty || total.isEmpty)
                    .opacity(name.isEmpty || total.isEmpty ? 0.5 : 1)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Schuld hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let totalVal = Double(total.replacingOccurrences(of: ",", with: ".")),
              totalVal > 0 else { return }
        let monthlyVal = Double(monthly.replacingOccurrences(of: ",", with: ".")) ?? 0

        try? LibWimg.addDebt(name: name, total: totalVal, monthly: monthlyVal)
        onDismiss()
        dismiss()
    }
}
