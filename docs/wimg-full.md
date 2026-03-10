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
| AI              | Local embeddings (Zig, multilingual-e5-small Q8_0) |
| FinTS           | Pure Zig (native-only, iOS)                        |
| MCP server      | CF Worker DO + libwimg-compact.wasm                |

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

Phases 0–4B + 5.0, 5.1, 5.3, 5.5, 5.8 all **done**.

Working: CSV import (Comdirect/TR/Scalable), categorization, summaries,
debts, recurring detection, multi-account, undo/redo, real-time sync with
E2E encryption, MCP server (20 tools), data export, monthly snapshots,
PWA with offline support, DevTools panel (5 tabs), local embeddings
(pure Zig inference, multilingual-e5-small Q8_0, 384-dim), smart categorization,
semantic search.

Embeddings are infrastructure — they make categorization smarter and search
better. No chat UI (Claude Desktop + MCP replaces it).

Next: Annual Renewals (5.4), Command Palette + Semantic Search (5.7),
Phase 6 (Annual Review, Net Worth, Tax, Savings Goals).

Deferred: Notifications (5.2) — to be defined later.

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

---

# wimg Architecture

## Overview

```
libwimg (Zig)
├── sqlite3.c (amalgamation, compiled in — no external dep)
├── src/
│   ├── root.zig        C ABI exports — the public API
│   ├── db.zig          SQLite wrapper + schema + migrations
│   ├── parser.zig      CSV parsing (Comdirect, Trade Republic, Scalable)
│   ├── categories.zig  Categorization (keyword rules)
│   ├── summary.zig     Monthly summaries, debt tracking, goals
│   ├── types.zig       Transaction, Category, Summary structs
│   ├── gguf.zig        GGUF v3 file parser
│   ├── quants.zig      Dequantization (Q4_K, Q6_K, Q8_0, F16) + vector math
│   ├── tokenizer.zig   SentencePiece BPE tokenizer (vocab/scores from GGUF)
│   └── embed.zig       BERT transformer forward pass (12 layers, e5-small)
│
├── → libwimg.wasm      (wasm32-freestanding) ← web
└── → libwimg.a         (aarch64-apple-ios)   ← iOS / macOS

wimg-web  (Svelte 5 + TailwindCSS + LayerChart)
├── loads libwimg.wasm
├── OPFS for SQLite persistence (offline, no server)
├── PWA — installable, works fully offline
└── thin shell: UI only, zero business logic

wimg-ios  (SwiftUI)
├── links libwimg.a
├── SQLite file at ~/Documents/wimg.db
└── thin shell: UI only, zero business logic
```

### Data flow

```
User drops CSV
  → wimg-web passes bytes to libwimg.wasm
  → parser.zig parses Comdirect/TR/Scalable format
  → categories.zig assigns categories (keyword rules + smart categorize)
  → db.zig writes to SQLite (via OPFS on web, file on iOS)
  → root.zig returns JSON to Svelte
  → Svelte renders transaction list
```

### Sync (Phase 4)

Last-write-wins via `updated_at` timestamp on every row.
No CRDTs, no Automerge, no conflict resolution complexity.
One person, two devices — whoever saved last is right.

Sync via Cloudflare Durable Objects + WebSocket Hibernation API.
Real-time: change on one device → appears on others within 1-2 seconds.

### Offline

Web: OPFS (Origin Private File System) — SQLite writes directly to a local
browser file. Works offline. Persists across sessions. No server needed.

Requires these headers (Vite dev + production host):

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

iOS: regular file on disk. Always offline-first by nature.

### Pure Zig Inference Engine

Local embedding model runs entirely in Zig — no ggml, no llama.cpp, no C++ deps.
~500 lines of Zig for a complete BERT forward pass on wasm32-freestanding.

**Model:** multilingual-e5-small (118M params, 12 layers, 384-dim, Q8_0 GGUF, ~125MB)

