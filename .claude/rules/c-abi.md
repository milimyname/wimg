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
```

All functions return JSON strings into a caller-provided buffer.
Negative return = error. Caller owns the buffer.

---

## WASM Memory Budget (Two Builds)

Two WASM builds with different memory budgets, controlled by `-Dcompact` in
`build.zig`. Same binary size (~783KB).

**Web app** (default: `zig build --release=small`):

| Source              | File              | Size    |
| ------------------- | ----------------- | ------- |
| `wasm_buf` (FBA)    | `root.zig`        | 64 MB   |
| `mem_storage[4]`    | `wasm_vfs.c`      | 128 MB  |
| `heap`              | `libc_shim.c`     | 16 MB   |
| Stack               | `build.zig`       | 1 MB    |
| **Total**           |                   | ~209 MB |

**MCP/CF Workers** (compact: `zig build --release=small -Dcompact=true`):

| Source              | File              | Size   |
| ------------------- | ----------------- | ------ |
| `wasm_buf` (FBA)    | `root.zig`        | 16 MB  |
| `mem_storage[4]`    | `wasm_vfs.c`      | 32 MB  |
| `heap`              | `libc_shim.c`     | 4 MB   |
| Stack               | `build.zig`       | 1 MB   |
| **Total**           |                   | ~53 MB |
