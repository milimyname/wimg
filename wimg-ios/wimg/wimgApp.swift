import SwiftUI

@main
struct wimgApp: App {
    @State private var initError: String?

    var body: some Scene {
        WindowGroup {
            if let error = initError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Initialisierung fehlgeschlagen")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ContentView()
            }
        }
    }

    init() {
        do {
            try LibWimg.initialize()
        } catch {
            _initError = State(initialValue: error.localizedDescription)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Übersicht", systemImage: "chart.pie")
                }

            TransactionsView()
                .tabItem {
                    Label("Umsätze", systemImage: "list.bullet")
                }

            AnalysisView()
                .tabItem {
                    Label("Analyse", systemImage: "chart.bar")
                }

            ReviewView()
                .tabItem {
                    Label("Rückblick", systemImage: "calendar")
                }

            DebtsView()
                .tabItem {
                    Label("Schulden", systemImage: "creditcard")
                }

            ImportView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
        }
        .tint(.blue)
    }
}
