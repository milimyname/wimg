# Feature Parity — iOS vs Web vs Android

All platforms are thin shells over the same libwimg C ABI.
FinTS is native-only (iOS + Android, browsers can't do FinTS due to CORS).

## At Parity (iOS + Web + Android)

Dashboard (+ Sparquote savings rate), Transactions (+ advanced filter sheet),
Analysis (+ Net Worth + Spending Heatmap), Monthly Review, CSV Import,
Auto-categorization, Recurring (grouped by interval), Search (+ quick actions:
nav, categorize, export, undo/redo), Settings (theme/language picker, feature
toggles, sync, data export/reset), About (FAQ, privacy, GitHub), More page,
Data Export, Monthly Snapshots, Onboarding (4 cards), FinTS (bank search,
credentials, TAN handling, statement fetch), Sync (WebSocket + HTTP push/pull
+ E2E encryption), Feedback (POST to wimg-sync), Demo data.

Tax, Goals, and Debts UI removed 2026-05-14 — Zig C ABI + SQLite tables
remain in libwimg for cheap resurrection but no platform renders them.

## Android Minor Gaps

- Spending Heatmap tap-to-select (iOS has inline amount label on tap)
- (resolved 2026-05-15) i18n now uniform across all 3 platforms via macro/Composable `L()` from one `en.ts` source.

## iOS Missing

- Settings: sync key mask/reveal toggle (Low priority)
- Settings: sync QR code display (Low priority)
- FAQ deep-links from search (Low priority)

## Platform-Specific (intentional)

| Feature                              | Platform      | Reason                         |
| ------------------------------------ | ------------- | ------------------------------ |
| FinTS bank connection + TAN medium   | iOS + Android | Browsers can't do FinTS (CORS) |
| FinTS Quick Refresh (PIN storage)    | iOS + Android | Keychain (iOS), SharedPrefs (Android) |
| PWA install + service worker updates | Web only      | Native concept                 |
| OPFS persistence                     | Web only      | Native uses file on disk       |
| MCP server (AI agent access)         | Remote        | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only      | Native uses platform tools     |
| Command Palette                      | Web only      | Native uses platform navigation|
| In-app Changelog                     | Web only      | Native uses store notes / update checker |
| Auto-learn rules                     | All           | Runs in libwimg (Zig)          |
| Update checker (GitHub Releases)     | Android only  | iOS uses TestFlight, Web uses SW |
