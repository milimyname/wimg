# wimg Phases

## Completed

- **Phase 0** — Zig Fundamentals (Done)
- **Phase 1** — libwimg MVP + Web Shell (Done): Zig core, WASM build, CSV import, OPFS
- **Phase 2** — Core Features (Done): Categories, summaries, debts, undo/redo, PWA, Claude AI
- **Phase 3** — SwiftUI iOS App (Done): XCFramework, all screens, feature parity
- **Phase 3.5** — Multi-Account Support (Done): Account CRUD, filter all screens
- **Phase 4A** — Pure Zig FinTS Client (Done): fints.zig, fints_http.zig, mt940.zig, banks.zig, iOS-only. Anonymous init, auth dialog (PIN/TAN with nochallenge detection), HKKAZ v5 statement fetch, MT940 parsing, photoTAN challenge extraction. HTTP via C ABI callback (URLSession on iOS). Tested with Comdirect.
- **Phase 4B** — Real-time Sync (Done): CF Durable Objects, WebSocket, E2E encryption
- **Phase 5.0** — UX Polish (Done): Onboarding, demo data, multi-file import
- **Phase 5.1** — Recurring Detection (Done): Pure SQL, price alerts
- **Phase 5.3** — Data Export + Snapshots (Done)
- **Phase 5.5** — Embeddings + Smart Categorization (Done): Pure Zig inference engine (multilingual-e5-small, Q8_0), GGUF parser, SentencePiece Unigram tokenizer (Viterbi), 384-dim embeddings, cosine similarity categorization. Semantic search tested but deprioritized — e5-small doesn't differentiate well for short queries against banking descriptions.
- **Phase 5.8** — Remote MCP Server (Done): 20 tools (10 read + 10 write), E2E encrypted
- **Phase 5.9** — Remove Embeddings (Done): Deleted Zig inference engine (~4,400 lines), web workers, model download. Keyword rules + MCP suffice.
- **Phase 5.7** — Command Palette + Search (Done): SQL LIKE search via `searchTransactions()`, search history (localStorage), transaction deep-links with URL params (`?txn=`, `?filter`, `?cmd`), class-based Svelte stores.
- **Phase 5.10** — Auto-learn Rules (Done): `extractKeyword()` strips German banking prefixes, `learnRule()` in `db.zig` inserts low-priority (1) rules on every manual `setCategory()`. No new C ABI, no UI changes. ~50 lines Zig.
- **Phase 5.11** — In-App Changelog (Done): Standalone `/changelog` page (outside `(app)` layout) fetching GitHub Releases API. Card-based UI with version pills, German dates, warm fintech design. localStorage cache (1hr TTL) for offline access. "Was ist neu?" links in UpdateBanner, About footer, and landing page footer point to `/changelog`. Conventional commits enforced by lefthook `commit-msg` hook. `release.sh` filters chore/ci/build commits from changelog.

## In Progress / Future

- **Phase 5.7b** — Command Palette Refinement (Done): Shared `dateNav` store for month/year across dashboard/analysis/review. Palette actions: prev/next/current month. Quick categorize from search results (inline category picker). Exclude/include toggle on search results. Dark mode (light/dark/system) with CSS variable overrides, flash prevention, premium dark theme (#111114 bg, #1c1c1e cards, white/5 borders). Theme toggle action in palette.
- **Phase 5.2** — Notifications (deferred, TBD)
- **Phase 5.4** — Annual Renewals Calendar
- **Phase 6.1** — Annual Review ("Geld-Wrapped")
- **Phase 6.2** — Net Worth Over Time (Done): SVG area chart in analysis page showing cumulative net worth from snapshots. Smooth bezier curves, gradient fill, dot markers, month labels, stats grid (highest/lowest/average), year-over-year growth badge. NetWorthChart component. Requires 2+ snapshots.
- **Phase 6.3** — Anlage N Assistant (Done): Tax helper page (`/tax`) with Pendlerpauschale calculator (0.30€/km first 20km + 0.38€/km beyond), Homeoffice-Pauschale (6€/day, max 210 days), auto-tagged tax-relevant transactions (5 categories: Arbeitsmittel, Fortbildung, Fachliteratur, Fahrtkosten, Versicherungen), include/exclude toggles, year picker, summary grid, CSV export. Config persisted in localStorage. Feature-flagged (`tax: true`).
- **Phase 6.4** — Savings Goals (Done): `savings_goals` table (schema v14), full CRUD with sync support. C ABI: `wimg_get_goals`, `wimg_add_goal`, `wimg_contribute_goal`, `wimg_delete_goal`. Web: goals page with hero card, icon picker (12 icons), inline contribute input, progress bars, undo support. Feature-flagged (`goals: true`).
- **Phase 6.5** — Sparquote + Spending Heatmap (Done): Savings rate (`(income + expenses) / income * 100`) on dashboard hero card (web + iOS). SpendingHeatmap component (GitHub contribution graph style) — SVG grid with months as rows, years as columns, indigo color scale from snapshot expenses. Both platforms. No new schema or C ABI — reads existing `snapshots` table.
- **Phase 6.6** — FinTS Statement Import Hardening (Done): Full Comdirect end-to-end parity for auth + fetch + TAN submit. Fixed task-reference propagation for HKTAN process-2, robust HITAN/HITANS dispatch, binary-safe `@len@` parsing, matrix/photoTAN payload normalization, HIKAZ multi-part MT940 concatenation, parser normalization (`@@ -> CRLF`, `-0000 -> +0000`, optional funds code), and touchdown pagination via 3040 continuation token. Import now persists multi-page statement history with duplicate-safe inserts.
- **Phase 6.7** — FinTS Multi-Bank Hardening (Done): Decoupled TAN polling (HKTAN process-S with BPD-derived timings), TAN mechanism auto-selection from `3920`, HKKAZ v5/v6/v7 version negotiation from `HIKAZS` BPD, transparent MT940 → CAMT fallback (`camt.zig`, 112 tests), structured `3040` touchdown extraction, HKTAB TAN medium fetch + selection (new C ABI: `wimg_fints_get_tan_media`, `wimg_fints_set_tan_medium`), iOS TAN medium picker stage, top-bank validation matrix (8 banks), bank catalog drift checker (`scripts/check-bank-drift.py`).
- **Phase 6.8** — Deutsche Bank / Postbank Compatibility (Planned): Both reject with `9110` in anon mode — likely need security envelope or bank-family-specific init. Investigation: compare python-fints behavior, check if HNVSK required, may need bank-family flags in `banks.zig`.
- **Phase 6.9** — FinTS Background Sync (Planned): iOS background refresh for no-TAN paths (`3076`/`nochallenge`), pending-action resume when TAN required, import result UX improvements.

## FinTS Product Registration (Done)

Registration ID: `F7C4049477F6136957A46EC28` (25 chars, goes in HKVVB Produktbezeichnung).
Received from registrierung@hbci-zka.de. Note: bank databases update after several business days.
