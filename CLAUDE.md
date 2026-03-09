# wimg — Local-First Personal Finance

> libwimg (Zig) · Svelte 5 web · SwiftUI iOS

Last updated: March 2026

---

## Vision

One Zig library — **libwimg** — that IS the app. Every platform (web, iOS) is
a thin shell around it. No logic duplication. Same CSV parser, same
categorization, same SQLite queries, everywhere.

Inspired by libghostty: the library is the product. The UIs are just renderers.

---

## Tech Stack

| Layer           | Choice                                     |
| --------------- | ------------------------------------------ |
| Shared core     | Zig 0.15.2 + SQLite 3.52.0 (amalgamation) |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart        |
| Web persistence | OPFS (offline SQLite in browser)           |
| iOS UI          | SwiftUI + C ABI (libwimg.a)                |
| Sync            | CF Durable Objects + WebSocket + LWW       |
| AI              | Claude API (JS-side, optional)             |
| FinTS           | Pure Zig (native-only, iOS)                |
| MCP server      | CF Worker DO + libwimg-compact.wasm        |

---

## Tooling

- **Package manager:** bun (always, never npm)
- **Formatter:** oxfmt (`.oxfmtrc.json`)
- **Linter:** oxlint (`.oxlintrc.json`) — correctness/error, suspicious/warn, perf/warn
- **Pre-commit:** lefthook (zig fmt, oxfmt, oxlint)
- **Release:** `scripts/release.sh` — bump versions, changelog, commit, tag
- **Build WASM:** `scripts/build-wasm.sh` — two variants (web 209MB + compact 53MB)
- **Build iOS:** `scripts/build-ios.sh` — XCFramework
- **CI:** `.github/workflows/release.yml` — check → build → GitHub release

---

## Current Status (March 2026)

Phases 0–4B + 5.0, 5.1, 5.3, 5.8 all **done**.

Working: CSV import (Comdirect/TR/Scalable), categorization, summaries,
debts, recurring detection, multi-account, undo/redo, real-time sync with
E2E encryption, MCP server (17 tools), data export, monthly snapshots,
PWA with offline support, DevTools panel (5 tabs).

Next: Notifications (5.2), Annual Renewals (5.4), Command Palette (5.7),
Phase 6 (Annual Review, Net Worth, Tax, Savings Goals).

---

## Key Principles

- Local-first: all data in SQLite, works fully offline
- Last-write-wins sync (no CRDTs) — one person, two devices
- C ABI for cross-platform: same Zig library on web (WASM) and iOS (FFI)
- E2E encryption: key derived from sync key, server sees only ciphertext
- Friendly fintech design: light, cards, warm tones, calm
- Zero production overhead for dev features (DevTools tree-shaken in prod)

---

## Detailed Documentation

Split into `.claude/rules/` for context efficiency:

- `architecture.md` — full architecture diagrams, data flow, tech stack details
- `schema.md` — complete SQLite schema (all tables)
- `c-abi.md` — all C ABI function signatures + WASM memory budget
- `phases.md` — all phase details (completed + future)
- `sync.md` — sync system, E2E encryption, MCP server, API
- `devtools.md` — DevTools panel (5 tabs, activation, architecture)
- `feature-flags.md` — feature flag system (web + iOS)
- `feature-parity.md` — iOS vs web parity table
- `file-structure.md` — complete file tree
- `decisions.md` — decision log (all architectural choices)
