import SwiftUI

struct DebtsView: View {
    @State private var debts: [Debt] = []
    @State private var showAddSheet = false
    @State private var payDebtId: String?
    @State private var payAmount = ""

    private var totalDebt: Double {
        debts.reduce(0) { $0 + $1.total }
    }

    private var totalPaid: Double {
        debts.reduce(0) { $0 + $1.paid }
    }

    private var overallProgress: Double {
        totalDebt > 0 ? totalPaid / totalDebt : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Overall progress
                    VStack(spacing: 8) {
                        Text("Schulden gesamt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formatAmountShort(totalDebt - totalPaid))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        ProgressView(value: overallProgress)
                            .tint(.blue)
                            .padding(.horizontal, 40)
                        Text(String(format: "%.0f%% abbezahlt", overallProgress * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    if debts.isEmpty {
                        ContentUnavailableView(
                            "Keine Schulden",
                            systemImage: "checkmark.circle",
                            description: Text("Tippe + um eine Schuld hinzuzufügen.")
                        )
                    } else {
                        ForEach(debts) { debt in
                            debtCard(debt)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schulden")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDebtSheet {
                    reload()
                }
            }
            .alert("Zahlung eintragen", isPresented: .init(
                get: { payDebtId != nil },
                set: { if !$0 { payDebtId = nil; payAmount = "" } }
            )) {
                TextField("Betrag (€)", text: $payAmount)
                    .keyboardType(.decimalPad)
                Button("Bezahlen") {
                    if let id = payDebtId,
                       let amount = Double(payAmount.replacingOccurrences(of: ",", with: ".")) {
                        let cents = Int(amount * 100)
                        try? LibWimg.markDebtPaid(id: id, amountCents: cents)
                        payDebtId = nil
                        payAmount = ""
                        reload()
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    payDebtId = nil
                    payAmount = ""
                }
            }
            .onAppear { reload() }
        }
    }

    private func debtCard(_ debt: Debt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(debt.name)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Zahlung eintragen") {
                        payDebtId = debt.id
                    }
                    Button("Löschen", role: .destructive) {
                        try? LibWimg.deleteDebt(id: debt.id)
                        reload()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: debt.progress)
                .tint(debt.isPaidOff ? .green : .blue)

            HStack {
                Text(formatAmountShort(debt.paid))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatAmountShort(debt.total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if debt.monthly > 0 {
                Text("Monatlich: \(formatAmountShort(debt.monthly))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func reload() {
        debts = LibWimg.getDebts()
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
            Form {
                Section("Details") {
                    TextField("Name (z.B. FOM, Klarna)", text: $name)
                    TextField("Gesamtbetrag (€)", text: $total)
                        .keyboardType(.decimalPad)
                    TextField("Monatliche Rate (€, optional)", text: $monthly)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Schuld hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(name.isEmpty || total.isEmpty)
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