```
GGUF file (from HuggingFace)
  → gguf.zig parses header, KV metadata, tensor directory
  → tokenizer.zig loads vocab + scores from GGUF metadata
  → embed.zig loads tensor weights (Q8_0 quantized)

Input text ("REWE MARKT BERLIN")
  → tokenizer.zig: SentencePiece BPE → token IDs [▁RE, WE, ▁MAR, KT, ...]
  → embed.zig: 12-layer BERT forward pass
     1. Token embeddings + position embeddings (lookup)
     2. Per layer: self-attention (Q/K/V) → FFN (up → GELU → down)
     3. RMSNorm after each sublayer
     4. Mean pooling over sequence → L2 normalize
  → 384-dim float32 vector output
  → Stored in embeddings table (1536 bytes per transaction)

Smart categorize:
  → Cosine similarity between uncategorized tx and categorized tx embeddings
  → Sign-aware: only matches income↔income, expense↔expense
  → Threshold > 0.7 → assign same category

Semantic search:
  → Embed query text → cosine similarity against all tx embeddings → top-K
```

**Key implementation details:**

- Q8_0 dequantization: 32 int8 values + f16 scale per block → f32
- All computation in f32 (no SIMD, single-threaded — fast enough for WASM)
- Model loaded via `@wasmMemoryGrow` (too large for 64MB FBA)
- Tokenizer vocab/scores in file-level statics (too large for 1MB stack)
- Web worker (`embed.worker.ts`) runs inference off main thread
- Model stored in OPFS (persistent, not affected by SW cache cleanup)

---

## Tech Stack

| Layer           | Choice                                    | Why                                                   |
| --------------- | ----------------------------------------- | ----------------------------------------------------- |
| Shared core     | Zig 0.15.2                                | Single source of truth for all logic                  |
| Storage         | SQLite 3.52.0 (amalgamation, compiled in) | Local, queryable, no deps                             |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart       | Reactive, lightweight, Svelte-native charts           |
| Web persistence | OPFS                                      | SQLite-on-browser, offline, no server                 |
| iOS UI          | SwiftUI                                   | Native, links libwimg.a via C ABI                     |
| Sync            | CF Durable Objects + WebSocket + LWW      | Real-time, hibernation = cost-efficient               |
| AI              | Local embeddings (Zig)                    | Pure Zig inference for smart categorization + search  |
| Embeddings      | multilingual-e5-small (Q8_0 GGUF, ~125MB) | 384-dim vectors, pure Zig inference, semantic search  |
| FinTS           | Pure Zig (fints.zig + mt940.zig)          | No external deps, native-only, direct bank connection |
| MCP server      | CF Worker DO + libwimg.wasm + Zod         | Remote MCP via POST /mcp, Bearer auth = sync key      |

---

# C ABI — libwimg Public API

These are the exact functions both Svelte (via WASM) and Swift (via FFI) call.
Same signatures, same behavior, same SQLite underneath.

```zig
// Lifecycle
export fn wimg_init(db_path: [*:0]const u8) i32
export fn wimg_close() void
export fn wimg_free(ptr: [*]u8, len: usize) void
export fn wimg_alloc(len: usize) ?[*]u8

// Import
export fn wimg_parse_csv(ptr: [*]const u8, len: usize) ?[*]const u8
export fn wimg_import_csv(ptr: [*]const u8, len: usize) i32

// Transactions
export fn wimg_get_transactions() i32
export fn wimg_set_category(id: [*]const u8, id_len: usize, cat: u8) i32
export fn wimg_auto_categorize() i32

// Summaries
export fn wimg_get_summary(year: i32, month: i32) i32

// Accounts
export fn wimg_get_accounts() ?[*]const u8
export fn wimg_add_account(ptr: [*]const u8, len: usize) i32
export fn wimg_update_account(ptr: [*]const u8, len: usize) i32
export fn wimg_delete_account(id: [*]const u8, id_len: usize) i32

// Debt tracker
export fn wimg_get_debts() i32
export fn wimg_add_debt(ptr: [*]const u8, len: usize) i32
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: usize, amount: i64) i32
export fn wimg_delete_debt(id: [*]const u8, id_len: usize) i32

// Undo/Redo
export fn wimg_undo() ?[*]const u8
export fn wimg_redo() ?[*]const u8

// Snapshots
export fn wimg_take_snapshot(year: u32, month: u32) i32
export fn wimg_get_snapshots() ?[*]const u8

// Export
export fn wimg_export_csv() ?[*]const u8
export fn wimg_export_db() ?[*]const u8

// Persistence (OPFS)
export fn wimg_get_db_ptr() ?[*]u8
export fn wimg_get_db_size() usize
export fn wimg_restore_db(ptr: [*]const u8, len: usize) i32

// SQL (DevTools)
export fn wimg_query(sql_ptr: [*]const u8, sql_len: u32) ?[*]const u8

// Embeddings (Phase 5.5)
export fn wimg_alloc_model(size: u32) ?[*]u8           // grows WASM memory for model
export fn wimg_load_model(data: [*]const u8, len: u32) i32
export fn wimg_embed_text(text: [*]const u8, text_len: u32) ?[*]const u8
export fn wimg_embed_transactions() i32
export fn wimg_smart_categorize() i32
export fn wimg_semantic_search(query: [*]const u8, query_len: u32, k: u32) ?[*]const u8
export fn wimg_embedding_status() ?[*]const u8
```

