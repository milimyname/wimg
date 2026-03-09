# Feature Flags

Simple localStorage (web) / UserDefaults (iOS) toggles. Features are compiled
in — flags just control visibility in navigation, routes, and screens.

## Always-on (core)

Dashboard, Transactions, Analysis, Import, Settings, About, Sync

## Toggleable

| Flag Key    | Label          | Description                    | Status      |
| ----------- | -------------- | ------------------------------ | ----------- |
| `debts`     | Schulden       | Debt tracking with progress    | Implemented |
| `recurring` | Wiederkehrend  | Recurring payment detection    | Implemented |
| `review`    | Rückblick      | Monthly review                 | Implemented |
| `goals`     | Sparziele      | Savings goals (Phase 6.4)      | Future      |
| `net_worth` | Vermögen       | Net worth tracking (Phase 6.2) | Future      |
| `tax`       | Steuern        | Anlage N assistant (Phase 6.3) | Future      |
| `ai_chat`   | KI-Chat        | AI chat (Phase 5.6)            | Future      |

## Storage

- **Web:** `localStorage` key `wimg_features` → JSON object (`features.svelte.ts`)
- **iOS:** `UserDefaults` key `wimg_features` → JSON (`FeatureFlags.swift`)
- Defaults: `{ debts: true, recurring: true, review: true }`

## How it works

1. `featureStore` (web) / `FeatureFlags.shared` (iOS) — reactive singleton
2. More page filters grid items by enabled features
3. BottomNav filters `moreSubRoutes` so disabled features don't highlight "Mehr"
4. Settings page has toggle section between Claude AI and About
5. New features: add flag key to `DEFAULT_FEATURES` / `defaultFeatures`, add
   toggle entry, gate with `featureStore.isEnabled(key)` / `FeatureFlags.shared.isEnabled(key)`
