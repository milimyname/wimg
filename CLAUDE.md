# wimg — Roadmap v2

> Local-first personal finance · libwimg (Zig) · Svelte 5 web · SwiftUI iOS

Last updated: March 2026

---

## Vision

One Zig library — **libwimg** — that IS the app. Every platform (web, iOS) is
a thin shell around it. No logic duplication. Same CSV parser, same
categorization, same SQLite queries, everywhere.

Inspired by libghostty: the library is the product. The UIs are just renderers.

---

## Architecture

```
libwimg (Zig)
├── sqlite3.c (amalgamation, compiled in — no external dep)
├── src/
│   ├── root.zig        C ABI exports — the public API
│   ├── db.zig          SQLite wrapper + schema + migrations
│   ├── parser.zig      CSV parsing (Comdirect, Trade Republic, Scalable)
│   ├── categories.zig  Categorization (keyword rules + Claude API)
│   ├── summary.zig     Monthly summaries, debt tracking, goals
│   └── types.zig       Transaction, Category, Summary structs
│
├── → libwimg.wasm      (wasm32-freestanding) ← web
└── → libwimg.a         (aarch64-apple-ios)   ← iOS / macOS

wimg-web  (Svelte 5 + TailwindCSS + LayerChart)
├── loads libwimg.wasm
├── OPFS for SQLite persistence (offline, no server)
├── PWA — installable, works fully offline
├── Claude API (JS-side) for categorization fallback
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
  → categories.zig assigns categories (rules → Claude API fallback)
  → db.zig writes to SQLite (via OPFS on web, file on iOS)
  → root.zig returns JSON to Svelte
  → Svelte renders transaction list
```

### Sync (Phase 4)

Last-write-wins via `updated_at` timestamp on every row.
No CRDTs, no Automerge, no conflict resolution complexity.
One person, two devices — whoever saved last is right.

```sql
-- Every table has this column
updated_at  INTEGER NOT NULL  -- unix ms, last write wins
```

Sync mechanism TBD (iCloud Drive file copy, or simple WebSocket relay).

### Offline

Web: OPFS (Origin Private File System) — SQLite writes directly to a local
browser file. Works offline. Persists across sessions. No server needed.

Requires these headers (Vite dev + production host):
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

iOS: regular file on disk. Always offline-first by nature.

---

## C ABI — libwimg Public API

These are the exact functions both Svelte (via WASM) and Swift (via FFI) call.
Same signatures, same behavior, same SQLite underneath.

```zig
// Lifecycle
export fn wimg_init(db_path: [*:0]const u8) i32
export fn wimg_close() void
export fn wimg_free(ptr: [*]u8, len: usize) void
export fn wimg_alloc(len: usize) ?[*]u8

// Import
export fn wimg_import_csv(ptr: [*]const u8, len: usize) i32
  // returns JSON: { total_rows, imported, skipped_duplicates, errors, format, categorized }

// Transactions
export fn wimg_get_transactions() i32       // returns JSON array
export fn wimg_set_category(id: [*]const u8, id_len: usize, cat: u8) i32

// Summaries
export fn wimg_get_summary(year: i32, month: i32) i32
  // returns JSON: { year, month, income, expenses, available, tx_count, by_category[] }

// Debt tracker
export fn wimg_get_debts() i32              // returns JSON array
export fn wimg_add_debt(ptr: [*]const u8, len: usize) i32
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: usize, amount: i64) i32
export fn wimg_delete_debt(id: [*]const u8, id_len: usize) i32

// Persistence (OPFS)
export fn wimg_get_db_ptr() ?[*]u8
export fn wimg_get_db_size() usize
export fn wimg_restore_db(ptr: [*]const u8, len: usize) i32
```

All functions return JSON strings into a caller-provided buffer.
Negative return = error. Caller owns the buffer.

---

## SQLite Schema

