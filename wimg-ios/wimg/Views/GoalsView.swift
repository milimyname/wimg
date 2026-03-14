import SwiftUI

struct GoalsView: View {
    @State private var goals: [Goal] = []
    @State private var showAddSheet = false
    @State private var contributeGoalId: String?
    @State private var contributeAmount = ""
    @State private var undoMessage: String?

    private var totalTarget: Double {
        goals.reduce(0) { $0 + $1.target }
    }

    private var totalSaved: Double {
        goals.reduce(0) { $0 + $1.current }
    }

    private var overallProgress: Double {
        totalTarget > 0 ? totalSaved / totalTarget : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !goals.isEmpty {
                        heroCard
                    }

                    // Section header
                    HStack {
                        Text("Deine Sparziele")
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.text)
                        Spacer()

                        if !goals.isEmpty {
                            Text("\(goals.count) \(goals.count == 1 ? "Ziel" : "Ziele")")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(WimgTheme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)

                    if goals.isEmpty && !showAddSheet {
                        VStack(spacing: 8) {
                            Text("\u{2B50}")
                                .font(.system(size: 48))
                            Text("Keine Sparziele")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.text)
                            Text("Setze dir Sparziele und verfolge deinen Fortschritt")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(goals) { goal in
                            goalCard(goal)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Sparziele")
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
                AddGoalSheet {
                    reload()
                    showUndo("Sparziel hinzugefügt")
                }
            }
            .alert("Einzahlen", isPresented: .init(
                get: { contributeGoalId != nil },
                set: { if !$0 { contributeGoalId = nil; contributeAmount = "" } }
            )) {
                TextField("Betrag (\u{20AC})", text: $contributeAmount)
                    .keyboardType(.decimalPad)
                Button("Sparen") {
                    if let id = contributeGoalId,
                       let amount = Double(contributeAmount.replacingOccurrences(of: ",", with: ".")) {
                        let cents = Int(amount * 100)
                        try? LibWimg.contributeGoal(id: id, amountCents: cents)
                        contributeGoalId = nil
                        contributeAmount = ""
                        reload()
                        showUndo("Einzahlung verbucht")
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    contributeGoalId = nil
                    contributeAmount = ""
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
                Text("Gesamtfortschritt")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(formatAmountShort(totalSaved))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(WimgTheme.text)
                    .tracking(-1)

                Text("von \(formatAmountShort(totalTarget)) gespart")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(WimgTheme.text.opacity(0.7))

                VStack(spacing: 8) {
                    HStack {
                        Text("Fortschritt")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text.opacity(0.6))
                        Spacer()
                        Text(String(format: "%.0f%%", overallProgress * 100))
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                            .foregroundStyle(WimgTheme.text)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.4))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(WimgTheme.text)
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

    // MARK: - Goal Card

    private func goalCard(_ goal: Goal) -> some View {
        let pct = goal.progress
        let isComplete = goal.isComplete

        return VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Text(goal.icon)
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                        if let deadlineDate = goal.deadlineDate {
                            Text("Bis \(deadlineDate, format: .dateTime.day().month(.abbreviated).year())")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(WimgTheme.textSecondary)
                        }
                    }
                }
                Spacer()

                if isComplete {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Erreicht")
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                } else {
                    Button {
                        contributeGoalId = goal.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Einzahlen")
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
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
                    Text("\(formatAmountShort(goal.current)) von \(formatAmountShort(goal.target))")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isComplete ? Color.green : WimgTheme.text)
                            .frame(width: geo.size.width * pct, height: 10)
                    }
                }
                .frame(height: 10)
            }

            // Actions
            HStack {
                Spacer()
                Menu {
                    Button("Einzahlen") {
                        contributeGoalId = goal.id
                    }
                    Button("Löschen", role: .destructive) {
                        try? LibWimg.deleteGoal(id: goal.id)
                        reload()
                        showUndo("Sparziel gelöscht")
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
        goals = LibWimg.getGoals()
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

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "🎯"
    @State private var target = ""
    @State private var deadline = ""
    @State private var showDatePicker = false
    @State private var selectedDate = Date()

    private let icons = ["🎯", "🏠", "✈️", "🚗", "💻", "🎓", "💍", "🏖️", "🎸", "📱", "🏋️", "🎮"]

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
                        TextField("z.B. Urlaub 2027", text: $name)
                            .font(.system(.body, design: .rounded))
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(icons, id: \.self) { ic in
                                Button {
                                    icon = ic
                                } label: {
                                    Text(ic)
                                        .font(.system(size: 24))
                                        .frame(width: 44, height: 44)
                                        .background(icon == ic ? WimgTheme.accent : Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(icon == ic ? WimgTheme.text : .clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zielbetrag")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        TextField("z.B. 5000", text: $target)
                            .font(.system(.body, design: .rounded))
                            .keyboardType(.decimalPad)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Deadline (optional)")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Button {
                        save()
                    } label: {
                        Text("Hinzufügen")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(WimgTheme.accent)
                            .foregroundStyle(WimgTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusSmall, style: .continuous))
                    }
                    .disabled(name.isEmpty || target.isEmpty)
                    .opacity(name.isEmpty || target.isEmpty ? 0.5 : 1)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(WimgTheme.bg)
            .navigationTitle("Neues Sparziel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let targetVal = Double(target.replacingOccurrences(of: ",", with: ".")),
              targetVal > 0 else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let deadlineStr = fmt.string(from: selectedDate)

        try? LibWimg.addGoal(name: name, icon: icon, target: targetVal, deadline: deadlineStr)
        onDismiss()
        dismiss()
    }
}
