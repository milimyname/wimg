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
- [ ] iOS FinTSView.swift — bank picker, credentials, TAN challenge, fetch flow (not yet implemented)
- [x] Swift wrappers in LibWimg.swift + FinTS.swift models
- [x] Integration test: MT940 → DB pipeline (476 total tests passing)
- [ ] photoTAN challenge handling (return image data to caller)
- [ ] FinTS product ID registration (see below)
- [ ] Keychain storage for credentials on iOS

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

##### E2E Encryption (planned)

All data encrypted client-side before syncing. Server stores ciphertext only.

1. User sets a passphrase on both devices (once)
2. Derive encryption key with PBKDF2/Argon2
3. `description`, `amount`, `raw` fields encrypted before POST
4. Server can't read data even if compromised
5. Other device pulls, decrypts locally

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
- [ ] `wimg_encrypt_field(plaintext, key)` — C ABI: AES-256 encrypt before sync
- [ ] `wimg_decrypt_field(ciphertext, key)` — C ABI: decrypt after pull

#### Success criteria

- [ ] Native app connects to Comdirect via FinTS, fetches real transactions
- [ ] TAN flow works (photoTAN challenge → user enters code → transactions load)
- [ ] Works with multiple German banks (ING, DKB, Commerzbank, etc.)
- [x] Change category on iPhone → appears on web within 1-2 seconds (real-time)
- [x] No data loss on concurrent edits (last-write-wins per row)
- [x] Sync key generated → paste on second device → data appears
- [ ] E2E encryption: server stores only ciphertext, passphrase never leaves device

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
- [ ] i18n — multi-language support (see Phase 5.1 below)

---

### Phase 5.1 — i18n (Internationalization)

**Goal:** Multi-language support with one source of truth for all platforms.
**Time box:** TBD

Using [Wuchale](https://wuchale.dev/) — compile-time i18n toolkit for JavaScript.

##### How it works

1. **German stays as-is** — all existing Svelte/Swift code keeps hardcoded German text
2. **Wuchale extracts** translatable strings from Svelte components into PO files (Gettext)
3. **Translators edit PO files** — standard format, supported by Crowdin/Weblate/POEdit
4. **Compile-time transform** — translations become indexed arrays (smallest bundles, zero runtime overhead)
5. **iOS gets `.strings`** — a script converts the same PO files → Apple `Localizable.strings`

##### Architecture — one source of truth

```
wimg/
├── locales/
│   ├── de.po          ← source language (German, auto-extracted)
│   ├── en.po          ← English translations
│   └── tr.po          ← additional languages
├── scripts/
│   └── po-to-strings.sh  ← PO → iOS .strings converter
├── wimg-web/           ← Wuchale Svelte plugin reads PO at build time
└── wimg-ios/
    └── wimg/*.lproj/Localizable.strings  ← generated from PO
```

- **Web**: Wuchale Svelte plugin compiles PO → indexed arrays at build time
- **iOS**: SwiftUI `Text("German string")` auto-looks up in `.strings` files per locale
- **Zig (libwimg)**: No changes needed — returns raw data, no UI strings

##### Why Wuchale

- No code changes required — extracts from existing German text
- Compile-time = zero runtime cost, smallest bundles
- PO is the most widely supported translation format
- Works with Svelte 5

##### Tasks

- [ ] Install Wuchale Svelte plugin, configure in `vite.config.ts`
- [ ] Run initial extraction → `locales/de.po` (German source)
- [ ] Create `locales/en.po` with English translations
- [ ] Write `scripts/po-to-strings.sh` (PO → Apple `.strings`)
- [ ] Add `*.lproj/` directories to wimg-ios
- [ ] Verify SwiftUI picks up translations by device locale
- [ ] Add locale switcher in Settings (web + iOS)
- [ ] CI: validate PO files have no missing translations

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
| Settings: encryption passphrase (placeholder)               | ✅  | ✅                     |
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

| Feature                              | Platform | Reason                                           |
| ------------------------------------ | -------- | ------------------------------------------------ |
| FinTS bank connection                | iOS only | Browsers can't do FinTS (CORS); UI not yet built |
| PWA install + service worker updates | Web only | Native concept                                   |
| OPFS persistence                     | Web only | iOS uses file on disk                            |

---

## Open Questions

| Question                                        | Answer when                                         |
| ----------------------------------------------- | --------------------------------------------------- |
| WASM + OPFS: SharedArrayBuffer complexity?      | Resolved Phase 1 — works with credentialless COEP   |
| libwimg output buffer size — static or dynamic? | Resolved Phase 1 — static 64KB buffer               |
| Claude API calls from Zig WASM — possible?      | Resolved Phase 2 — No, done on JS side instead      |
| iCloud Drive sync reliability?                  | Resolved Phase 4B — used CF Durable Objects instead |
| App Store distribution of wimg-ios?             | Phase 3 end                                         |