```sql
CREATE TABLE transactions (
  id          TEXT PRIMARY KEY,        -- hash of date+desc+amount
  date        TEXT NOT NULL,           -- ISO: 2026-02-14
  description TEXT NOT NULL,
  amount      INTEGER NOT NULL,        -- cents, negative = expense
  currency    TEXT DEFAULT 'EUR',
  category    TEXT,
  account     TEXT,
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

CREATE TABLE meta (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL
  -- last_sync, schema_version, etc.
);
```

---

## Phases

---

### ✅ Phase 0 — Zig Fundamentals
**Status: Done (March 2026)**

- [x] Basic syntax, types, comptime
- [x] Error handling
- [x] Memory management (allocators)
- [x] Structs, enums, tagged unions
- [x] File I/O
- [x] C interop basics

---

### ✅ Phase 1 — libwimg MVP + Web Shell
**Status: Done (March 2026)**

#### libwimg tasks
- [x] `build.zig` — compile libwimg + sqlite3.c to WASM (657KB release)
- [x] `types.zig` — Transaction, ImportResult structs
- [x] `db.zig` — SQLite init, schema creation, basic insert/query
- [x] `parser.zig` — Comdirect CSV parser (ISO-8859-1, `;` separator, `dd.MM.yyyy`)
- [x] `root.zig` — `wimg_init`, `wimg_import_csv`, `wimg_get_transactions`, `wimg_set_category`
- [x] Duplicate detection (hash of date+desc+amount as primary key)
- [x] JSON serialization of Transaction slice into caller buffer
- [x] Custom in-memory VFS (`wasm_vfs.c`) + libc shim (`libc_shim.c`)

#### wimg-web tasks
- [x] Vite + Svelte 5 + TailwindCSS v4 scaffold
- [x] OPFS setup + COEP/COOP headers via hooks.server.ts
- [x] `wasm.ts` — load libwimg.wasm, wrap exports with typed TS functions
- [x] Import screen — file drop → call `wimg_import_csv` → show result
- [x] Transaction list — grouped by date, card per transaction (Finanzguru style)
- [x] Category editor — tap transaction → change category
- [x] oxfmt + oxlint tooling

#### Success criteria
- [x] Drop real Comdirect CSV → transactions appear in browser
- [x] Change a category → persists after page refresh (OPFS)
- [x] Binary compiles for both `wasm32-freestanding` and `aarch64-apple-macos`

---

### Phase 2 — Core Features
**Goal:** Actually useful for daily tracking.
**Status: In Progress (March 2026)**

#### libwimg tasks
- [x] `categories.zig` — keyword rules engine (REWE→Food, DB→Transport)
- [x] `summary.zig` — monthly income / expenses / available / by_category
- [x] `summary.zig` — month-over-month delta calculation
- [x] `debts` table + CRUD (wimg_get_debts, wimg_add_debt, wimg_mark_debt_paid)
- [ ] Auto-categorization on import (rules first, Claude API fallback)
- [ ] Trade Republic CSV parser (UTF-8, `,` separator, `YYYY-MM-DD`)
- [ ] Scalable Capital CSV parser (UTF-8, `;` separator)

