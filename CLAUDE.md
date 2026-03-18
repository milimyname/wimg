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

- **Formatter:** oxfmt (`.oxfmtrc.json`)
- **Linter:** oxlint (`.oxlintrc.json`) — correctness/error, suspicious/warn, perf/warn
- **Pre-commit:** lefthook (`zig fmt`, `oxfmt`, `oxlint`, commit-msg validation)
- **Commit format:** conventional commits (`feat:`, `fix:`, `refactor:`, etc.) — enforced by lefthook
- **Tests:** `bun test` — 36 tests covering tax calculations, format utils, changelog logic
- **Release:** `scripts/release.sh` — bump versions, changelog (filters chore/ci/build), commit, tag, `--push`
- **Build WASM:** `scripts/build-wasm.sh` — two variants (web 209MB + compact 53MB)
- **Build iOS:** `scripts/build-ios.sh` — XCFramework
- **CI:** `.github/workflows/release.yml` — check → build → GitHub release
- **Feedback CI:** `.github/workflows/feedback-triage.yml` — Claude Code Action triages user-feedback issues

---

## Current Status (March 2026)

Phases 0–4B + 5.0, 5.1, 5.3, 5.7, 5.7b, 5.8, 5.9, 5.10, 5.11, 6.2, 6.3, 6.4, 6.5, 6.6 all **done**.

Working: CSV import (Comdirect/TR/Scalable), categorization (keyword rules +
auto-learn), summaries, debts, recurring detection, multi-account, undo/redo,
real-time sync with E2E encryption, MCP server (20 tools), data export,
monthly snapshots, PWA with offline support, DevTools panel (5 tabs), Command
Palette with SQL LIKE search + search history + transaction deep-links,
advanced search with date range, amount range slider, and category filters,
in-app changelog (`/changelog`) fetching GitHub Releases API with localStorage
cache, dark mode (light/dark/system with flash prevention), shared month/year
navigation across dashboard/analysis/review via `dateNav` store, savings goals
(CRUD with icon picker, progress tracking, feature-flagged), net worth over
time chart (SVG area chart in analysis page, cumulative from snapshots),
tax helper (Pendlerpauschale + Homeoffice calculators, auto-tagged
tax-relevant transactions, CSV export), Sparquote (savings rate) on
dashboard hero card, spending heatmap (GitHub contribution graph style).

Embeddings were built (Phase 5.5) then removed (Phase 5.9) — 4,400 lines
deleted. Keyword rules cover ~80% of categorization, MCP + Claude handles
the long tail. Semantic search didn't differentiate well for short queries
against banking descriptions. Simplicity won.

All Svelte stores use class-based reactive pattern (`class Store { #v = $state(...) }`).
No chat UI — Claude Desktop + MCP replaces it.

BottomNav has 3 tabs (Home, Umsätze, Mehr). Analyse moved to More page.
Landing page (`+page.svelte`) is German. Import and About pages redesigned
with card-based layouts, border styling, and project design tokens.

Conventional commits enforced by lefthook `commit-msg` hook.

LayerChart removed — all charts are pure SVG (DonutChart, NetWorthChart,
SpendingHeatmap). Changelog page shows commit type badges
(feat/fix/refactor/perf) with grid layout. About page has 22 FAQ entries
with hash-anchor deep-links from Command Palette (`afterNavigate` +
`noScroll` goto for reliable scrolling past Drawer body lock).
UpdateBanner changelog fallback for unreleased versions.

Drawer component (renamed from BottomSheet) with Base UI-inspired stacking:
global `drawerStore` tracks open drawers, portal to `document.body`, dynamic
z-index from stack depth, CSS-driven indent when nested (custom properties
`--indent-scale`/`--indent-y`), input isolation, dim overlay, data attributes
(`data-open`, `data-swiping`, `data-nested-drawer-open`). `DrawerIndent`
wraps page content for scale-down effect when any drawer opens. Sonner-style
stacked toasts (multiple simultaneous, hover-to-pause, swipe-to-dismiss).

In-app feedback system: `POST /feedback` on wimg-sync creates GitHub Issues
with `user-feedback` label. Rate limited (5/hour per IP). FeedbackSheet
stacks on top of Command Palette. Feedback history persisted in
localStorage (web) / UserDefaults (iOS). Claude Code Action auto-triages
feedback issues.

All Phase 6 features complete except 6.1 (Annual Review).
MCP server has 24 tools (11 read + 13 write) including savings goals.
Tax page has custom keyword settings (user-defined keywords per category,
persisted in localStorage). Tax logic extracted to `src/lib/tax.ts` (pure
functions, testable). Bun test runner with 36 tests covering tax
calculations, format utils, and changelog logic (migrated from vitest).

iOS dark mode support (ThemeManager with light/dark/system, adaptive colors
in WimgTheme, settings picker). Onboarding updated (4 cards:
privacy, import, goals/net-worth, tax/sync). SearchView has nav links to
all features including Bankverbindung (FinTS).

FinTS 3.0 protocol engine (pure Zig, ~2500 lines): anonymous init, authenticated
dialog (PIN/TAN), HKKAZ v5/v6/v7 statement fetch (version negotiated from BPD),
MT940 + CAMT parsing, photoTAN challenge extraction, decoupled TAN polling
(HKTAN process-S with BPD-derived timings), TAN mechanism auto-selection from
`3920`, HKTAB TAN medium fetch + selection (for banks requiring
`description_required=2`), touchdown pagination with structured `3040` extraction.
HTTP transport via C ABI callback (URLSession on iOS). Tested with Comdirect
(BLZ 20041177). Top-bank matrix script validates 8 major banks (anon init probe).
Bank catalog drift checker compares official CSV against `banks.zig` (1,745 entries).
Key protocol details: bare envelope (no HNVSK/HNVSD), HKTAN v2-v7, contiguous
segment numbering, YYYYMMDD dates, DEG colons not escaped. Static buffers for
Base64 encode/decode (prevent stack overflow on iOS GCD threads).

Deferred: Phase 5.2 (Notifications) — TBD.
Deferred: Phase 6.1 (Annual Review / "Geld-Wrapped") — planned for end of year.

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
- `banking-aggregators.md` — PSD2/PSD3 research, aggregator comparison, AISP licensing
- `testflight.md` — TestFlight setup, upload process, versioning
- `fints.md` — FinTS 3.0 technical deep dive (wire format, TAN flow, paging, MT940)