All functions return JSON strings into a caller-provided buffer.
Negative return = error. Caller owns the buffer.

---

## WASM Memory Budget (Two Builds)

Two WASM builds with different memory budgets, controlled by `-Dcompact` in
`build.zig`. Same binary size (~783KB).

**Web app** (default: `zig build --release=small`):

| Source           | File          | Size    |
| ---------------- | ------------- | ------- |
| `wasm_buf` (FBA) | `root.zig`    | 64 MB   |
| `mem_storage[4]` | `wasm_vfs.c`  | 128 MB  |
| `heap`           | `libc_shim.c` | 16 MB   |
| Stack            | `build.zig`   | 1 MB    |
| **Total**        |               | ~209 MB |

**MCP/CF Workers** (compact: `zig build --release=small -Dcompact=true`):

| Source           | File          | Size   |
| ---------------- | ------------- | ------ |
| `wasm_buf` (FBA) | `root.zig`    | 16 MB  |
| `mem_storage[4]` | `wasm_vfs.c`  | 32 MB  |
| `heap`           | `libc_shim.c` | 4 MB   |
| Stack            | `build.zig`   | 1 MB   |
| **Total**        |               | ~53 MB |

---

# Decision Log

| Date     | Decision                                    | Reason                                                                                                                                                                               |
| -------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Mar 2026 | Zig as shared core, not Rust                | Already learning Zig, libghostty proves the model                                                                                                                                    |
| Mar 2026 | No Automerge                                | Rust-only, logic still duplicated per platform                                                                                                                                       |
| Mar 2026 | SQLite compiled into libwimg                | One storage engine, same on web + iOS                                                                                                                                                |
| Mar 2026 | Last-write-wins sync                        | Single user, two devices — CRDT overkill                                                                                                                                             |
| Mar 2026 | OPFS for web persistence                    | True offline SQLite in browser, no server                                                                                                                                            |
| Mar 2026 | FinTS via separate wimg-sync binary         | Can't compile AqBanking to WASM                                                                                                                                                      |
| Mar 2026 | Friendly fintech design                     | Light, cards, warm tones, calm                                                                                                                                                       |
| Mar 2026 | LayerChart instead of D3                    | Svelte-native, PieChart component, less boilerplate                                                                                                                                  |
| Mar 2026 | Claude API removed from web app             | Local embeddings + smart categorize replaced Claude API for categorization. Claude Desktop + MCP covers financial Q&A.                                                               |
| Mar 2026 | COEP `credentialless` not `require-corp`    | `require-corp` breaks Vite HMR WebSocket in dev                                                                                                                                      |
| Mar 2026 | Controlled SW updates (no skipWaiting)      | Users choose when to update; banner shows changelog; OPFS clear for breaking schema changes                                                                                          |
| Mar 2026 | XcodeGen for iOS project                    | Auto-discovers Swift files, no manual pbxproj editing                                                                                                                                |
| Mar 2026 | Multi-account as Phase 3.5                  | Transactions already have `account` column; minimal schema change, big UX win                                                                                                        |
| Mar 2026 | `scripts/release.sh` for versioning         | Single command: bump versions, generate changelog, commit, tag                                                                                                                       |
| Mar 2026 | CI downloads SQLite amalgamation            | sqlite3.c gitignored (9MB); CI fetches from sqlite.org                                                                                                                               |
| Mar 2026 | `lefthook` pre-commit hooks                 | Catch fmt/lint issues before commit (zig fmt, oxfmt, oxlint)                                                                                                                         |
| Mar 2026 | CI tests with `-Doptimize=ReleaseFast`      | sqlite3.c compilation 72s → ~15s in CI                                                                                                                                               |
| Mar 2026 | Cloudflare R2 for sync storage              | JSON blob sync, 10GB free, no vendor lock-in risk                                                                                                                                    |
| Mar 2026 | Durable Objects + WebSocket Hibernation     | Real-time sync, one DO per sync key, idle DOs cost nothing                                                                                                                           |
| Mar 2026 | Hono for Worker routing                     | Lightweight, CORS middleware, clean route handlers                                                                                                                                   |
| Mar 2026 | Echo suppression (2s window) over WS tags   | Simple, avoids pusher applying own changes back; no session tracking needed                                                                                                          |
| Mar 2026 | Remote MCP in wimg-sync, not local          | CF Worker DO keeps WASM warm, no local Bun process needed, accessible from Claude.ai                                                                                                 |
| Mar 2026 | Manual JSON-RPC over MCP SDK                | MCP protocol is simple JSON-RPC; avoids Node.js deps in CF Workers, keeps bundle small                                                                                               |
| Mar 2026 | Feature flags via localStorage/UserDefaults | Simple toggles, no plugin runtime; features compiled in, flags control UI visibility only                                                                                            |
| Mar 2026 | Two WASM builds (`-Dcompact` flag)          | Web app gets large buffers (209MB), MCP/CF Workers gets compact (53MB)                                                                                                               |
| Mar 2026 | MCP Streamable HTTP (protocol `2025-03-26`) | Claude Desktop requires Streamable HTTP; session ID via `Mcp-Session-Id` header                                                                                                      |
| Mar 2026 | SQLite 3.52.0                               | WAL corruption fix, query planner improvements, float precision                                                                                                                      |
| Mar 2026 | DevTools via `?devtools` URL param          | Enables prod debugging; `devtoolsEnabled` boolean flag = zero overhead when off                                                                                                      |
| Mar 2026 | `config` module for all Zig targets         | `root.zig` imports `config` unconditionally; native builds get `compact=false` default                                                                                               |
| Mar 2026 | Embeddings over LLMs for categorization     | Tested wllama (llama.cpp WASM) with Qwen3 0.6B–1.7B: too slow on CPU, heats MacBook M2. Embedding model + cosine similarity is 100x faster and deterministic.                        |
| Mar 2026 | PII stripping for MCP responses             | MCP clients see decrypted data; `stripPII()` removes IBANs, card numbers, BICs, references, personal names from descriptions. Merchant names kept for categorization.                |
| Mar 2026 | Pure Zig inference over vendoring ggml      | ggml has C++ files, threading, and heavy libc deps that break on wasm32-freestanding. ~400 lines of Zig for a fixed BERT forward pass is cleaner.                                    |
| Mar 2026 | multilingual-e5-small (swapped from jina)   | 118M params, ~125MB Q8_0, 384-dim, 100+ languages. 10x smaller/faster than jina-v5-nano (239M, 157MB Q4_K_M, 768-dim). Custom Q8_0 quantization via scripts/quantize-q8.py.          |
| Mar 2026 | OPFS for embedding model storage            | More reliable than Cache API (not affected by service worker cache cleanup). Model persists across sessions per browser.                                                             |
| Mar 2026 | Sign-aware smart categorize                 | Only match income with income, expenses with expenses in cosine similarity. Prevents misclassifying income as shopping.                                                              |
| Mar 2026 | Embeddings not synced (derived data)        | Each device computes its own from transaction descriptions. Avoids syncing large BLOBs. `model_ver` field allows re-embedding on model change.                                       |
| Mar 2026 | `@wasmMemoryGrow` for model loading         | Model doesn't fit in 64MB FBA. `wimg_alloc_model` grows WASM linear memory directly for large allocations.                                                                           |
| Mar 2026 | File-level statics for large buffers        | Tokenizer vocab arrays (~1.5MB) are too large for 1MB WASM stack. Moved to file-level statics in embed.zig and tokenizer.zig.                                                        |
| Mar 2026 | `batch_categorize_by_pattern` MCP tool      | Pattern-based categorization reduces LLM tool calls from 10+ to 2. Match merchant substrings, apply category to all matches at once. Increased batch limit to 500.                   |
| Mar 2026 | No chat UI, Claude Desktop + MCP instead    | Embeddings are infrastructure (smart categorization + semantic search), not a chat feature. Claude Desktop/Claude.ai with MCP already provides financial Q&A. Chat UI was redundant. |

