# wimg Phases

## Completed

- **Phase 0** — Zig Fundamentals (Done)
- **Phase 1** — libwimg MVP + Web Shell (Done): Zig core, WASM build, CSV import, OPFS
- **Phase 2** — Core Features (Done): Categories, summaries, debts, undo/redo, PWA, Claude AI
- **Phase 3** — SwiftUI iOS App (Done): XCFramework, all screens, feature parity
- **Phase 3.5** — Multi-Account Support (Done): Account CRUD, filter all screens
- **Phase 4A** — Pure Zig FinTS Client (Done): fints.zig, mt940.zig, iOS-only
- **Phase 4B** — Real-time Sync (Done): CF Durable Objects, WebSocket, E2E encryption
- **Phase 5.0** — UX Polish (Done): Onboarding, demo data, multi-file import
- **Phase 5.1** — Recurring Detection (Done): Pure SQL, price alerts
- **Phase 5.3** — Data Export + Snapshots (Done)
- **Phase 5.5** — Embeddings + Smart Categorization (Done): Pure Zig inference engine (multilingual-e5-small, Q8_0), GGUF parser, SentencePiece Unigram tokenizer (Viterbi), 384-dim embeddings, cosine similarity categorization. Semantic search tested but deprioritized — e5-small doesn't differentiate well for short queries against banking descriptions.
- **Phase 5.8** — Remote MCP Server (Done): 20 tools (10 read + 10 write), E2E encrypted
- **Phase 5.9** — Remove Embeddings (Done): Deleted Zig inference engine (~4,400 lines), web workers, model download. Keyword rules + MCP suffice.
- **Phase 5.7** — Command Palette + Search (Done): SQL LIKE search via `searchTransactions()`, search history (localStorage), transaction deep-links with URL params (`?txn=`, `?filter`, `?cmd`), class-based Svelte stores.
- **Phase 5.10** — Auto-learn Rules (Done): `extractKeyword()` strips German banking prefixes, `learnRule()` in `db.zig` inserts low-priority (1) rules on every manual `setCategory()`. No new C ABI, no UI changes. ~50 lines Zig.

## In Progress / Future

- **Phase 5.7b** — Command Palette Refinement
  - Change month/year from palette (context-aware)
  - Quick categorize transaction from search results (inline picker)
  - Exclude/include transaction from search results
  - Add debt from palette (needs input fields)
  - Dark mode / theme toggle
- **Phase 5.11** — In-App Changelog (Linear-style)
  - `/changelog` page fetching GitHub Releases API (public, no auth)
  - Timeline UI with version badges, dates, commit descriptions
  - UpdateBanner shows inline changelog (diff between current and new version)
  - "Was ist neu?" links to `/changelog` instead of GitHub
  - localStorage cache for offline access after first fetch
- **Phase 5.2** — Notifications (deferred, TBD)
- **Phase 5.4** — Annual Renewals Calendar
- **Phase 6.1** — Annual Review ("Geld-Wrapped")
- **Phase 6.2** — Net Worth Over Time
- **Phase 6.3** — Anlage N Assistant (Tax Estimation)
- **Phase 6.4** — Savings Goals

## FinTS Product Registration (Done)

Registration ID: `F7C4049477F6136957A46EC28` (25 chars, goes in HKVVB Produktbezeichnung).
Received from registrierung@hbci-zka.de. Note: bank databases update after several business days.
