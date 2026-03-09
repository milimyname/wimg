# wimg Architecture

## Overview

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

## Tech Stack

| Layer           | Choice                               | Why                                                   |
| --------------- | ------------------------------------ | ----------------------------------------------------- |
| Shared core     | Zig 0.15.2                           | Single source of truth for all logic                  |
| Storage         | SQLite 3.52.0 (amalgamation, compiled in) | Local, queryable, no deps                        |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart  | Reactive, lightweight, Svelte-native charts           |
| Web persistence | OPFS                                 | SQLite-on-browser, offline, no server                 |
| iOS UI          | SwiftUI                              | Native, links libwimg.a via C ABI                     |
| Sync            | CF Durable Objects + WebSocket + LWW | Real-time, hibernation = cost-efficient               |
| AI              | Claude API (optional, online)        | Categorization + chat                                 |
| FinTS           | Pure Zig (fints.zig + mt940.zig)     | No external deps, native-only, direct bank connection |
| MCP server      | CF Worker DO + libwimg.wasm + Zod    | Remote MCP via POST /mcp, Bearer auth = sync key     |