---

# DevTools (Web Only)

TanStack-style developer panel for inspecting WASM performance, memory, sync,
and data state. Web only — iOS uses Xcode Instruments.

## Activation

- **Dev mode:** always available (auto-enabled via `import.meta.env.DEV`)
- **Production:** add `?devtools` URL param
- **Toggle:** `Ctrl+Shift+D` keyboard shortcut or floating gear button

## Architecture

```
devtools.svelte.ts          Reactive $state store (singleton)
├── wasmCalls[]             Ring buffer of 200 WASM call records
├── syncEvents[]            Ring buffer of 100 sync events
├── actions[]               Ring buffer of 100 action log entries (mutations)
├── syncDiffs[]             Ring buffer of 50 sync diff records
├── aggregateStats          Per-function call count + total ms (computed)
├── sparklineData           60-element array of call counts per second
├── devtoolsEnabled         Global boolean flag checked by instrumentation
└── open / activeTab        Panel UI state

wasm.ts                     timed() / timedAsync() wrappers + logAction() on mutations
sync.ts                     Push/pull event logging + sync diffs
sync-ws.svelte.ts           WS connect/disconnect/message logging + sync diffs

DevTools.svelte             Floating panel UI (5 tabs), macOS-style corner resize
+layout.svelte              Dynamic import + keyboard shortcut + ?devtools param
```

