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

## In Progress / Future

- **Phase 5.9** — Remove Embeddings (simplification)
  - Delete Zig inference engine: `gguf.zig`, `tokenizer.zig`, `quants.zig`, `embed.zig` (~2000 lines)
  - Delete web workers: `embed.worker.ts`, `embed-store.svelte.ts`
  - Remove C ABI exports: `wimg_embed_*`, `wimg_semantic_search`, `wimg_alloc_model`, `wimg_load_model`
  - Remove model download/OPFS logic from `wasm.ts`
  - Drop `embeddings` table
  - Saves 125MB model download per device
  - Rationale: keyword rules cover ~80%, MCP handles the rest. Earned complexity principle.
- **Phase 5.10** — Auto-learn Rules from User Actions
  - When user categorizes a transaction → extract merchant → insert into `rules` table
  - Future imports auto-match via learned rules
  - Coverage: keyword rules (80%) + learned rules (15%) + manual/MCP (5%)
- **Phase 5.7** — Command Palette + Search (Cmd+K)
  - `LIKE` substring search (simple, instant for 10K rows)
  - FTS5 only if `LIKE` demonstrably fails at scale (earned complexity)
  - Search across transactions, categories, and actions
- **Phase 5.2** — Notifications (deferred, TBD)
- **Phase 5.4** — Annual Renewals Calendar
- **Phase 6.1** — Annual Review ("Geld-Wrapped")
- **Phase 6.2** — Net Worth Over Time
- **Phase 6.3** — Anlage N Assistant (Tax Estimation)
- **Phase 6.4** — Savings Goals

## FinTS Product Registration (Pending)

Required to connect to real German banks. Free, one-time.
Email form to `registrierung@hbci-zka.de`. Not yet submitted.
