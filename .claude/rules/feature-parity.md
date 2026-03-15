# Feature Parity — iOS vs Web

Both platforms are thin shells over the same libwimg C ABI.
FinTS is intentionally iOS-only (browsers can't do FinTS due to CORS).

## At Parity

Dashboard (+ Sparquote savings rate), Transactions, Analysis (+ Net Worth
chart + Spending Heatmap), Debts, Savings Goals, Tax Helper
(Pendlerpauschale, Homeoffice, auto-tagged transactions), Monthly Review,
CSV Import, Auto-categorization, Claude AI, Account Switcher, Account
Management, Sync (enable/link/manual/copy key), Real-time WebSocket, E2E
Encryption, Settings (+ dark mode picker), More page, About page, Data
Export, Monthly Snapshots, Undo toast, Onboarding (4 cards).

## iOS Missing

- Settings: sync key mask/reveal toggle (Low priority)
- Settings: sync QR code display (Low priority)
- FAQ deep-links from search (Low priority)
- Custom tax keywords UI (Web uses localStorage)

## Platform-Specific (intentional)

| Feature                              | Platform | Reason                         |
| ------------------------------------ | -------- | ------------------------------ |
| FinTS bank connection                | iOS only | Browsers can't do FinTS (CORS) |
| PWA install + service worker updates | Web only | Native concept                 |
| OPFS persistence                     | Web only | iOS uses file on disk          |
| MCP server (AI agent access)         | Remote   | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only | iOS uses Xcode Instruments     |
| Command Palette                      | Web only | iOS uses native navigation     |
| Transaction search + advanced filter | Both     | Web: Command Palette, iOS: .searchable + filter sheet |
| In-app Changelog                     | Web only | iOS uses App Store notes       |
| Auto-learn rules                     | Both     | Runs in libwimg (Zig)          |
| Custom tax keywords                  | Web only | localStorage, not synced       |