## Panel Tabs

| Tab    | Shows                                                                            |
| ------ | -------------------------------------------------------------------------------- |
| WASM   | Sparkline (60s) + aggregate stats + call log + Action Log                        |
| Memory | WASM linear memory, SQLite DB size, budget bar, growth indicator                 |
| Sync   | WS status pill, sync event log, Sync Diff Viewer                                 |
| Data   | Entity counts, Feature Flags, OPFS Browser, localStorage, Snapshots, Danger Zone |
| SQL    | Query runner (Cmd+Enter), history, results, Schema Inspector                     |

## Resize

macOS-style corner grip at top-left. Width 300-900px, height 250-800px.
Document-level pointermove/pointerup. Cursor overlay during drag.

## Files

- `wimg-web/src/lib/devtools.svelte.ts` — store + `devtoolsEnabled` flag
- `wimg-web/src/components/DevTools.svelte` — panel UI
- `libwimg/src/root.zig` — `wimg_query` C ABI export for SQL tab
- `libwimg/src/db.zig` — `rawQuery()` for arbitrary SQL

---

# Feature Flags

Simple localStorage (web) / UserDefaults (iOS) toggles. Features are compiled
in — flags just control visibility in navigation, routes, and screens.

## Always-on (core)

Dashboard, Transactions, Analysis, Import, Settings, About, Sync

## Toggleable

| Flag Key    | Label         | Description                    | Status      |
| ----------- | ------------- | ------------------------------ | ----------- |
| `debts`     | Schulden      | Debt tracking with progress    | Implemented |
| `recurring` | Wiederkehrend | Recurring payment detection    | Implemented |
| `review`    | Rückblick     | Monthly review                 | Implemented |
| `goals`     | Sparziele     | Savings goals (Phase 6.4)      | Future      |
| `net_worth` | Vermögen      | Net worth tracking (Phase 6.2) | Future      |
| `tax`       | Steuern       | Anlage N assistant (Phase 6.3) | Future      |
| `ai_chat`   | KI-Chat       | Removed — Claude Desktop + MCP | Removed     |

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

---

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

