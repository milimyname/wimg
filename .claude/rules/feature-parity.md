# Feature Parity — iOS vs Web vs Android

All platforms are thin shells over the same libwimg C ABI.
FinTS is native-only (iOS + Android, browsers can't do FinTS due to CORS).

## At Parity (iOS + Web)

Dashboard (+ Sparquote savings rate), Transactions, Analysis (+ Net Worth
chart + Spending Heatmap), Debts, Savings Goals, Tax Helper
(Pendlerpauschale, Homeoffice, auto-tagged transactions), Monthly Review,
CSV Import, Auto-categorization, Claude AI, Account Switcher, Account
Management, Sync (enable/link/manual/copy key), Real-time WebSocket, E2E
Encryption, Settings (+ dark mode picker), More page, About page, Data
Export, Monthly Snapshots, Undo toast, Onboarding (4 cards), Empty state
CTAs (all screens), Post-import next steps, Coachmarks (3 first-visit
tooltips), Spending Heatmap tap-to-select (iOS), Renewals Calendar
(12-month forecast, segmented tab on recurring page).

## Android (Phase 8.0a MVP)

Dashboard, Transactions (with category editor), CSV Import, More page.
Built with Kotlin + Jetpack Compose + JNI bridge to libwimg.so.
Material 3 theme matching wimg design tokens. Sideload APK distribution.

### Android Missing (planned for Phase 8.0b+)

- Analysis (net worth chart, spending heatmap, category breakdown)
- Debts, Savings Goals, Recurring, Tax Helper, Monthly Review
- Search + advanced filters
- Sync (WebSocket + HTTP push/pull + E2E encryption)
- FinTS (HTTP callback via OkHttp, TAN screens)
- Settings (theme, language, data export, reset)
- About, Onboarding, Feedback, Coachmarks
- Account switcher + account management
- Undo toast

## iOS Missing

- Settings: sync key mask/reveal toggle (Low priority)
- Settings: sync QR code display (Low priority)
- FAQ deep-links from search (Low priority)
- Custom tax keywords UI (Web uses localStorage)

## Platform-Specific (intentional)

| Feature                              | Platform      | Reason                         |
| ------------------------------------ | ------------- | ------------------------------ |
| FinTS bank connection + TAN medium   | iOS + Android | Browsers can't do FinTS (CORS) |
| FinTS Quick Refresh (PIN storage)    | iOS only      | Android planned (Phase 8.0c)   |
| PWA install + service worker updates | Web only      | Native concept                 |
| OPFS persistence                     | Web only      | Native uses file on disk       |
| MCP server (AI agent access)         | Remote        | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only      | Native uses platform tools     |
| Command Palette                      | Web only      | Native uses platform navigation|
| Transaction search + advanced filter | Web + iOS     | Android planned (Phase 8.0b)   |
| In-app Changelog                     | Web only      | Native uses store notes        |
| Auto-learn rules                     | All           | Runs in libwimg (Zig)          |
| Custom tax keywords                  | Web only      | localStorage, not synced       |
