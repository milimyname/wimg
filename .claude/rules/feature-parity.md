# Feature Parity — iOS vs Web vs Android

All platforms are thin shells over the same libwimg C ABI.
FinTS is native-only (iOS + Android, browsers can't do FinTS due to CORS).

## At Parity (iOS + Web + Android)

Dashboard (+ Sparquote savings rate), Transactions (+ advanced filter sheet),
Analysis (+ Net Worth + Spending Heatmap), Debts, Savings Goals, Tax Helper
(Pendlerpauschale, Homeoffice), Monthly Review, CSV Import, Auto-categorization,
Recurring (grouped by interval), Search (+ quick actions: nav, categorize,
export, undo/redo), Settings (theme/language picker, feature toggles, sync,
data export/reset), About (19 FAQ, privacy, GitHub), More page, Data Export,
Monthly Snapshots, Onboarding (4 cards), FinTS (bank search, credentials,
TAN handling, statement fetch), Sync (WebSocket + HTTP push/pull + E2E
encryption), Feedback (POST to wimg-sync), Demo data.

## Android Missing

- Renewals calendar tab on Recurring (iOS has 12-month forecast)
- Spending Heatmap tap-to-select (iOS has inline amount label)
- Account switcher UI (JNI bridged but no picker in top bar)
- Coachmarks (component exists but not placed on screens)
- Undo toast (component exists but not wired into mutations)
- i18n (German only, no English translations yet)
- FinTS Quick Refresh (iOS has PIN storage + one-tap fetch)

## iOS Missing

- Settings: sync key mask/reveal toggle (Low priority)
- Settings: sync QR code display (Low priority)
- FAQ deep-links from search (Low priority)
- Custom tax keywords UI (Web uses localStorage)

## Platform-Specific (intentional)

| Feature                              | Platform      | Reason                         |
| ------------------------------------ | ------------- | ------------------------------ |
| FinTS bank connection + TAN medium   | iOS + Android | Browsers can't do FinTS (CORS) |
| FinTS Quick Refresh (PIN storage)    | iOS only      | Android planned                |
| PWA install + service worker updates | Web only      | Native concept                 |
| OPFS persistence                     | Web only      | Native uses file on disk       |
| MCP server (AI agent access)         | Remote        | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only      | Native uses platform tools     |
| Command Palette                      | Web only      | Native uses platform navigation|
| In-app Changelog                     | Web only      | Native uses store notes / update checker |
| Auto-learn rules                     | All           | Runs in libwimg (Zig)          |
| Custom tax keywords                  | Web only      | localStorage, not synced       |
| Update checker (GitHub Releases)     | Android only  | iOS uses TestFlight, Web uses SW |
