import SwiftUI

struct MoreView: View {
    @Binding var selectedAccount: String?

    private let allItems: [(title: String, icon: String, color: Color, destination: Destination)] = [
        ("Schulden", "creditcard", .pink, .debts),
        ("Wiederkehrend", "arrow.triangle.2.circlepath", .green, .recurring),
        ("Sparziele", "target", .yellow, .goals),
        ("Steuern", "doc.text", .orange, .tax),
        ("Import", "square.and.arrow.down", .blue, .import_),
        ("Bankkonto", "building.columns", .teal, .fints),
        ("Rückblick", "calendar", .purple, .review),
        ("Einstellungen", "gearshape", .orange, .settings),
        ("Über wimg", "info.circle", .gray, .about),
    ]

    private var items: [(title: String, icon: String, color: Color, destination: Destination)] {
        allItems.filter { item in
            switch item.destination {
            case .debts: return FeatureFlags.shared.isEnabled("debts")
            case .recurring: return FeatureFlags.shared.isEnabled("recurring")
            case .review: return FeatureFlags.shared.isEnabled("review")
            case .goals: return FeatureFlags.shared.isEnabled("goals")
            case .tax: return FeatureFlags.shared.isEnabled("tax")
            default: return true
            }
        }
    }

    enum Destination {
        case debts, recurring, goals, tax, import_, fints, review, settings, about
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Mehr")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 16) {
                        ForEach(items, id: \.title) { item in
                            NavigationLink {
                                destinationView(for: item.destination)
                            } label: {
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(item.color.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                        .overlay {
                                            Image(systemName: item.icon)
                                                .font(.title3)
                                                .foregroundStyle(item.color)
                                        }

                                    Text(item.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(WimgTheme.text)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .wimgCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(WimgTheme.bg)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: Destination) -> some View {
        switch destination {
        case .debts:
            DebtsView()
        case .recurring:
            RecurringView()
        case .goals:
            GoalsView()
        case .tax:
            TaxView()
        case .import_:
            ImportView()
        case .fints:
            FinTSView()
        case .review:
            ReviewView(selectedAccount: $selectedAccount)
        case .settings:
            SettingsView()
        case .about:
            AboutView()
        }
    }
}
