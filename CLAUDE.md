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
export fn wimg_parse_csv(ptr: [*]const u8, len: usize) ?[*]const u8
  // returns JSON: { format, total_rows, transactions[] } — preview only, no DB write
export fn wimg_import_csv(ptr: [*]const u8, len: usize) i32
  // returns JSON: { total_rows, imported, skipped_duplicates, errors, format, categorized }

// Transactions
export fn wimg_get_transactions() i32       // returns JSON array
export fn wimg_set_category(id: [*]const u8, id_len: usize, cat: u8) i32
export fn wimg_auto_categorize() i32        // returns count categorized

// Summaries
export fn wimg_get_summary(year: i32, month: i32) i32
  // returns JSON: { year, month, income, expenses, available, tx_count, by_category[] }

// Accounts
export fn wimg_get_accounts() ?[*]const u8  // returns JSON array
export fn wimg_add_account(ptr: [*]const u8, len: usize) i32
export fn wimg_update_account(ptr: [*]const u8, len: usize) i32
export fn wimg_delete_account(id: [*]const u8, id_len: usize) i32

// Debt tracker
export fn wimg_get_debts() i32              // returns JSON array
export fn wimg_add_debt(ptr: [*]const u8, len: usize) i32
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: usize, amount: i64) i32
export fn wimg_delete_debt(id: [*]const u8, id_len: usize) i32

// Undo/Redo
export fn wimg_undo() ?[*]const u8
export fn wimg_redo() ?[*]const u8

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
- [x] Transaction list — grouped by date, card per transaction
- [x] Category editor — tap transaction → change category
- [x] oxfmt + oxlint tooling

#### Success criteria

- [x] Drop real Comdirect CSV → transactions appear in browser
- [x] Change a category → persists after page refresh (OPFS)
- [x] Binary compiles for both `wasm32-freestanding` and `aarch64-apple-macos`

---

### ✅ Phase 2 — Core Features

**Goal:** Actually useful for daily tracking.
**Status: Done (March 2026)**

#### libwimg tasks

- [x] `categories.zig` — keyword rules engine (REWE→Food, DB→Transport)
- [x] `summary.zig` — monthly income / expenses / available / by_category
- [x] `summary.zig` — month-over-month delta calculation
- [x] `debts` table + CRUD (wimg_get_debts, wimg_add_debt, wimg_mark_debt_paid)
- [x] Auto-categorization on import (rules first, Claude API fallback)
- [x] Trade Republic CSV parser (UTF-8, `,` separator, `YYYY-MM-DD`)
- [x] Scalable Capital CSV parser (UTF-8, `;` separator)
- [x] `wimg_parse_csv` — preview CSV without importing
- [x] `wimg_undo` / `wimg_redo` — undo/redo support

#### wimg-web tasks

