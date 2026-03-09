# Decision Log

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
| Mar 2026 | Cloudflare R2 for sync storage            | JSON blob sync, 10GB free, no vendor lock-in risk                                           |
| Mar 2026 | Durable Objects + WebSocket Hibernation   | Real-time sync, one DO per sync key, idle DOs cost nothing                                  |
| Mar 2026 | Hono for Worker routing                   | Lightweight, CORS middleware, clean route handlers                                          |
| Mar 2026 | Echo suppression (2s window) over WS tags | Simple, avoids pusher applying own changes back; no session tracking needed                 |
| Mar 2026 | Remote MCP in wimg-sync, not local        | CF Worker DO keeps WASM warm, no local Bun process needed, accessible from Claude.ai       |
| Mar 2026 | Manual JSON-RPC over MCP SDK              | MCP protocol is simple JSON-RPC; avoids Node.js deps in CF Workers, keeps bundle small      |
| Mar 2026 | Feature flags via localStorage/UserDefaults | Simple toggles, no plugin runtime; features compiled in, flags control UI visibility only  |
| Mar 2026 | Two WASM builds (`-Dcompact` flag)        | Web app gets large buffers (209MB), MCP/CF Workers gets compact (53MB)                      |
| Mar 2026 | MCP Streamable HTTP (protocol `2025-03-26`) | Claude Desktop requires Streamable HTTP; session ID via `Mcp-Session-Id` header           |
| Mar 2026 | SQLite 3.52.0                             | WAL corruption fix, query planner improvements, float precision                             |
| Mar 2026 | DevTools via `?devtools` URL param        | Enables prod debugging; `devtoolsEnabled` boolean flag = zero overhead when off             |
| Mar 2026 | `config` module for all Zig targets       | `root.zig` imports `config` unconditionally; native builds get `compact=false` default      |