#### wimg-web tasks
- [x] Dashboard screen — Verfügbares Einkommen hero, donut chart, budget overview
- [x] Analysis screen — spending breakdown, category drill-down, donut chart
- [x] Debt tracker screen — progress bars, mark paid button, overall progress
- [x] Transaction list — segmented filter (Alle/Ausgaben/Einnahmen), bottom sheet editor
- [x] Import screen — file drop, Claude AI categorization section
- [x] PWA manifest + service worker — installable, fully offline
- [x] Claude API integration (JS-side, not Zig — WASM can't do HTTP)
- [x] LayerChart donut charts (replaced D3)
- [x] German UI labels throughout (Finanzguru-inspired)
- [x] PWA version update system — controlled SW updates, changelog banner, OPFS clear for breaking changes
- [ ] Monthly review screen — summary + checklist + anomaly flags

#### Success criteria
- [x] Dashboard shows correct monthly numbers from real data
- [x] Claude API categorizes uncategorized transactions on import
- [x] PWA manifest + service worker registered
- [x] Debt payoff tracker with add/mark-paid/delete
- [ ] Works fully offline after first load (service worker caching)
- [ ] Monthly review screen

---

### Phase 3 — SwiftUI iOS App
**Goal:** Same app on iPhone, same data, same libwimg.
**Time box:** 4 weekends

#### libwimg tasks
- [ ] Compile libwimg to `aarch64-apple-ios` and `x86_64-apple-ios-simulator`
- [ ] Build XCFramework wrapping libwimg.a
- [ ] Ensure all C ABI functions work identically on iOS target
- [ ] iOS-specific SQLite file path handling (Documents directory)

#### wimg-ios tasks
- [ ] Xcode project, link libwimg XCFramework
- [ ] Swift wrapper: `LibWimg.swift` — typed Swift API over C ABI
- [ ] Dashboard view (SwiftUI, mirrors wimg-web design)
- [ ] Transaction list view
- [ ] Import view — Files app picker → CSV → libwimg
- [ ] Category editor sheet
- [ ] Debt tracker view
- [ ] Monthly review view

#### Success criteria
- [ ] Runs on iPhone simulator and real device
- [ ] Same CSV imported on web and iOS produces identical SQLite state
- [ ] All screens functional, Finanzguru-inspired design

---

### Phase 4 — Sync + FinTS
**Goal:** Data follows you across devices. Comdirect auto-import.
**Time box:** TBD

#### Sync
- [ ] Export/import wimg.db as file (manual sync via iCloud Drive)
- [ ] Last-write-wins merge: compare `updated_at`, keep higher
- [ ] `wimg_merge(other_db_bytes, len)` — C ABI function for merge
- [ ] iCloud Drive integration in Swift (automatic file sync)
- [ ] Optional: lightweight WebSocket relay for web ↔ iOS push sync

#### FinTS / AqBanking (Zig native binary, not WASM)
- [ ] Separate `wimg-sync` Zig binary (not libwimg — can't WASM this)
- [ ] AqBanking C interop (`libaqbanking-dev`, `libgwenhywfar-dev`)
- [ ] Comdirect FinTS connection + photoTAN flow
- [ ] Fetch transactions → write directly to wimg.db
- [ ] Run as background daemon or on-demand CLI

```
wimg-sync (Zig binary, runs on desktop/server)
  → fetches from Comdirect via FinTS/AqBanking
  → writes to wimg.db
  → wimg-web and wimg-ios pick up via iCloud sync
```

#### Success criteria
- [ ] Change category on iPhone → appears on web after sync
- [ ] wimg-sync fetches last 30 days from Comdirect automatically
- [ ] No data loss on concurrent edits (last-write-wins)

---

### Phase 5 — Intelligence + Polish
**Goal:** Make wimg proactively useful.
**Time box:** TBD

- [ ] Recurring payment detection (same amount + merchant ± 3 days)
- [ ] Price increase alerts ("Netflix +3€ vs last month")
- [ ] Annual renewals calendar (Aufenthaltstitel, insurance, etc.)
- [ ] AI chat panel (Claude API, natural language → SQL → chart)
- [ ] Data export — JSON dump of full database
- [ ] Month snapshot — freeze monthly state for historical comparison
- [ ] ETF / investment tracking (Trade Republic depot data)

---

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Shared core | Zig 0.15.2 | Single source of truth for all logic |
| Storage | SQLite (amalgamation, compiled in) | Local, queryable, no deps |
| Web UI | Svelte 5 + TailwindCSS + LayerChart | Reactive, lightweight, Svelte-native charts |
| Web persistence | OPFS | SQLite-on-browser, offline, no server |
| iOS UI | SwiftUI | Native, links libwimg.a via C ABI |
| Sync | Last-write-wins on `updated_at` | Simple, correct for single user |
| AI | Claude API (optional, online) | Categorization + chat |
| FinTS | AqBanking C lib → wimg-sync binary | Comdirect auto-import |

---

## File Structure

```
wimg/
├── libwimg/
│   ├── build.zig
│   ├── vendor/
│   │   └── sqlite3.c          sqlite amalgamation (download once)
│   └── src/
│       ├── root.zig            C ABI exports
│       ├── db.zig              SQLite wrapper
│       ├── parser.zig          CSV parsers
│       ├── categories.zig      Rules + Claude API
│       ├── summary.zig         Calculations
│       └── types.zig           Shared structs
│
├── wimg-web/
│   ├── vite.config.ts          COOP/COEP headers
│   ├── package.json
│   ├── static/
│   │   ├── libwimg.wasm         compiled WASM binary
│   │   ├── manifest.webmanifest PWA manifest
│   │   ├── sw.js                service worker
│   │   └── icon-192/512.png     PWA icons
│   └── src/
│       ├── lib/
│       │   ├── wasm.ts          TypeScript wrapper over C ABI
│       │   ├── claude.ts        Claude API categorization (JS-side)
│       │   ├── version.ts       APP_VERSION + CHANGELOG registry
│       │   └── update.svelte.ts SW update detection + activation store
│       ├── routes/
│       │   ├── +page.svelte     redirect → /dashboard
│       │   ├── dashboard/       Verfügbares Einkommen hero, donut, overview
│       │   ├── transactions/    segmented filter, bottom sheet editor
│       │   ├── analysis/        spending breakdown, category drill-down
│       │   ├── debts/           progress bars, mark paid
│       │   └── import/          file drop, Claude categorization
│       └── components/
│           ├── DonutChart.svelte    LayerChart PieChart wrapper
│           ├── MonthPicker.svelte   month/year selector
│           └── UpdateBanner.svelte  PWA update notification banner
│
├── wimg-ios/                   Phase 3
│   ├── wimg.xcodeproj
│   ├── LibWimg.swift           Swift wrapper over C ABI
│   └── Views/
│       ├── DashboardView.swift
│       ├── TransactionsView.swift
│       └── ImportView.swift
│
└── wimg-sync/                  Phase 4
    ├── build.zig
    └── src/
        └── main.zig            FinTS via AqBanking → wimg.db
```

---

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| Mar 2026 | Zig as shared core, not Rust | Already learning Zig, libghostty proves the model |
| Mar 2026 | No Automerge | Rust-only, logic still duplicated per platform |
| Mar 2026 | SQLite compiled into libwimg | One storage engine, same on web + iOS |
| Mar 2026 | Last-write-wins sync | Single user, two devices — CRDT overkill |
| Mar 2026 | OPFS for web persistence | True offline SQLite in browser, no server |
| Mar 2026 | FinTS via separate wimg-sync binary | Can't compile AqBanking to WASM |
| Mar 2026 | Finanzguru-inspired design | Light, cards, pastel categories, calm |
| Mar 2026 | LayerChart instead of D3 | Svelte-native, PieChart component, less boilerplate |
| Mar 2026 | Claude API on JS side, not Zig WASM | WASM can't make HTTP requests; JS calls Anthropic API directly |
| Mar 2026 | COEP `credentialless` not `require-corp` | `require-corp` breaks Vite HMR WebSocket in dev |
| Mar 2026 | Controlled SW updates (no skipWaiting) | Users choose when to update; banner shows changelog; OPFS clear for breaking schema changes |

---

## Open Questions

| Question | Answer when |
|----------|-------------|
| WASM + OPFS: SharedArrayBuffer complexity? | Resolved Phase 1 — works with credentialless COEP |
| libwimg output buffer size — static or dynamic? | Resolved Phase 1 — static 64KB buffer |
| Claude API calls from Zig WASM — possible? | Resolved Phase 2 — No, done on JS side instead |
| iCloud Drive sync reliability? | Phase 4 |
| App Store distribution of wimg-ios? | Phase 3 end |

