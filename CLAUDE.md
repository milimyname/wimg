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

| Layer           | Choice                                             |
| --------------- | -------------------------------------------------- |
| Shared core     | Zig 0.15.2 + SQLite 3.52.0 (amalgamation)          |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart                |
| Web persistence | OPFS (offline SQLite in browser)                   |
| iOS UI          | SwiftUI + C ABI (libwimg.a)                        |
| Sync            | CF Durable Objects + WebSocket + LWW               |
| Categorization  | Keyword rules (~80%) + learned rules + MCP (long tail) |
| Search          | SQL LIKE (planned: FTS5 if needed at scale)        |
| FinTS           | Pure Zig (native-only, iOS)                        |
| MCP server      | CF Worker DO + libwimg-compact.wasm                |

---

## Tooling

- **Toolchain:** Vite+ (`vite-plus`) — `vp dev`, `vp build`, `vp fmt`, `vp lint`, `vp install`
- **Formatter:** `vp fmt` (config in `vite.config.ts` `fmt` block)
- **Linter:** `vp lint` (config in `vite.config.ts` `lint` block) — correctness/error, suspicious/warn, perf/warn
- **Pre-commit:** lefthook (`zig fmt`, `vp fmt`, `vp lint`, commit-msg validation)
- **Commit format:** conventional commits (`feat:`, `fix:`, `refactor:`, etc.) — enforced by lefthook
- **Release:** `scripts/release.sh` — bump versions, changelog (filters chore/ci/build), commit, tag, `--push`
- **Build WASM:** `scripts/build-wasm.sh` — two variants (web 209MB + compact 53MB)
- **Build iOS:** `scripts/build-ios.sh` — XCFramework
- **CI:** `.github/workflows/release.yml` — `setup-vp` → check → build → GitHub release

---

## Current Status (March 2026)

Phases 0–4B + 5.0, 5.1, 5.3, 5.7, 5.8, 5.9, 5.10, 5.11 all **done**.

Working: CSV import (Comdirect/TR/Scalable), categorization (keyword rules +
auto-learn), summaries, debts, recurring detection, multi-account, undo/redo,
real-time sync with E2E encryption, MCP server (20 tools), data export,
monthly snapshots, PWA with offline support, DevTools panel (5 tabs), Command
Palette with SQL LIKE search + search history + transaction deep-links,
advanced search with date range, amount range slider, and category filters,
in-app changelog (`/changelog`) fetching GitHub Releases API with localStorage
cache.

Embeddings were built (Phase 5.5) then removed (Phase 5.9) — 4,400 lines
deleted. Keyword rules cover ~80% of categorization, MCP + Claude handles
the long tail. Semantic search didn't differentiate well for short queries
against banking descriptions. Simplicity won.

All Svelte stores use class-based reactive pattern (`class Store { #v = $state(...) }`).
No chat UI — Claude Desktop + MCP replaces it.

BottomNav has 3 tabs (Home, Umsätze, Mehr). Analyse moved to More page.
Landing page (`+page.svelte`) is German. Import and About pages redesigned
with card-based layouts, border styling, and project design tokens.

Vite+ (`vite-plus`) replaces standalone oxfmt/oxlint — config consolidated
in `vite.config.ts`, all commands via `vp`. CI uses `setup-vp` action.
Conventional commits enforced by lefthook `commit-msg` hook.

Next: Command Palette Refinement (5.7b), Annual Renewals (5.4),
Phase 6 (Annual Review, Net Worth, Tax, Savings Goals).

Deferred: Notifications (5.2) — to be defined later.

---

## Principles

### Simplicity above all
Less code is better code. If a feature needs 2000 lines of infra for marginal
gain, it's not worth it. Prefer boring, proven solutions (SQL LIKE, keyword
rules) over clever ones (ML models, vector search). Every line of code is a
liability.

### 80/20 — Pareto Principle
Solve 80% of the problem with 20% of the effort. Keyword rules categorize ~80%
of transactions — that's good enough. MCP + Claude handles the long tail
on-demand. Don't build complex systems to automate the last 20%.

### Local-first, offline always
All data lives in SQLite. The app works fully offline with zero server
dependency. Network is an enhancement (sync), not a requirement. No loading
spinners for core functionality.

### Library is the product
One Zig library (libwimg) IS the app. Every platform (web, iOS) is a thin
shell that renders what the library returns. No logic duplication. Same CSV
parser, same categorization, same queries, everywhere. Inspired by libghostty.

### Don't fight the platform
C ABI for cross-platform. WASM for web, static lib for iOS. Use what each
platform gives you (OPFS on web, files on iOS, SwiftUI vs Svelte). Don't
abstract away platform differences — embrace them at the shell level.

### Earned complexity
Start simple. Add complexity only when the simple solution demonstrably fails.
LWW sync instead of CRDTs (one person, two devices). SQL LIKE before FTS5.
Keyword rules before embeddings. Every abstraction must justify its existence.

### Security by default
E2E encryption for sync — key derived from sync key, server sees only
ciphertext. PII stripping for MCP responses. No accounts, no passwords —
sync key IS the identity.

### Zero overhead for dev features
DevTools, feature flags, debug logging — all tree-shaken in production.
`devtoolsEnabled` boolean = zero cost when off. No runtime overhead for
things users never see.

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
- `release.md` — release process, commit format, CI pipeline