| Feature                              | Platform | Reason                         |
| ------------------------------------ | -------- | ------------------------------ |
| FinTS bank connection                | iOS only | Browsers can't do FinTS (CORS) |
| PWA install + service worker updates | Web only | Native concept                 |
| OPFS persistence                     | Web only | iOS uses file on disk          |
| MCP server (AI agent access)         | Remote   | CF Worker DO, any MCP client   |
| DevTools panel                       | Web only | iOS uses Xcode Instruments     |

---

# File Structure

```
wimg/
├── CHANGELOG.md               auto-generated by release.sh
├── lefthook.yml               pre-commit hooks (zig fmt, oxfmt, oxlint)
├── scripts/
│   ├── release.sh             version bump + changelog + commit + tag
│   ├── build-wasm.sh          build both WASM variants (web + compact/MCP)
│   ├── build-ios.sh           build XCFramework + copy to Frameworks
│   ├── gen-xcodeproj.sh       regenerate .xcodeproj from project.yml
│   ├── build-all.sh           all three above
│   └── dev-web.sh             start wimg-web dev server
│
├── .github/workflows/
│   └── release.yml            CI: check → build-wasm + build-ios → GitHub release
│
├── libwimg/
│   ├── build.zig
│   ├── include/
│   │   └── libwimg.h            C header for iOS bridging
│   ├── vendor/
│   │   └── sqlite3.c           sqlite amalgamation (download once)
│   └── src/
│       ├── root.zig             C ABI exports (+ FinTS native-only exports)
│       ├── db.zig               SQLite wrapper + schema + migrations
│       ├── parser.zig           CSV parsers (Comdirect, TR, Scalable)
│       ├── categories.zig       Keyword rules
│       ├── summary.zig          Calculations
│       ├── types.zig            Shared structs
│       ├── gguf.zig             GGUF v3 file parser
│       ├── quants.zig           Q4_K/Q6_K/Q8_0/F16 dequant + vector math
│       ├── tokenizer.zig        SentencePiece BPE tokenizer (vocab/scores from GGUF)
│       ├── embed.zig            BERT transformer forward pass (12 layers, e5-small)
│       ├── fints.zig            FinTS 3.0 protocol engine (native only)
│       ├── fints_http.zig       HTTPS transport (native only)
│       ├── mt940.zig            MT940 bank statement parser
│       └── banks.zig            German bank list (BLZ + FinTS URLs)
│
├── wimg-web/
│   ├── vite.config.ts           COOP/COEP headers + __APP_VERSION__
│   ├── package.json
│   ├── static/
│   │   ├── libwimg.wasm         compiled WASM binary
│   │   ├── manifest.webmanifest PWA manifest
│   │   └── icon-192/512.png     PWA icons
│   └── src/
│       ├── service-worker.ts    SvelteKit service worker (offline caching)
│       ├── lib/
│       │   ├── wasm.ts          TypeScript wrapper over C ABI + model loading
│       │   ├── sync.ts          Sync orchestrator (push/pull/connect)
│       │   ├── sync-ws.svelte.ts Real-time WebSocket sync store
│       │   ├── config.ts        API URLs (prod/LAN detection)
│       │   ├── features.svelte.ts Feature flags reactive store
│       │   ├── devtools.svelte.ts DevTools store (WASM calls, sync events, actions, diffs, sparkline)
│       │   ├── version.ts       APP_VERSION + GitHub releases link
│       │   ├── update.svelte.ts SW update detection + activation store
│       │   └── toast.svelte.ts  Undo snackbar store
│       ├── routes/
│       │   ├── +page.svelte     redirect → /dashboard
│       │   ├── dashboard/       Verfügbares Einkommen hero, donut, overview
│       │   ├── transactions/    segmented filter, bottom sheet editor
│       │   ├── analysis/        spending breakdown, category drill-down
│       │   ├── debts/           progress bars, mark paid
│       │   ├── import/          file drop, CSV preview, Claude categorization
│       │   ├── review/          monthly review, anomalies, checklist
│       │   ├── settings/        sync config, Claude AI key, embeddings, data reset
│       │   └── about/           about page, FAQ, privacy, MCP info
│       └── components/
│           ├── BottomSheet.svelte   iOS-style sheet (vaul-inspired scale effect)
│           ├── DevTools.svelte      Developer panel (5 tabs: WASM, Memory, Sync, Data, SQL)
│           ├── DonutChart.svelte    LayerChart PieChart wrapper
│           ├── MonthPicker.svelte   month/year selector
│           ├── Toast.svelte         undo snackbar
│           └── UpdateBanner.svelte  PWA update notification banner
│
├── wimg-ios/
│   ├── project.yml              XcodeGen spec (→ xcodegen generate)
│   ├── wimg.xcodeproj           generated, not manually edited
│   ├── Frameworks/
│   │   └── libwimg.xcframework  built by scripts/build-ios.sh
│   └── wimg/
│       ├── wimgApp.swift        entry point + TabView (5 tabs)
│       ├── LibWimg.swift        Swift wrapper over C ABI (+ FinTS methods)
│       ├── wimg-Bridging-Header.h
│       ├── Models/
│       │   ├── Transaction.swift  Transaction, ImportResult, ParseResult
│       │   ├── Summary.swift      MonthlySummary, CategoryBreakdown
│       │   ├── Category.swift     WimgCategory enum (colors, icons)
│       │   ├── Debt.swift
│       │   ├── Snapshot.swift
│       │   └── Notifications.swift
│       ├── Services/
│       │   ├── SyncService.swift  Sync orchestrator + WebSocket client
│       │   └── FeatureFlags.swift Feature flags observable class
│       ├── Views/
│       │   ├── DashboardView.swift
│       │   ├── TransactionsView.swift  + CategoryEditorSheet
│       │   ├── AnalysisView.swift
│       │   ├── ReviewView.swift
│       │   ├── DebtsView.swift    + AddDebtSheet
│       │   ├── ImportView.swift
│       │   ├── SettingsView.swift  Sync config, Claude AI key, data reset
│       │   ├── MoreView.swift     Hub to Debts, Import, Review, Settings, About
│       │   └── AboutView.swift    About page (hero, FAQ, privacy, GitHub)
│       └── Components/
│           ├── MonthPicker.swift
│           ├── TransactionCard.swift  + formatAmountShort()
│           ├── CategoryBadge.swift
│           └── UndoToast.swift
│
└── wimg-sync/                  Phase 4B — Cloudflare Worker + DO + MCP
    ├── wrangler.toml             Worker config, R2 + DO bindings, WASM rule
    ├── package.json              hono + zod
    ├── libwimg-compact.wasm      compact WASM build (small buffers for CF Workers)
    └── src/
        ├── index.ts              Hono router, CORS, sync + MCP routes
        ├── sync-room.ts          SyncRoom DO (WebSocket Hibernation API)
        ├── mcp-session.ts        McpSession DO (WASM lifecycle + MCP handling)
        ├── mcp-wasm.ts           WASM loader for CF Workers (WasmInstance class)
        ├── mcp-tools.ts          20 MCP tool definitions (10 read + 10 write)
        └── wasm.d.ts             TypeScript declaration for .wasm imports
```

