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
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(WimgTheme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WimgTheme.bg)
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
    @State private var selectedAccount: String?
    @State private var accounts: [Account] = []

    var body: some View {
        TabView {
            DashboardView(selectedAccount: $selectedAccount, accounts: $accounts)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            TransactionsView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Umsätze", systemImage: "list.bullet")
                }

            AnalysisView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Analyse", systemImage: "chart.bar")
                }

            MoreView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Mehr", systemImage: "square.grid.2x2")
                }
        }
        .tint(WimgTheme.text)
        .onAppear {
            accounts = LibWimg.getAccounts()
            // Connect real-time sync WebSocket + initial pull
            Task {
                let sync = SyncService.shared
                if await sync.isEnabled {
                    await sync.connectWebSocket()
                    _ = try? await sync.pull()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            accounts = LibWimg.getAccounts()
        }
    }
}
