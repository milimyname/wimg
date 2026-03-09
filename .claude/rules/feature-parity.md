# Feature Parity — iOS vs Web

Both platforms are thin shells over the same libwimg C ABI.
FinTS is intentionally iOS-only (browsers can't do FinTS due to CORS).

## At Parity

Dashboard, Transactions, Analysis, Debts, Monthly Review, CSV Import,
Auto-categorization, Claude AI, Account Switcher, Account Management,
Sync (enable/link/manual/copy key), Real-time WebSocket, E2E Encryption,
Settings, More page, About page, Data Export, Monthly Snapshots, Undo toast.

## iOS Missing

- Settings: sync key mask/reveal toggle (Low priority)
- Settings: sync QR code display (Low priority)

## Platform-Specific (intentional)

| Feature                              | Platform    | Reason                         |
| ------------------------------------ | ----------- | ------------------------------ |
| FinTS bank connection                | iOS only    | Browsers can't do FinTS (CORS) |
| PWA install + service worker updates | Web only    | Native concept                 |
| OPFS persistence                     | Web only    | iOS uses file on disk          |
| MCP server (AI agent access)         | Remote      | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only    | iOS uses Xcode Instruments     |