- [x] Dashboard screen — Verfügbares Einkommen hero, donut chart, budget overview
- [x] Analysis screen — spending breakdown, category drill-down, donut chart
- [x] Debt tracker screen — progress bars, mark paid button, overall progress
- [x] Transaction list — segmented filter (Alle/Ausgaben/Einnahmen), bottom sheet editor
- [x] Import screen — file drop, CSV preview, Claude AI categorization section
- [x] PWA manifest + service worker — installable, fully offline
- [x] Claude API integration (JS-side, not Zig — WASM can't do HTTP)
- [x] LayerChart donut charts (replaced D3)
- [x] German UI labels throughout
- [x] PWA version update system — controlled SW updates, changelog banner, OPFS clear for breaking changes
- [x] Monthly review screen — summary + checklist + anomaly flags

#### Success criteria

- [x] Dashboard shows correct monthly numbers from real data
- [x] Claude API categorizes uncategorized transactions on import
- [x] PWA manifest + service worker registered
- [x] Debt payoff tracker with add/mark-paid/delete
- [x] Works fully offline after first load (service worker caching)
- [x] Monthly review screen

---

### ✅ Phase 3 — SwiftUI iOS App

**Goal:** Same app on iPhone, same data, same libwimg.
**Status: Done (March 2026)**

#### libwimg tasks

- [x] Compile libwimg to `aarch64-apple-ios` and `aarch64-apple-ios-simulator`
- [x] Build XCFramework wrapping libwimg.a (`scripts/build-ios.sh`)
- [x] All C ABI functions work identically on iOS target
- [x] iOS-specific SQLite file path handling (Documents directory)
- [x] C header `libwimg.h` with all exports

#### wimg-ios tasks

- [x] XcodeGen project (`project.yml` → `xcodegen generate`)
- [x] Swift wrapper: `LibWimg.swift` — typed Swift API over C ABI
- [x] Dashboard view (SwiftUI, mirrors wimg-web design)
- [x] Transaction list view with segmented filter + search
- [x] Import view — Files app picker → CSV preview → confirm import
- [x] Category editor sheet
- [x] Debt tracker view with add/pay/delete
- [x] Monthly review view — savings card, anomalies, checklist, stats
- [x] Undo toast after category change and debt actions

#### Build scripts

- [x] `scripts/build-wasm.sh` — build WASM + copy to wimg-web/static
- [x] `scripts/build-ios.sh` — build XCFramework + copy to Frameworks
- [x] `scripts/gen-xcodeproj.sh` — regenerate Xcode project from project.yml
- [x] `scripts/build-all.sh` — all three in sequence
- [x] `scripts/dev-web.sh` — start wimg-web dev server

#### Success criteria

- [x] Runs on iPhone simulator and real device
- [x] Same CSV imported on web and iOS produces identical SQLite state
- [x] All screens functional, friendly fintech design

---

### ✅ Phase 3.5 — Multi-Account Support

**Goal:** Track multiple bank accounts, view together or separately.
**Status: Done (March 2026)**

Real-world use case:

```
Comdirect Girokonto     (main, salary)
Scalable Capital        (ETF investments)
Trade Republic          (older investments)
Shared account          (rent, groceries with partner)
```

#### libwimg tasks

- [x] `accounts` table — CREATE TABLE with id, name, type, currency, owner, color
- [x] Schema migration — add `accounts` table, auto-create default account for existing data
- [x] `wimg_get_accounts`, `wimg_add_account`, `wimg_update_account`, `wimg_delete_account`
- [x] Auto-populate `account` on CSV import (Comdirect → "Comdirect", TR → "Trade Republic", etc.)
- [x] Auto-create account entry on first import of each format
- [x] `wimg_get_transactions` — optional account filter parameter (`wimg_get_transactions_filtered`)
- [x] `wimg_get_summary` — optional account filter parameter (`wimg_get_summary_filtered`)
- [x] Include `account` field in transaction hash (same tx in different accounts = not duplicate)

#### wimg-web tasks

- [x] Account switcher dropdown in nav/header (Alle Konten / single account)
- [x] Account management page — add/edit/delete accounts, set color/owner
- [x] Dashboard filters by selected account
- [x] Transaction list filters by selected account
- [x] Analysis screen filters by selected account
- [x] Import shows which account the CSV will be assigned to

#### wimg-ios tasks

- [x] Account switcher in nav (same pattern as web)
- [x] Account management view
- [x] All screens respect selected account filter

#### Success criteria

- [x] Import Comdirect + TR CSVs → each tagged to correct account
- [x] Dashboard shows "Alle Konten" aggregated by default
- [x] Switch to single account → all numbers/transactions filter correctly
- [x] Manually add accounts (cash, shared, etc.)

---

### Phase 4 — Pure Zig FinTS + Sync

**Goal:** Direct bank connection from native app. No third-party. Data stays on device.
**Time box:** TBD

#### ✅ Phase 4A — Pure Zig FinTS Client (Done, March 2026)

FinTS 3.0 over HTTPS: build text segments → Base64 → HTTP POST to bank.
No AqBanking, no GPL deps, no external libraries. Reference: python-fints source.

- [x] `fints.zig` — FinTS 3.0 message builder + parser + dialog state machine (~570 lines)
      Segments: HNHBK/HNHBS (envelope), HKIDN (auth), HKVVB (product),
      HKTAN/HITAN (TAN flow), HKKAZ/HIKAZ (statements)
- [x] `fints_http.zig` — HTTPS transport via `std.http.Client` (~100 lines)
- [x] `mt940.zig` — MT940 bank statement parser with ?XX subfields + SVWZ+ (~540 lines)
- [x] `banks.zig` — hardcoded list of 24 German banks with FinTS URLs (~130 lines)
- [x] C ABI exports (native only, not WASM):
      `wimg_fints_connect`, `wimg_fints_send_tan`,
      `wimg_fints_fetch`, `wimg_fints_get_banks`
- [x] iOS/macOS: direct FinTS from device via `std.http.Client`
- [x] Web: stays CSV-only (browser can't do FinTS due to CORS)
- [x] iOS FinTSView.swift — bank picker, credentials, TAN challenge, fetch flow
- [x] Swift wrappers in LibWimg.swift + FinTS.swift models
- [x] Integration test: MT940 → DB pipeline (476 total tests passing)
- [ ] photoTAN challenge handling (return image data to caller)
- [ ] FinTS product ID registration (see below)
- [x] Keychain storage for credentials on iOS

#### FinTS Product Registration

Required to connect to real German banks. Free, one-time, shared by all wimg users.

1. Download registration form from https://www.fints.org/de/hersteller/produktregistrierung
2. Fill out:
   - **Firma/Name:** Komiljon Maksudov
   - **Produktbezeichnung:** wimg
   - **Produktkategorie:** Finanzverwaltungssoftware / Mobile App
   - **Kurzbeschreibung:** Persönliche Finanzverwaltung (iOS/Web), FinTS 3.0 Kontoabruf
3. Email to: `registrierung@hbci-zka.de`
4. Wait 5-10 business days → receive 25-char product ID
5. Hardcode product ID in libwimg (all users share it)

**Status:** Not yet submitted

#### ✅ Phase 4B — Real-time Sync (Cloudflare Durable Objects + WebSocket)

**Status: Done (March 2026)**

Row-level sync using existing `updated_at` columns. Cloudflare Worker + Durable
Objects with WebSocket Hibernation API for real-time sync. Hono router for CORS

- routing. Last-write-wins per row. No CRDTs.

##### How it works

1. User taps "Sync aktivieren" → info sheet explains sync → generates UUID sync key
2. Sync key IS the identity — no signup, no auth
3. Changes pushed via HTTP POST → Durable Object merges to R2 + broadcasts via WebSocket
4. All connected devices receive changes in real-time (~1-2 seconds)
5. User pastes/scans QR code on other device → full bidirectional sync

##### Architecture

```
Device A (web/iOS)                    Cloudflare Edge
  │                                     │
  ├─ mutate locally ──────────────────► Worker receives push
  │                                     │
  │                                     ├─► SyncRoom DO (by sync key)
  │                                     │     ├─ merges into R2 (LWW)
  │                                     │     └─ broadcasts to all WS clients
  │                                     │
  │  ◄─── WebSocket message ──────────┘
  │
  └─ applyChanges() + refresh UI
```

##### Sync triggers

- **Pull on app open** — fetch changes from server since last sync
- **Push on mutate** — auto-push after every write (category change, import, debt, undo/redo)
- **Real-time WebSocket** — changes broadcast to all connected devices instantly
- **Echo suppression** — 2-second window ignores own changes echoed back via WS
- **Full sync on link** — bidirectional push + pull when linking a new device

##### Storage

```
r2://wimg-sync/{sync-key}/changes.json
```

Each sync key = one JSON blob in R2. Worker appends rows, returns rows
newer than `since`. 10GB free tier = ~100 users at 100MB each.

##### API

```
POST /sync/:key          — push changed rows (HTTP → DO merges + WS broadcast)
GET  /sync/:key?since=ts — pull rows newer than timestamp
GET  /ws/:key            — WebSocket upgrade → real-time sync via DO
```

##### WebSocket Protocol

```
Client → Server:
  { type: "pong" }                     — heartbeat response

Server → Client:
  { type: "changes", rows: SyncRow[] } — incoming changes from another device
  { type: "ping" }                     — heartbeat (every 30s)
```

##### E2E Encryption (Done, March 2026)

All data encrypted client-side before syncing. Server stores ciphertext only.
Always-on: encryption key derived from sync key via HKDF-SHA256. No separate passphrase.

1. `crypto.zig` — HKDF-SHA256 key derivation + XChaCha20-Poly1305 encrypt/decrypt
2. Key derived from sync key automatically (122 bits of entropy from UUID v4)
3. Entire `data` field encrypted as one blob before POST (base64-encoded)
4. Server can't read data even if compromised
5. Other device pulls, decrypts locally
6. Migration: old plaintext `data` objects pass through (`typeof === 'object'`)

##### Self-hosting

Same API, different backend. Replace Worker + DO with:

```
Go/Zig binary (~200 lines)
├── POST /sync/:key        — store changes in SQLite file per key
├── GET  /sync/:key?since= — return changes since timestamp
└── GET  /ws/:key          — WebSocket for realtime
```

Runs on any $4 VPS. Same client code, zero changes.

##### Cloudflare Pricing (wimg's current stack)

| Service                    | Free Tier                                                     | Paid Tier ($5/mo min)                       |
| -------------------------- | ------------------------------------------------------------- | ------------------------------------------- |
| **Pages** (web hosting)    | Unlimited sites, bandwidth, requests                          | Same + preview deployments, analytics       |
| **Workers** (sync API)     | 100K requests/day, 10ms CPU/request                           | 10M requests/mo, 30M CPU ms/mo, +$0.30/M    |
| **R2** (sync storage)      | 10 GB storage, 1M writes/mo, 10M reads/mo, **no egress fees** | $0.015/GB-mo, $4.50/M writes, $0.36/M reads |
| **Durable Objects** (sync) | 1M requests/mo, 400K GB-s included                            | +$0.15/M requests, $12.50/M GB-s            |
| **CDN**                    | Unlimited bandwidth, free                                     | Same                                        |

**wimg cost estimate:**

- Current (web only, no sync): **$0/mo** — Pages free tier
- With sync (personal use, 2 devices): **$5/mo** — Workers Paid plan required for DOs
- With sync (100 users): **$5/mo** — well within DO free allocation (hibernation = idle DOs cost nothing)
- With sync (1000 users): **~$6.50/mo** — minimal DO overage

Key: R2 has **zero egress fees**. Hibernation API means idle DOs cost nothing.

##### Tasks

- [x] `wimg_get_changes(since_ts)` — C ABI: return rows with updated_at > ts as JSON
- [x] `wimg_apply_changes(json)` — C ABI: merge incoming rows (LWW per updated_at)
- [x] `wimg-sync/` — Cloudflare Worker + Hono router + CORS
- [x] `wimg-sync/src/sync-room.ts` — Durable Object with WebSocket Hibernation API
- [x] `wimg-sync/wrangler.toml` — DO binding + migration
- [x] Sync UI in web app: enable sync, link device, manual sync, copy key, QR code
- [x] Sync UI in iOS app: enable sync, link device, manual sync, copy key
- [x] Real-time WebSocket sync (web: `sync-ws.svelte.ts`, iOS: `SyncService.swift`)
- [x] Auto-push on every local mutation (`setOnMutate` callback)
- [x] Auto-pull on app open + WebSocket reconnect
- [x] Sync info confirmation sheet before key generation
- [x] Echo suppression (2-second window after push)
- [x] Undo/redo sync (bumps `updated_at` in db.zig `applyUpdate`)
- [x] LAN dev support (private network CORS, `wrangler dev --ip 0.0.0.0`)
- [x] `crypto.randomUUID` fallback for non-secure contexts (HTTP on LAN)
- [x] `crypto.zig` — HKDF-SHA256 + XChaCha20-Poly1305 (6 unit tests)
- [x] `wimg_derive_key`, `wimg_encrypt_field`, `wimg_decrypt_field` — C ABI exports
- [x] Web: encrypt on push, decrypt on pull + WS, automatic (no passphrase UI)
- [x] Migration: plaintext objects pass through, encrypted strings get decrypted

#### Success criteria

- [ ] Native app connects to Comdirect via FinTS, fetches real transactions
- [ ] TAN flow works (photoTAN challenge → user enters code → transactions load)
- [ ] Works with multiple German banks (ING, DKB, Commerzbank, etc.)
- [x] Change category on iPhone → appears on web within 1-2 seconds (real-time)
- [x] No data loss on concurrent edits (last-write-wins per row)
- [x] Sync key generated → paste on second device → data appears
- [x] E2E encryption: server stores only ciphertext, key derived from sync key

---

### Phase 5 — Intelligence

**Goal:** Make wimg notice things before you do.
**Time box:** TBD

Core principle: start with pure SQL patterns → add statistics → add embeddings
only when simpler approaches prove insufficient.

#### 5.1 — Recurring Detection + Price Alerts

Pure SQL, no ML. Immediately useful with real data.

##### How it works

```sql
CREATE TABLE recurring_patterns (
  id          TEXT PRIMARY KEY,
  merchant    TEXT NOT NULL,       -- normalized merchant name
  amount      INTEGER NOT NULL,    -- cents (typical amount)
  interval    TEXT NOT NULL,       -- 'monthly', 'weekly', 'annual', 'quarterly'
  category    TEXT,                -- inherited from transactions
  last_seen   TEXT NOT NULL,       -- ISO date of last occurrence
  next_due    TEXT,                -- predicted next date
  active      INTEGER DEFAULT 1,  -- 0 = cancelled/stopped
  updated_at  INTEGER NOT NULL
);
```

- **Detection:** GROUP BY normalized merchant, find transactions with consistent
  intervals (±3 days) and similar amounts (±10%)
- **Price alerts:** compare current amount vs previous occurrence.
  "Netflix: €15.99 → €17.99 (+€2.00)" flagged automatically
- **Predictions:** calculate next expected date based on interval

##### Tasks

- [ ] `recurring.zig` — detect recurring patterns from transaction history (pure SQL)
- [ ] `wimg_detect_recurring()` — C ABI: scan transactions → populate recurring_patterns
- [ ] `wimg_get_recurring()` — C ABI: return active recurring patterns as JSON
- [ ] Price change detection: compare latest vs previous amount per pattern
- [ ] Web: Recurring screen — list of detected subscriptions, price change badges
- [ ] iOS: Recurring view — same layout
- [ ] Run detection on import + manual refresh

#### 5.2 — Notifications

Without notifications, recurring detection is just a screen you forget to open.
This makes wimg proactive.

##### How it works

- **iOS:** `UNUserNotificationCenter` — local push notifications
- **Web:** PWA notifications via service worker (`self.registration.showNotification`)
- **Triggers:**
  - "Netflix went up €2 this month"
  - "Aufenthaltstitel renewal due in 30 days"
  - "Unusual spending: €500 at X (3× your average)"

##### Tasks

- [ ] Notification data model in libwimg (what to notify, when, dedupe)
- [ ] `wimg_get_pending_notifications()` — C ABI: return unread notifications
- [ ] iOS: request notification permission + schedule local notifications
- [ ] Web: PWA notification support via service worker
- [ ] Settings: notification preferences (on/off per type)

#### 5.3 — Data Export + Month Snapshot

Quick wins. Data export should've been Phase 2.

##### Tasks

- [ ] `wimg_export_db()` — C ABI: return full database as JSON dump
- [ ] `wimg_take_snapshot()` — C ABI: freeze monthly state (income, expenses, by_category)
- [ ] `snapshots` table + schema migration (reused by Phase 6 net worth)
- [ ] Web: Export button in Settings → download JSON file
- [ ] iOS: Export via share sheet
- [ ] Auto-snapshot on first app open each month

#### 5.4 — Annual Renewals Calendar

Personal value — track yearly payments and renewal dates.

```sql
-- Extends recurring_patterns with annual items
-- interval = 'annual', next_due = predicted renewal date
-- Examples: Aufenthaltstitel, insurance, domain renewals, annual subscriptions
```

##### Tasks

- [ ] Filter recurring_patterns where interval = 'annual'
- [ ] Calendar view: upcoming renewals in next 30/60/90 days
- [ ] Web: Renewals section on recurring screen (or separate screen)
- [ ] iOS: Renewals view
- [ ] Manual add for non-transaction renewals (Aufenthaltstitel, insurance)

#### 5.5 — Smart Categorization (sqlite-vec)

Only invest here if keyword rules + Claude API prove insufficient.
sqlite-vec is a pure C extension (~300KB), compiles into libwimg.

##### How it works

```sql
CREATE VIRTUAL TABLE tx_embeddings USING vec0(
  transaction_id TEXT PRIMARY KEY,
  embedding      FLOAT[384]       -- all-MiniLM-L6-v2 dimensions
);
```

- Embed transaction descriptions → store in sqlite-vec
- New transaction → find 5 nearest neighbors → inherit majority category
- Works for merchants never seen before, as long as similar ones exist
- Embedding model: all-MiniLM-L6-v2 (~80MB, runs on device via Core ML / WASM)

##### Tasks

- [ ] Compile sqlite-vec into libwimg (C extension, ~300KB)
- [ ] `wimg_embed_transaction(id)` — generate + store embedding
- [ ] `wimg_categorize_by_similarity(id)` — find nearest neighbors → assign category
- [ ] Embedding model integration: Core ML on iOS, Claude API on web (or WASM model)
- [ ] Batch embed existing transactions on first run
- [ ] Benchmark: embedding quality vs keyword rules on real data

#### 5.6 — AI Chat (later)

RAG over your own transactions via sqlite-vec. Only after 5.5 is solid.

##### Tasks

- [ ] `wimg_search_transactions(query_embedding)` — vector search via sqlite-vec
- [ ] Web: chat panel — Claude API with transaction context (RAG)
- [ ] iOS: chat view — Core ML or Claude API
- [ ] Natural language → relevant transactions → LLM summarizes
- [ ] "What did I spend on food in January?" → embed query → find matches → answer

#### 5.7 — Command Palette (Cmd+K)

Spotlight-style command palette for power-user navigation, actions, and search.
Low effort, high polish. Makes wimg feel like a proper tool.

##### What it does

```
Cmd+K (web) opens palette overlay

Navigation
  → Go to Dashboard / Transactions / Analysis / Debts / Import / Settings

Actions
  → Import CSV          (navigates to /import)
  → Add debt            (navigates to /debts with add sheet open)
  → Sync now            (triggers syncFull)
  → Export data         (triggers JSON export)

Search (queries libwimg via WASM)
  → "REWE"    → filtered transactions list inline
  → "March"   → jumps to March summary
  → "Netflix" → shows matching transactions

AI (Phase 5.6 dependency)
  → "Show food spending"              → creates analysis panel
  → "How much did I spend last month?" → opens AI chat
```

##### Tasks

- [ ] Web: `CommandPalette.svelte` — overlay with fuzzy search, keyboard nav
- [ ] Cmd+K / Ctrl+K global shortcut registration
- [ ] Navigation commands (static list, instant)
- [ ] Action commands (trigger functions)
- [ ] Transaction search (calls `wimg_get_transactions_filtered` or client-side filter)
- [ ] Month/summary search (parse month names → navigate to dashboard with month set)
- [ ] iOS: equivalent via `.searchable()` modifier + custom overlay (spotlight-style)

##### iOS equivalent

SwiftUI `.searchable()` modifier + custom sheet overlay. Not cmdk but same
concept — spotlight-style search over your own data. Same commands, native feel.

#### Deferred

- **i18n** — no users yet, one language works. Revisit when needed.
- **ETF tracking** — only if Scalable/TR CSV has depot data worth parsing.

#### Implementation order

```
1. Recurring detection + price alerts    (pure SQL, core value)
2. Notifications (iOS + PWA)             (makes #1 proactive)
3. Data export + month snapshot           (quick wins, foundation for Phase 6)
4. Annual renewals calendar               (personal value, builds on #1)
5. Command palette (Cmd+K)               (low effort, high polish)
6. sqlite-vec + smart categorization     (only if keyword rules insufficient)
7. AI chat                                (only if everything else is solid)
```

#### Success criteria

- [ ] Recurring payments auto-detected from real transaction data
- [ ] Price increase flagged: "Netflix +€2 vs last month"
- [ ] Push notification on iOS when subscription price changes
- [ ] Full database exportable as JSON
- [ ] Monthly snapshots stored for historical comparison
- [ ] Annual renewals visible with upcoming due dates
- [ ] Cmd+K opens command palette with navigation, actions, and search

---

### Phase 6 — Financial Clarity

**Goal:** Turn raw transaction data into actionable financial insights.
**Time box:** TBD

Everything here uses data wimg already collects — no new imports, no new data
sources. Just smarter views on existing data.

#### 6.1 — Annual Review ("Geld-Wrapped")

Spotify Wrapped but for your money. End-of-year (or any-time) summary.

Uses existing `summary.zig` monthly breakdowns, aggregated over 12 months.

##### What it shows

- Total income vs total expenses for the year
- Savings rate (% of income saved)
- Top 5 spending categories (with amounts + trend vs previous year)
- Biggest single expense
- Most frequent merchant
- Month with highest/lowest spending
- Category that grew the most vs previous year
- Shareable card (optional — export as image)

##### Tasks

- [ ] `summary.zig` — `wimg_get_annual_summary(year)` C ABI: aggregate 12 months
- [ ] Return JSON: `{ year, income, expenses, savings_rate, top_categories[], biggest_tx, most_frequent_merchant, best_month, worst_month, category_deltas[] }`
- [ ] Web: Annual Review screen — card-based layout, one insight per card
- [ ] iOS: Annual Review view — same cards, SwiftUI
- [ ] Navigation: accessible from Review tab or Settings

#### 6.2 — Net Worth Over Time

One number that (hopefully) grows. Accounts + investments - debts = net worth.

##### How it works

```sql
CREATE TABLE snapshots (
  id          TEXT PRIMARY KEY,
  date        TEXT NOT NULL,        -- ISO: 2026-03-01 (first of month)
  net_worth   INTEGER NOT NULL,     -- cents
  breakdown   TEXT NOT NULL,        -- JSON: { accounts: {...}, debts: {...} }
  updated_at  INTEGER NOT NULL
);
```

- Auto-snapshot on first app open each month (or manual trigger)
- Net worth = sum of account balances - sum of remaining debts
- Account balances: latest salary deposit or manual entry
- Line chart showing net worth progression over months/years

##### Tasks

- [ ] `snapshots` table + schema migration in `db.zig`
- [ ] `wimg_take_snapshot()` — C ABI: compute + store current net worth
- [ ] `wimg_get_snapshots(since_year)` — C ABI: return snapshot history as JSON
- [ ] Account balance tracking (derived from transactions or manual entry)
- [ ] Web: Net Worth screen — line chart (LayerChart) + breakdown cards
- [ ] iOS: Net Worth view — same layout, SwiftUI Charts
- [ ] Auto-snapshot trigger on app open (once per month)

#### 6.3 — Anlage N Assistant (Tax Estimation)

Estimate your German tax refund from data wimg already has.

"Anlage N" = the tax form for employed income (Nichtselbständige Arbeit).
Every employed person in Germany fills this out. wimg already knows:

- **Salary** — tagged income transactions (Brutto from Gehaltszettel)
- **Werbungskosten** — transactions categorized as:
  - Fahrtkosten (commute — distance × €0.30/km × work days)
  - Homeoffice-Pauschale (€6/day, max €1,260/year)
  - Arbeitsmittel (laptop, desk, monitor — already categorized)
  - Fortbildung (courses, books, certifications)

##### What it does

1. Scan transactions for the tax year → sum Werbungskosten by type
2. Compare against €1,230 Pauschbetrag (if below, no benefit)
3. Apply simplified income tax formula → estimate refund
4. Show: "Geschätzte Erstattung: ~€800" with breakdown

##### What it does NOT do

- No ELSTER submission (that's a different product)
- No Anlage KAP, Anlage V, etc. (investments, rental income)
- No tax advice — just estimation from your own data

##### Tasks

- [ ] `tax.zig` — German income tax formula (Grundtarif / Splittingtarif)
- [ ] `wimg_estimate_tax(year)` — C ABI: scan transactions → compute Werbungskosten → estimate refund
- [ ] Return JSON: `{ year, estimated_refund, werbungskosten_total, breakdown: { fahrtkosten, homeoffice, arbeitsmittel, fortbildung, sonstige }, pauschbetrag_used, effective_tax_rate }`
- [ ] Web: Anlage N screen — refund hero card, Werbungskosten breakdown, tips
- [ ] iOS: Anlage N view — same layout
- [ ] Settings: commute distance (km) + work days/week for Fahrtkosten calculation
- [ ] Category mapping: which wimg categories count as Werbungskosten

#### 6.4 — Savings Goals

Simple progress tracking toward financial goals.

##### How it works

```sql
CREATE TABLE goals (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,        -- "Uzbekistan trip", "Notgroschen"
  target      INTEGER NOT NULL,     -- cents
  saved       INTEGER DEFAULT 0,    -- cents (manual or auto-tracked)
  deadline    TEXT,                  -- ISO date, optional
  icon        TEXT,                  -- emoji
  updated_at  INTEGER NOT NULL
);
```

- Manual: user adds money to goal ("saved €200 this month")
- Auto (optional): track a specific account's balance as goal progress
- Progress bar + "€X left" + "on track" / "behind" indicator

##### Tasks

- [ ] `goals` table + schema migration in `db.zig`
- [ ] `wimg_get_goals`, `wimg_add_goal`, `wimg_update_goal`, `wimg_delete_goal` — C ABI
- [ ] Web: Goals screen — progress bars, add/edit/delete, deadline countdown
- [ ] iOS: Goals view — same layout
- [ ] Optional: auto-link goal to account balance

#### Implementation order

1. **Annual Review** — lowest effort, highest "wow" factor, uses existing summary logic
2. **Savings Goals** — simple CRUD, similar to debts (can reuse patterns)
3. **Net Worth** — needs snapshot mechanism, but straightforward
4. **Anlage N** — most complex (tax formulas), but highest unique value

#### Success criteria

- [ ] Annual review shows meaningful insights from real transaction data
- [ ] Net worth chart shows progression over 3+ months
- [ ] Anlage N estimation within ±€200 of actual ELSTER result
- [ ] Savings goals with progress tracking on both platforms
- [ ] All features work offline (computed in libwimg, no server needed)

---

## Tech Stack

| Layer           | Choice                               | Why                                                   |
| --------------- | ------------------------------------ | ----------------------------------------------------- |
| Shared core     | Zig 0.15.2                           | Single source of truth for all logic                  |
| Storage         | SQLite (amalgamation, compiled in)   | Local, queryable, no deps                             |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart  | Reactive, lightweight, Svelte-native charts           |
| Web persistence | OPFS                                 | SQLite-on-browser, offline, no server                 |
| iOS UI          | SwiftUI                              | Native, links libwimg.a via C ABI                     |
| Sync            | CF Durable Objects + WebSocket + LWW | Real-time, hibernation = cost-efficient               |
| AI              | Claude API (optional, online)        | Categorization + chat                                 |
| FinTS           | Pure Zig (fints.zig + mt940.zig)     | No external deps, native-only, direct bank connection |

---

## File Structure

```
wimg/
├── CHANGELOG.md               auto-generated by release.sh
├── lefthook.yml               pre-commit hooks (zig fmt, oxfmt, oxlint)
├── scripts/
│   ├── release.sh             version bump + changelog + commit + tag
│   ├── build-wasm.sh          build WASM + copy to wimg-web/static
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
│       ├── categories.zig       Rules + Claude API
│       ├── summary.zig          Calculations
│       ├── types.zig            Shared structs
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
│       │   ├── wasm.ts          TypeScript wrapper over C ABI
│       │   ├── claude.ts        Claude API categorization (JS-side)
│       │   ├── sync.ts          Sync orchestrator (push/pull/connect)
│       │   ├── sync-ws.svelte.ts Real-time WebSocket sync store
│       │   ├── config.ts        API URLs (prod/LAN detection)
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
│       │   └── settings/        sync config, Claude AI key, data reset
│       └── components/
│           ├── BottomSheet.svelte   iOS-style sheet (vaul-inspired scale effect)
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
│       │   └── Notifications.swift
│       ├── Services/
│       │   └── SyncService.swift  Sync orchestrator + WebSocket client
│       ├── Views/
│       │   ├── DashboardView.swift
│       │   ├── TransactionsView.swift  + CategoryEditorSheet
│       │   ├── AnalysisView.swift
│       │   ├── ReviewView.swift
│       │   ├── DebtsView.swift    + AddDebtSheet
│       │   ├── ImportView.swift
│       │   ├── SettingsView.swift  Sync config, Claude AI key, data reset
│       │   └── MoreView.swift     Hub to Debts, Import, Review, Settings
│       └── Components/
│           ├── MonthPicker.swift
│           ├── TransactionCard.swift  + formatAmountShort()
│           ├── CategoryBadge.swift
│           └── UndoToast.swift
│
└── wimg-sync/                  Phase 4B — Cloudflare Worker + DO
    ├── wrangler.toml             Worker config, R2 + DO bindings
    └── src/
        ├── index.ts              Hono router, CORS, route to DO
        └── sync-room.ts          Durable Object (WebSocket Hibernation API)
```

---

## Decision Log

| Date     | Decision                                  | Reason                                                                                      |
| -------- | ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| Mar 2026 | Zig as shared core, not Rust              | Already learning Zig, libghostty proves the model                                           |
| Mar 2026 | No Automerge                              | Rust-only, logic still duplicated per platform                                              |
| Mar 2026 | SQLite compiled into libwimg              | One storage engine, same on web + iOS                                                       |
| Mar 2026 | Last-write-wins sync                      | Single user, two devices — CRDT overkill                                                    |
| Mar 2026 | OPFS for web persistence                  | True offline SQLite in browser, no server                                                   |
| Mar 2026 | FinTS via separate wimg-sync binary       | Can't compile AqBanking to WASM                                                             |
| Mar 2026 | Friendly fintech design                   | Light, cards, warm tones, calm                                                              |
| Mar 2026 | LayerChart instead of D3                  | Svelte-native, PieChart component, less boilerplate                                         |
| Mar 2026 | Claude API on JS side, not Zig WASM       | WASM can't make HTTP requests; JS calls Anthropic API directly                              |
| Mar 2026 | COEP `credentialless` not `require-corp`  | `require-corp` breaks Vite HMR WebSocket in dev                                             |
| Mar 2026 | Controlled SW updates (no skipWaiting)    | Users choose when to update; banner shows changelog; OPFS clear for breaking schema changes |
| Mar 2026 | XcodeGen for iOS project                  | Auto-discovers Swift files, no manual pbxproj editing                                       |
| Mar 2026 | Multi-account as Phase 3.5                | Transactions already have `account` column; minimal schema change, big UX win               |
| Mar 2026 | `scripts/release.sh` for versioning       | Single command: bump versions, generate changelog, commit, tag                              |
| Mar 2026 | CI downloads SQLite amalgamation          | sqlite3.c gitignored (9MB); CI fetches from sqlite.org                                      |
| Mar 2026 | `lefthook` pre-commit hooks               | Catch fmt/lint issues before commit (zig fmt, oxfmt, oxlint)                                |
| Mar 2026 | CI tests with `-Doptimize=ReleaseFast`    | sqlite3.c compilation 72s → ~15s in CI                                                      |
| Mar 2026 | Cloudflare R2 for sync storage (Phase 4B) | JSON blob sync, 10GB free, no vendor lock-in risk                                           |
| Mar 2026 | Durable Objects + WebSocket Hibernation   | Real-time sync, one DO per sync key, idle DOs cost nothing                                  |
| Mar 2026 | Hono for Worker routing                   | Lightweight, CORS middleware, clean route handlers                                          |
| Mar 2026 | Echo suppression (2s window) over WS tags | Simple, avoids pusher applying own changes back; no session tracking needed                 |
| Mar 2026 | Wuchale for i18n (Phase 5.1)              | Compile-time, PO files as single source for web + iOS, zero runtime cost                    |

---

## Feature Parity — iOS vs Web

Both platforms are thin shells over the same libwimg C ABI.
FinTS is intentionally iOS-only (browsers can't do FinTS due to CORS).

### At Parity

| Feature                                                     | Web | iOS                    |
| ----------------------------------------------------------- | --- | ---------------------- |
| Dashboard (hero, donut, income/expenses, deltas)            | ✅  | ✅                     |
| Month/year picker                                           | ✅  | ✅                     |
| Transactions (segmented filter, search, grouped by date)    | ✅  | ✅                     |
| Category editor (bottom sheet / modal)                      | ✅  | ✅                     |
| Exclude/include transactions                                | ✅  | ✅                     |
| Undo toast                                                  | ✅  | ✅                     |
| Analysis (donut, category breakdown, deltas)                | ✅  | ✅                     |
| Debts (progress bars, add/pay/delete)                       | ✅  | ✅                     |
| Monthly review (savings, anomalies, checklist)              | ✅  | ✅                     |
| CSV import (Comdirect, TR, Scalable, preview, format badge) | ✅  | ✅                     |
| Rules-based auto-categorization on import                   | ✅  | ✅                     |
| Claude AI categorization (Import post-import)               | ✅  | ✅                     |
| Account switcher + filter all screens                       | ✅  | ✅                     |
| Account management (add/edit/delete, color picker)          | ✅  | ✅ (via AccountPicker) |
| Auto-create account on import                               | ✅  | ✅                     |
| Sync enable / link device / manual sync / copy key          | ✅  | ✅                     |
| Real-time WebSocket sync (auto-push, live receive)          | ✅  | ✅                     |
| E2E encryption (automatic, derived from sync key)           | ✅  | ✅                     |
| Settings: version + GitHub link                             | ✅  | ✅                     |
| More page (hub to Debts, Import, Review, Settings)          | ✅  | ✅                     |

### iOS Missing (needs implementation)

| Feature                               | Web | iOS | Priority |
| ------------------------------------- | --- | --- | -------- |
| Settings: sync key mask/reveal toggle | ✅  | ❌  | Low      |
| Settings: sync QR code display        | ✅  | ❌  | Low      |

### Web Missing

None. Web is the reference implementation.

### Platform-Specific (intentional)

| Feature                              | Platform | Reason                         |
| ------------------------------------ | -------- | ------------------------------ |
| FinTS bank connection                | iOS only | Browsers can't do FinTS (CORS) |
| PWA install + service worker updates | Web only | Native concept                 |
| OPFS persistence                     | Web only | iOS uses file on disk          |

---

## Open Questions

| Question                                        | Answer when                                         |
| ----------------------------------------------- | --------------------------------------------------- |
| WASM + OPFS: SharedArrayBuffer complexity?      | Resolved Phase 1 — works with credentialless COEP   |
| libwimg output buffer size — static or dynamic? | Resolved Phase 1 — static 64KB buffer               |
| Claude API calls from Zig WASM — possible?      | Resolved Phase 2 — No, done on JS side instead      |
| iCloud Drive sync reliability?                  | Resolved Phase 4B — used CF Durable Objects instead |
| App Store distribution of wimg-ios?             | Phase 3 end                                         |
