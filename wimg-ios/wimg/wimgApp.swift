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

        // Log main thread hangs > 50ms
        #if DEBUG
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, activity in
            struct S { static var ts: CFAbsoluteTime = 0 }
            if activity.rawValue == CFRunLoopActivity.afterWaiting.rawValue {
                S.ts = CFAbsoluteTimeGetCurrent()
            } else if S.ts > 0 {
                let ms = (CFAbsoluteTimeGetCurrent() - S.ts) * 1000
                if ms > 50 { print("⚠️ Main thread blocked \(Int(ms))ms") }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        #endif

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
    @AppStorage("wimg_locale") private var currentLocale = "de"
    private var themeManager = ThemeManager.shared

    private var appLocale: Locale {
        Locale(identifier: currentLocale == "en" ? "en" : "de")
    }

    var body: some View {
        TabView {
            SearchView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Suche", systemImage: "magnifyingglass")
                }

            DashboardView(selectedAccount: $selectedAccount, accounts: $accounts)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            TransactionsView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Umsätze", systemImage: "list.bullet")
                }

            MoreView(selectedAccount: $selectedAccount)
                .tabItem {
                    Label("Mehr", systemImage: "square.grid.2x2")
                }
        }
        .tint(WimgTheme.text)
        .environment(\.locale, appLocale)
        .preferredColorScheme(themeManager.mode.colorScheme)
        .onAppear {
            Task.detached {
                let accs = LibWimg.getAccounts()
                // Auto-snapshot: take monthly snapshot if we haven't this month
                let now = Date()
                let cal = Calendar.current
                let currentMonth = String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
                let lastSnapshot = UserDefaults.standard.string(forKey: "wimg_last_snapshot_month")
                if lastSnapshot != currentMonth {
                    try? LibWimg.takeSnapshot(year: cal.component(.year, from: now), month: cal.component(.month, from: now))
                    UserDefaults.standard.set(currentMonth, forKey: "wimg_last_snapshot_month")
                }
                await MainActor.run { accounts = accs }
            }
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
            Task.detached {
                let accs = LibWimg.getAccounts()
                await MainActor.run { accounts = accs }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) {
            OnboardingView()
        }
    }
}