---

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
- **Phase 5.5** — Embeddings + Smart Categorization (Done): Pure Zig inference engine (multilingual-e5-small, Q8_0), GGUF parser, SentencePiece BPE tokenizer, 384-dim embeddings, cosine similarity categorization, semantic search
- **Phase 5.8** — Remote MCP Server (Done): 20 tools (10 read + 10 write), E2E encrypted

## In Progress / Future

- **Phase 5.2** — Notifications (deferred, TBD)
- **Phase 5.4** — Annual Renewals Calendar
- **Phase 5.7** — Command Palette + Semantic Search (Cmd+K): fuzzy + vector search across transactions, categories, actions
- **Phase 6.1** — Annual Review ("Geld-Wrapped")
- **Phase 6.2** — Net Worth Over Time
- **Phase 6.3** — Anlage N Assistant (Tax Estimation)
- **Phase 6.4** — Savings Goals

## FinTS Product Registration (Pending)

Required to connect to real German banks. Free, one-time.
Email form to `registrierung@hbci-zka.de`. Not yet submitted.

---

# SQLite Schema

```sql
CREATE TABLE accounts (
  id          TEXT PRIMARY KEY,        -- "comdirect-main", "scalable", etc.
  name        TEXT NOT NULL,           -- "Comdirect Girokonto"
  type        TEXT NOT NULL,           -- checking, investment, savings, cash
  currency    TEXT DEFAULT 'EUR',
  owner       TEXT,                    -- "Komiljon", "Familie", "Kind"
  color       TEXT,                    -- hex, for UI differentiation
  updated_at  INTEGER NOT NULL
);

CREATE TABLE transactions (
  id          TEXT PRIMARY KEY,        -- hash of date+desc+amount+account
  date        TEXT NOT NULL,           -- ISO: 2026-02-14
  description TEXT NOT NULL,
  amount      INTEGER NOT NULL,        -- cents, negative = expense
  currency    TEXT DEFAULT 'EUR',
  category    TEXT,
  account     TEXT REFERENCES accounts(id), -- FK to accounts table
  raw         TEXT,                    -- original CSV row
  updated_at  INTEGER NOT NULL         -- unix ms, last write wins
);

CREATE TABLE categories (
  name        TEXT PRIMARY KEY,
  color       TEXT NOT NULL,           -- hex
  icon        TEXT,                    -- emoji
  updated_at  INTEGER NOT NULL
);

CREATE TABLE debts (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,           -- "WSW Strom", "FOM", "Klarna"
  total       INTEGER NOT NULL,        -- cents
  paid        INTEGER DEFAULT 0,       -- cents
  monthly     INTEGER,                 -- cents, optional
  updated_at  INTEGER NOT NULL
);

CREATE TABLE rules (
  pattern     TEXT NOT NULL,           -- "REWE" → matches description
  category    TEXT NOT NULL,
  priority    INTEGER DEFAULT 0,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE snapshots (
  id          TEXT PRIMARY KEY,        -- "2026-03"
  date        TEXT NOT NULL,           -- "2026-03-01"
  net_worth   INTEGER NOT NULL DEFAULT 0,
  income      INTEGER NOT NULL DEFAULT 0,
  expenses    INTEGER NOT NULL DEFAULT 0,
  tx_count    INTEGER NOT NULL DEFAULT 0,
  breakdown   TEXT NOT NULL DEFAULT '[]',  -- by_category JSON
  updated_at  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE embeddings (
  tx_id       TEXT PRIMARY KEY,            -- FK to transactions.id
  embedding   BLOB NOT NULL,              -- 384 x f32 = 1536 bytes
  model_ver   TEXT NOT NULL DEFAULT 'e5-small-q8',
  updated_at  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE meta (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL
  -- last_sync, schema_version, etc.
);
```

