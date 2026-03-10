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
