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
        // Migrate credentials from UserDefaults to Keychain (one-time on update)
        SyncService.shared.migrateIfNeeded()
        ClaudeAPI.migrateIfNeeded()

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
    @AppStorage("wimg_onboarding_completed") private var onboardingCompleted = false

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
            // Auto-snapshot: take monthly snapshot if we haven't this month
            let now = Date()
            let cal = Calendar.current
            let currentMonth = String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
            let lastSnapshot = UserDefaults.standard.string(forKey: "wimg_last_snapshot_month")
            if lastSnapshot != currentMonth {
                try? LibWimg.takeSnapshot(year: cal.component(.year, from: now), month: cal.component(.month, from: now))
                UserDefaults.standard.set(currentMonth, forKey: "wimg_last_snapshot_month")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            accounts = LibWimg.getAccounts()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) {
            OnboardingView()
        }
    }
}