---

# Sync System

## Overview

Row-level sync using `updated_at` columns. Cloudflare Worker + Durable Objects
with WebSocket Hibernation API. Hono router. Last-write-wins per row. No CRDTs.

## How it works

1. User taps "Sync aktivieren" → generates UUID sync key
2. Sync key IS the identity — no signup, no auth
3. Changes pushed via HTTP POST → DO merges to R2 + broadcasts via WebSocket
4. All connected devices receive changes in real-time (~1-2 seconds)

## API

```
POST /sync/:key          — push changed rows (HTTP → DO merges + WS broadcast)
GET  /sync/:key?since=ts — pull rows newer than timestamp
GET  /ws/:key            — WebSocket upgrade → real-time sync via DO
POST /mcp                — MCP JSON-RPC endpoint (Bearer: sync-key)
DELETE /mcp              — Evict MCP session (clear WASM instance)
```

## E2E Encryption

All data encrypted client-side. Key derived from sync key via HKDF-SHA256.
XChaCha20-Poly1305 encrypt/decrypt. Server stores ciphertext only.

## Sync triggers

- Pull on app open
- Push on every local mutation (setOnMutate callback)
- Real-time WebSocket broadcast
- Echo suppression (2-second window after push)
- Full sync on linking new device

## Storage

`r2://wimg-sync/{sync-key}/changes.json` — one JSON blob per sync key.

## MCP Server

McpSession Durable Object inside wimg-sync. Loads libwimg-compact.wasm,
pulls data from R2, decrypts, serves 17 MCP tools (8 read + 9 write).

Claude.ai connector: `URL: https://wimg-sync.mili-my.name/mcp`, `Auth: Bearer <sync-key>`
