const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const db_mod = @import("db.zig");
const parser = @import("parser.zig");
const categories = @import("categories.zig");
const summary = @import("summary.zig");
const crypto = @import("crypto.zig");
const recurring = @import("recurring.zig");

const Db = db_mod.Db;
const Transaction = types.Transaction;
const ImportResult = types.ImportResult;

const is_wasm = builtin.cpu.arch == .wasm32;

// FinTS modules — native only (WASM can't do HTTPS)
const fints_mod = if (!is_wasm) @import("fints.zig") else struct {};
const fints_http_mod = if (!is_wasm) @import("fints_http.zig") else struct {};
const mt940_mod = if (!is_wasm) @import("mt940.zig") else struct {};
const banks_mod = if (!is_wasm) @import("banks.zig") else struct {};

// --- JS interop: imported logging function (WASM only) ---
extern fn js_console_log(ptr: [*]const u8, len: u32) void;

// --- Error reporting ---
var error_buf: [512]u8 = undefined;
var error_len: u32 = 0;

fn setError(comptime fmt: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(&error_buf, fmt, args) catch {
        const msg = "error: format failed";
        @memcpy(error_buf[0..msg.len], msg);
        error_len = msg.len;
        return;
    };
    error_len = @intCast(slice.len);
    if (is_wasm) {
        js_console_log(&error_buf, error_len);
    }
}

fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    if (is_wasm) {
        js_console_log(&buf, @intCast(slice.len));
    }
}

// --- WASM memory management ---
var wasm_buf: [64 * 1024 * 1024]u8 = undefined; // 64 MB scratch — virtual, zero cost until touched
var fba = std.heap.FixedBufferAllocator.init(&wasm_buf);

// Global database instance
var global_db: ?Db = null;

// --- C ABI Exports ---

/// Get the last error message. Returns pointer to error string.
/// First 4 bytes = u32 length, then the string data.
export fn wimg_get_error() ?[*]const u8 {
    if (error_len == 0) return null;

    const out = fba.allocator().alloc(u8, error_len + 4) catch return null;
    const len_bytes: [4]u8 = @bitCast(error_len);
    out[0] = len_bytes[0];
    out[1] = len_bytes[1];
    out[2] = len_bytes[2];
    out[3] = len_bytes[3];
    @memcpy(out[4 .. 4 + error_len], error_buf[0..error_len]);
    return out.ptr;
}

/// Initialize the database. Returns 0 on success, -1 on error.
export fn wimg_init(path: [*:0]const u8) i32 {
    log("wimg_init called", .{});

    if (global_db != null) {
        global_db.?.close();
    }

    global_db = Db.init(path) catch |err| {
        setError("wimg_init: db.init failed: {s}", .{@errorName(err)});
        return -1;
    };

    log("wimg_init: database initialized successfully", .{});
    return 0;
}

/// Import a CSV file. Auto-detects format. Returns a pointer to a JSON string
/// with the import result, or null on error.
export fn wimg_import_csv(data: [*]const u8, len: u32) ?[*]const u8 {
    log("wimg_import_csv: len={d}", .{len});

    var database = global_db orelse {
        setError("wimg_import_csv: database not initialized", .{});
        return null;
    };

    const csv_data = data[0..len];

    // Batch-parse CSV into transactions (10K buffer reused per batch)
    const max_txns = 10000;
    const txn_buf = fba.allocator().alloc(Transaction, max_txns) catch {
        setError("wimg_import_csv: failed to allocate transaction buffer", .{});
        return null;
    };
    defer fba.allocator().free(txn_buf);

    var cursor = parser.ParseCursor{};
    var result = ImportResult{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };
    var categorized: u32 = 0;
    var account_created = false;

    while (cursor.byte_offset < csv_data.len) {
        var batch_result: ImportResult = undefined;
        parser.parseCsvBatch(csv_data, &cursor, txn_buf, &batch_result);

        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;

        // Insert batch into DB
        var batch_imported: u32 = 0;
        var batch_duplicates: u32 = 0;
        var batch_insert_errors: u32 = 0;

        for (txn_buf[0..batch_result.imported]) |*txn| {
            const inserted = database.insertTransaction(txn) catch |err| {
                batch_insert_errors += 1;
                if (result.errors + batch_insert_errors <= 3) {
                    setError("wimg_import_csv: insert failed: {s}", .{@errorName(err)});
                }
                continue;
            };
            if (inserted) {
                batch_imported += 1;
            } else {
                batch_duplicates += 1;
            }
        }

        // Auto-categorize this batch
        for (txn_buf[0..batch_result.imported]) |*txn| {
            if (txn.category != .uncategorized) continue;
            const matched = categories.matchRules(database.handle, txn.descriptionSlice());
            if (matched != .uncategorized) {
                database.setCategoryById(&txn.id, matched) catch continue;
                categorized += 1;
            }
        }

        // Accumulate totals
        result.total_rows += batch_result.total_rows;
        result.imported += batch_imported;
        result.skipped_duplicates += batch_duplicates;
        result.errors += batch_result.errors + batch_insert_errors;
    }

    const format = cursor.format;

    // Auto-create account entry for this bank format (once)
    if (!account_created) {
        const account_info = accountInfoForFormat(format);
        database.ensureAccount(account_info.id, account_info.name, account_info.color) catch {};
        account_created = true;
    }

    log("wimg_import_csv: format={s}, {d} imported, {d} duplicates, {d} errors, {d} auto-categorized", .{
        format.name(), result.imported, result.skipped_duplicates, result.errors, categorized,
    });

    // Serialize result to JSON (with format and categorized count)
    var json_buf: [512]u8 = undefined;
    const json_len = formatImportResultEx(&json_buf, &result, format, categorized) orelse {
        setError("wimg_import_csv: failed to format result JSON", .{});
        return null;
    };

    return makeLengthPrefixed(json_buf[0..json_len]);
}

/// Parse CSV without importing into the database (preview only).
/// Returns a length-prefixed JSON string with format, total_rows, and transactions array.
export fn wimg_parse_csv(data: [*]const u8, len: u32) ?[*]const u8 {
    log("wimg_parse_csv: len={d}", .{len});

    const csv_data = data[0..len];

    const max_txns = 2000;
    const txn_buf = fba.allocator().alloc(Transaction, max_txns) catch {
        setError("wimg_parse_csv: failed to allocate transaction buffer", .{});
        return null;
    };
    defer fba.allocator().free(txn_buf);

    var result: ImportResult = undefined;
    const format = parser.parseCsv(csv_data, txn_buf, &result);

    log("wimg_parse_csv: format={s}, parsed {d} rows, {d} transactions", .{
        format.name(), result.total_rows, result.imported,
    });

    // Apply rule-based categorization (preview includes predicted categories)
    if (global_db) |database| {
        for (txn_buf[0..result.imported]) |*txn| {
            if (txn.category != .uncategorized) continue;
            const matched = categories.matchRules(database.handle, txn.descriptionSlice());
            if (matched != .uncategorized) {
                txn.category = matched;
            }
        }
    }

    // Serialize to JSON using manual building (same pattern as db.zig)
    const buf_size: usize = 1024 * 1024; // 1 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_parse_csv: failed to allocate output buffer", .{});
        return null;
    };

    var pos: usize = 4; // skip length prefix
    const out = buf[4..];

    // Header: {"format":"...","total_rows":N,"transactions":[
    const hdr = std.fmt.bufPrint(out, "{{\"format\":\"{s}\",\"total_rows\":{d},\"transactions\":[", .{
        format.name(), result.total_rows,
    }) catch {
        setError("wimg_parse_csv: failed to format header", .{});
        fba.allocator().free(buf);
        return null;
    };
    pos += hdr.len;

    // Write each transaction using db.zig helpers
    for (txn_buf[0..result.imported], 0..) |*txn, i| {
        const s = buf[pos .. buf_size + 4];
        const written = formatPreviewTransaction(
            s,
            i == 0,
            &txn.id,
            txn.date.year,
            txn.date.month,
            txn.date.day,
            txn.descriptionSlice(),
            txn.amount_cents,
            &txn.currency,
            @intFromEnum(txn.category),
            txn.accountSlice(),
        ) orelse {
            setError("wimg_parse_csv: buffer overflow at transaction {d}", .{i});
            fba.allocator().free(buf);
            return null;
        };
        pos += written;
    }

    // Close: ]}
    if (pos + 2 > buf_size + 4) {
        fba.allocator().free(buf);
        return null;
    }
    buf[pos] = ']';
    buf[pos + 1] = '}';
    pos += 2;

    const json_len = pos - 4;
    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Format a single transaction as JSON for the preview response.
/// Reuses db.zig helpers for amount formatting and JSON escaping.
fn formatPreviewTransaction(
    buf: []u8,
    first: bool,
    id: *const [32]u8,
    year: u16,
    month: u8,
    day: u8,
    desc: []const u8,
    amount_cents: i64,
    currency: *const [3]u8,
    category: u8,
    account: []const u8,
) ?usize {
    var pos: usize = 0;

    if (!first) {
        if (pos >= buf.len) return null;
        buf[pos] = ',';
        pos += 1;
    }

    // {"id":"
    const p1 = "{\"id\":\"";
    if (pos + p1.len + 32 > buf.len) return null;
    @memcpy(buf[pos .. pos + p1.len], p1);
    pos += p1.len;
    @memcpy(buf[pos .. pos + 32], id);
    pos += 32;

    // ","date":"YYYY-MM-DD"
    const p2 = "\",\"date\":\"";
    if (pos + p2.len + 10 > buf.len) return null;
    @memcpy(buf[pos .. pos + p2.len], p2);
    pos += p2.len;
    // Manual date formatting
    buf[pos] = '0' + @as(u8, @intCast(year / 1000));
    buf[pos + 1] = '0' + @as(u8, @intCast((year / 100) % 10));
    buf[pos + 2] = '0' + @as(u8, @intCast((year / 10) % 10));
    buf[pos + 3] = '0' + @as(u8, @intCast(year % 10));
    buf[pos + 4] = '-';
    buf[pos + 5] = '0' + month / 10;
    buf[pos + 6] = '0' + month % 10;
    buf[pos + 7] = '-';
    buf[pos + 8] = '0' + day / 10;
    buf[pos + 9] = '0' + day % 10;
    pos += 10;

    // ","description":"
    const p3 = "\",\"description\":\"";
    if (pos + p3.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p3.len], p3);
    pos += p3.len;
    pos += db_mod.jsonEscapeString(buf[pos..], desc) orelse return null;

    // ","amount":
    const p4 = "\",\"amount\":";
    if (pos + p4.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p4.len], p4);
    pos += p4.len;
    pos += db_mod.formatAmount(buf[pos..], amount_cents) orelse return null;

    // ,"currency":"EUR"
    const p5 = ",\"currency\":\"";
    if (pos + p5.len + 3 > buf.len) return null;
    @memcpy(buf[pos .. pos + p5.len], p5);
    pos += p5.len;
    @memcpy(buf[pos .. pos + 3], currency);
    pos += 3;

    // ","category":N
    const p6 = "\",\"category\":";
    if (pos + p6.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p6.len], p6);
    pos += p6.len;
    pos += db_mod.formatInt(buf[pos..], category) orelse return null;

    // ,"account":"..."
    const p7 = ",\"account\":\"";
    if (pos + p7.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p7.len], p7);
    pos += p7.len;
    pos += db_mod.jsonEscapeString(buf[pos..], account) orelse return null;

    const p8 = "\"}";
    if (pos + p8.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p8.len], p8);
    pos += p8.len;

    return pos;
}

/// Re-run auto-categorization on all uncategorized transactions.
/// Returns number of newly categorized transactions, or -1 on error.
export fn wimg_auto_categorize() i32 {
    var database = global_db orelse {
        setError("wimg_auto_categorize: database not initialized", .{});
        return -1;
    };

    const sql =
        \\SELECT id, description FROM transactions WHERE category = 0;
    ;

    var stmt: ?*@import("sqlite_c.zig").sqlite3_stmt = null;
    const c = @import("sqlite_c.zig");
    const rc = c.sqlite3_prepare_v2(database.handle, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK or stmt == null) return -1;
    defer _ = c.sqlite3_finalize(stmt.?);

    const s = stmt.?;
    var count: i32 = 0;

    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const desc_ptr = c.sqlite3_column_text(s, 1) orelse continue;
        const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));

        const matched = categories.matchRules(database.handle, desc_ptr[0..desc_len]);
        if (matched != .uncategorized) {
            const id_slice: *const [32]u8 = @ptrCast(id_ptr);
            database.setCategoryById(id_slice, matched) catch continue;
            count += 1;
        }
    }

    return count;
}

/// Get all transactions as a JSON array.
export fn wimg_get_transactions() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_transactions: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_transactions: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getTransactionsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_transactions: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_transactions: buffer too small (4MB exceeded)", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Set the category for a transaction.
export fn wimg_set_category(id: [*]const u8, id_len: u32, category: u8) i32 {
    var database = global_db orelse {
        setError("wimg_set_category: database not initialized", .{});
        return -1;
    };
    database.setCategory(id, id_len, category) catch |err| {
        setError("wimg_set_category: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Set the excluded flag for a transaction.
export fn wimg_set_excluded(id: [*]const u8, id_len: u32, excluded: u8) i32 {
    var database = global_db orelse {
        setError("wimg_set_excluded: database not initialized", .{});
        return -1;
    };
    database.setExcluded(id, id_len, excluded) catch |err| {
        setError("wimg_set_excluded: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Get monthly summary as JSON.
/// year and month are passed as integers.
export fn wimg_get_summary(year: u32, month: u32) ?[*]const u8 {
    const database = global_db orelse {
        setError("wimg_get_summary: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024; // 8 KB should be plenty
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_summary: failed to allocate buffer", .{});
        return null;
    };

    const json_len = summary.getSummaryJson(
        database.handle,
        @intCast(year),
        @intCast(month),
        buf.ptr + 4,
        buf_size,
    ) orelse {
        setError("wimg_get_summary: failed to generate summary", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Debts ---

/// Get all debts as JSON array.
export fn wimg_get_debts() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_debts: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 32 * 1024; // 32 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_debts: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getDebtsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_debts: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_debts: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Add a debt. JSON input: {"id":"...","name":"...","total":1234.56,"monthly":100.00}
export fn wimg_add_debt(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_add_debt: database not initialized", .{});
        return -1;
    };

    // Simple JSON parsing: find id, name, total, monthly fields
    const json = data[0..len];

    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_add_debt: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_add_debt: missing name field", .{});
        return -1;
    };
    const total = jsonExtractNumber(json, "\"total\"") orelse {
        setError("wimg_add_debt: missing total field", .{});
        return -1;
    };
    const monthly = jsonExtractNumber(json, "\"monthly\"") orelse 0;

    database.insertDebt(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        total,
        monthly,
    ) catch |err| {
        setError("wimg_add_debt: insert failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Mark a debt as partially paid.
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: u32, amount_cents: i64) i32 {
    var database = global_db orelse {
        setError("wimg_mark_debt_paid: database not initialized", .{});
        return -1;
    };

    database.markDebtPaid(id, id_len, amount_cents) catch |err| {
        setError("wimg_mark_debt_paid: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Delete a debt.
export fn wimg_delete_debt(id: [*]const u8, id_len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_delete_debt: database not initialized", .{});
        return -1;
    };

    database.deleteDebt(id, id_len) catch |err| {
        setError("wimg_delete_debt: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Undo the last action. Returns pointer to length-prefixed JSON, or null if nothing to undo.
export fn wimg_undo() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_undo: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_undo: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.undo(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_undo: failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Redo the last undone action. Returns pointer to length-prefixed JSON, or null if nothing to redo.
export fn wimg_redo() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_redo: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_redo: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.redo(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_redo: failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Sync ---

/// Get all rows changed since `since_ts` (unix ms). Returns length-prefixed JSON.
export fn wimg_get_changes(since_ts: i64) ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_changes: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_changes: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getChangesJson(since_ts, buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_changes: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_changes: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Apply incoming sync changes (JSON). Returns count of applied rows, or -1 on error.
export fn wimg_apply_changes(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_apply_changes: database not initialized", .{});
        return -1;
    };

    const result = database.applyChanges(data[0..len]) catch |err| {
        setError("wimg_apply_changes: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return result;
}

// --- Accounts ---

/// Get all accounts as JSON array.
export fn wimg_get_accounts() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_accounts: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_accounts: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getAccountsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_accounts: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_accounts: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Add an account. JSON input: {"id":"...","name":"...","color":"#..."}
export fn wimg_add_account(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_add_account: database not initialized", .{});
        return -1;
    };

    const json = data[0..len];
    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_add_account: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_add_account: missing name field", .{});
        return -1;
    };
    const color = jsonExtractString(json, "\"color\"") orelse "#4361ee";

    database.insertAccount(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        color.ptr,
        @intCast(color.len),
    ) catch |err| {
        setError("wimg_add_account: insert failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Update an account. JSON input: {"id":"...","name":"...","color":"#..."}
export fn wimg_update_account(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_update_account: database not initialized", .{});
        return -1;
    };

    const json = data[0..len];
    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_update_account: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_update_account: missing name field", .{});
        return -1;
    };
    const color = jsonExtractString(json, "\"color\"") orelse "#4361ee";

    database.updateAccount(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        color.ptr,
        @intCast(color.len),
    ) catch |err| {
        setError("wimg_update_account: update failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Delete an account by ID.
export fn wimg_delete_account(id: [*]const u8, id_len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_delete_account: database not initialized", .{});
        return -1;
    };

    database.deleteAccount(id, id_len) catch |err| {
        setError("wimg_delete_account: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Get transactions filtered by account. Pass empty string / 0 len for all.
export fn wimg_get_transactions_filtered(acct: [*]const u8, acct_len: u32) ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_transactions_filtered: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_transactions_filtered: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getTransactionsJsonFiltered(buf.ptr + 4, buf_size, acct, acct_len) catch |err| {
        setError("wimg_get_transactions_filtered: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_transactions_filtered: buffer too small (4MB exceeded)", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Get summary filtered by account.
export fn wimg_get_summary_filtered(year: u32, month: u32, acct: [*]const u8, acct_len: u32) ?[*]const u8 {
    const database = global_db orelse {
        setError("wimg_get_summary_filtered: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_summary_filtered: failed to allocate buffer", .{});
        return null;
    };

    const json_len = summary.getSummaryJsonFiltered(
        database.handle,
        @intCast(year),
        @intCast(month),
        buf.ptr + 4,
        buf_size,
        acct,
        acct_len,
    ) orelse {
        setError("wimg_get_summary_filtered: failed to generate summary", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Recurring ---

/// Detect recurring payment patterns from transaction history.
/// Returns count of patterns detected, or -1 on error.
export fn wimg_detect_recurring() i32 {
    var database = global_db orelse {
        setError("wimg_detect_recurring: database not initialized", .{});
        return -1;
    };

    const count = recurring.detectRecurring(&database) catch |err| {
        setError("wimg_detect_recurring: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return count;
}

/// Get all active recurring patterns as JSON array.
export fn wimg_get_recurring() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_recurring: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 32 * 1024; // 32 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_recurring: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getRecurringJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_recurring: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_recurring: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Get all category metadata as a JSON array (static, no DB needed).
/// Returns length-prefixed JSON: [{"id":0,"name":"...","color":"#...","icon":"..."}, ...]
export fn wimg_get_categories() ?[*]const u8 {
    const Category = types.Category;
    const all_cats = [_]Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };

    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    buf[pos] = '[';
    pos += 1;

    for (all_cats, 0..) |cat, i| {
        if (i > 0) {
            buf[pos] = ',';
            pos += 1;
        }

        const p1 = "{\"id\":";
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;
        pos += db_mod.formatInt(buf[pos..], @as(u32, @intFromEnum(cat))) orelse return null;

        const p2 = ",\"name\":\"";
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        const name = cat.germanName();
        pos += db_mod.jsonEscapeString(buf[pos..], name) orelse return null;

        const p3 = "\",\"color\":\"";
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        const color = cat.color();
        @memcpy(buf[pos .. pos + color.len], color);
        pos += color.len;

        const p4 = "\",\"icon\":\"";
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;

        const icon = cat.icon();
        pos += db_mod.jsonEscapeString(buf[pos..], icon) orelse return null;

        const p5 = "\"}";
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;
    }

    buf[pos] = ']';
    pos += 1;

    return makeLengthPrefixed(buf[0..pos]);
}

/// Close the database and free resources.
export fn wimg_close() void {
    if (global_db) |*database| {
        database.close();
        global_db = null;
    }
}

/// Free a pointer previously returned by other wimg_ functions.
export fn wimg_free(ptr: [*]const u8, len: u32) void {
    _ = len;
    _ = ptr;
    fba.reset();
}

/// Expose memory allocation for the JS host to write data into WASM memory.
export fn wimg_alloc(size: u32) ?[*]u8 {
    const buf = fba.allocator().alloc(u8, size) catch return null;
    return buf.ptr;
}

// --- DB persistence (OPFS) — WASM only ---
// These functions use the in-memory VFS which only exists for wasm32.
// On native (iOS/macOS), SQLite uses the real filesystem directly.

comptime {
    if (is_wasm) {
        @export(&wimg_db_ptr, .{ .name = "wimg_db_ptr" });
        @export(&wimg_db_size, .{ .name = "wimg_db_size" });
        @export(&wimg_db_load, .{ .name = "wimg_db_load" });
    }
}

extern fn wasm_vfs_get_db_ptr(name: [*:0]const u8) ?[*]const u8;
extern fn wasm_vfs_get_db_size(name: [*:0]const u8) i32;
extern fn wasm_vfs_load_db(name: [*:0]const u8, data: [*]const u8, size: i32) i32;

fn wimg_db_ptr() callconv(.c) ?[*]const u8 {
    return wasm_vfs_get_db_ptr("/wimg.db");
}

fn wimg_db_size() callconv(.c) u32 {
    const size = wasm_vfs_get_db_size("/wimg.db");
    return if (size > 0) @intCast(size) else 0;
}

fn wimg_db_load(data: [*]const u8, size: u32) callconv(.c) i32 {
    log("wimg_db_load: loading {d} bytes", .{size});
    const rc = wasm_vfs_load_db("/wimg.db", data, @intCast(size));
    if (rc != 0) {
        setError("wimg_db_load: failed with rc={d}", .{rc});
        return -1;
    }
    return 0;
}

// --- Crypto (E2E encryption for sync) ---

/// Derive a 32-byte encryption key from a sync key using HKDF-SHA256.
/// Returns a length-prefixed 32-byte key, or null on error.
export fn wimg_derive_key(sync_key_ptr: [*]const u8, sync_key_len: u32) ?[*]const u8 {
    const sync_key = sync_key_ptr[0..sync_key_len];
    const key = crypto.deriveKey(sync_key);
    return makeLengthPrefixed(&key);
}

/// Encrypt plaintext using XChaCha20-Poly1305.
/// Takes plaintext + 32-byte key + 24-byte nonce.
/// Returns length-prefixed base64(nonce + ciphertext + tag), or null on error.
export fn wimg_encrypt_field(
    pt_ptr: [*]const u8,
    pt_len: u32,
    key_ptr: [*]const u8,
    nonce_ptr: [*]const u8,
) ?[*]const u8 {
    const plaintext = pt_ptr[0..pt_len];
    const key: [32]u8 = key_ptr[0..32].*;
    const nonce: [24]u8 = nonce_ptr[0..24].*;

    // Encrypted output: nonce(24) + ciphertext(pt_len) + tag(16)
    const enc_size = 24 + pt_len + 16;
    const enc_buf = fba.allocator().alloc(u8, enc_size) catch {
        setError("wimg_encrypt_field: alloc failed", .{});
        return null;
    };

    const enc_len = crypto.encryptField(plaintext, key, nonce, enc_buf) catch {
        setError("wimg_encrypt_field: encryption failed", .{});
        return null;
    };

    // Base64 encode
    const b64_len = std.base64.standard.Encoder.calcSize(enc_len);
    const b64_buf = fba.allocator().alloc(u8, b64_len) catch {
        setError("wimg_encrypt_field: b64 alloc failed", .{});
        return null;
    };
    const encoded = std.base64.standard.Encoder.encode(b64_buf, enc_buf[0..enc_len]);

    return makeLengthPrefixed(encoded);
}

/// Decrypt a base64-encoded ciphertext using XChaCha20-Poly1305.
/// Takes base64(nonce + ciphertext + tag) + 32-byte key.
/// Returns length-prefixed plaintext, or null on error.
export fn wimg_decrypt_field(
    ct_ptr: [*]const u8,
    ct_len: u32,
    key_ptr: [*]const u8,
) ?[*]const u8 {
    const b64_input = ct_ptr[0..ct_len];
    const key: [32]u8 = key_ptr[0..32].*;

    // Decode base64
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(b64_input) catch {
        setError("wimg_decrypt_field: invalid base64", .{});
        return null;
    };
    const decoded_buf = fba.allocator().alloc(u8, decoded_size) catch {
        setError("wimg_decrypt_field: alloc failed", .{});
        return null;
    };
    std.base64.standard.Decoder.decode(decoded_buf, b64_input) catch {
        setError("wimg_decrypt_field: base64 decode failed", .{});
        return null;
    };

    // Decrypt: input is nonce(24) + ciphertext + tag(16), so plaintext = decoded_size - 40
    const pt_len_max = if (decoded_size > 40) decoded_size - 40 else 0;
    const pt_buf = fba.allocator().alloc(u8, pt_len_max) catch {
        setError("wimg_decrypt_field: pt alloc failed", .{});
        return null;
    };

    const pt_len = crypto.decryptField(decoded_buf[0..decoded_size], key, pt_buf) catch {
        setError("wimg_decrypt_field: decryption failed", .{});
        return null;
    };

    return makeLengthPrefixed(pt_buf[0..pt_len]);
}

// --- FinTS (native-only) ---

// Global FinTS session state — only exists on native targets
var fints_session: if (!is_wasm) fints_mod.FintsSession else void = if (!is_wasm) fints_mod.FintsSession.init("", "", "", "") else {};

comptime {
    if (!is_wasm) {
        @export(&wimg_fints_connect, .{ .name = "wimg_fints_connect" });
        @export(&wimg_fints_send_tan, .{ .name = "wimg_fints_send_tan" });
        @export(&wimg_fints_fetch, .{ .name = "wimg_fints_fetch" });
        @export(&wimg_fints_get_banks, .{ .name = "wimg_fints_get_banks" });
    }
}

/// Connect to a bank via FinTS. Input JSON: {"blz":"...","user":"...","pin":"..."}
/// Returns length-prefixed JSON: {"status":"ok"} or {"status":"tan_required","challenge":"..."}
fn wimg_fints_connect(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    const json = data[0..len];

    const blz = jsonExtractString(json, "\"blz\"") orelse {
        setError("wimg_fints_connect: missing blz field", .{});
        return null;
    };
    const user = jsonExtractString(json, "\"user\"") orelse {
        setError("wimg_fints_connect: missing user field", .{});
        return null;
    };
    const pin = jsonExtractString(json, "\"pin\"") orelse {
        setError("wimg_fints_connect: missing pin field", .{});
        return null;
    };
    const product = jsonExtractString(json, "\"product\"") orelse "0000000000000000000000000";

    // Look up bank
    const bank = banks_mod.findByBlz(blz) orelse {
        setError("wimg_fints_connect: unknown BLZ {s}", .{blz});
        return null;
    };

    // Initialize session
    fints_session = fints_mod.FintsSession.init(blz, bank.urlSlice(), user, pin);
    const prod_len = @min(product.len, 25);
    @memcpy(fints_session.product_id[0..prod_len], product[0..prod_len]);
    fints_session.product_id_len = @intCast(prod_len);

    // Step 1: Anonymous init to fetch BPD
    var msg_buf: [8192]u8 = undefined;
    const anon_len = fints_mod.buildAnonInit(&fints_session, &msg_buf) orelse {
        setError("wimg_fints_connect: failed to build anon init", .{});
        return null;
    };

    var resp_buf: [65536]u8 = undefined;
    const resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..anon_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_connect: HTTP request failed", .{});
        return null;
    };

    var anon_resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &anon_resp);
    fints_session.msg_num += 1;

    // Step 2: Authenticated init
    const auth_len = fints_mod.buildAuthInit(&fints_session, &msg_buf) orelse {
        setError("wimg_fints_connect: failed to build auth init", .{});
        return null;
    };

    const auth_resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..auth_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_connect: auth HTTP request failed", .{});
        return null;
    };

    var auth_resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..auth_resp_len], &auth_resp);
    fints_session.msg_num += 1;

    // Clear PIN from memory after auth
    fints_session.clearPin();

    // Check result
    if (auth_resp.hasError()) {
        var result_buf: [512]u8 = undefined;
        const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"error\",\"message\":\"Authentication failed\"}}", .{}) catch return null;
        return makeLengthPrefixed(result_json);
    }

    if (fints_session.has_pending_tan) {
        var result_buf: [512]u8 = undefined;
        const challenge = fints_session.challenge[0..fints_session.challenge_len];
        const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\"}}", .{challenge}) catch return null;
        return makeLengthPrefixed(result_json);
    }

    return makeLengthPrefixed("{\"status\":\"ok\"}");
}

/// Submit a TAN. Input JSON: {"tan":"123456"}
/// Returns length-prefixed JSON: {"status":"ok"} or {"status":"error","message":"..."}
fn wimg_fints_send_tan(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    const json = data[0..len];
    const tan = jsonExtractString(json, "\"tan\"") orelse {
        setError("wimg_fints_send_tan: missing tan field", .{});
        return null;
    };

    var msg_buf: [8192]u8 = undefined;
    const msg_len = fints_mod.buildTanResponse(&fints_session, tan, &msg_buf) orelse {
        setError("wimg_fints_send_tan: failed to build TAN response", .{});
        return null;
    };

    var resp_buf: [65536]u8 = undefined;
    const resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..msg_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_send_tan: HTTP request failed", .{});
        return null;
    };

    var resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &resp);
    fints_session.msg_num += 1;

    if (resp.hasError()) {
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"TAN rejected\"}");
    }

    fints_session.has_pending_tan = false;
    return makeLengthPrefixed("{\"status\":\"ok\"}");
}

/// Fetch bank statements. Input JSON: {"from":"2026-01-01","to":"2026-03-01"}
/// Fetches MT940 data, parses it, inserts transactions into DB.
/// Returns length-prefixed JSON: {"imported":N,"duplicates":N}
fn wimg_fints_fetch(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    var database = global_db orelse {
        setError("wimg_fints_fetch: database not initialized", .{});
        return null;
    };

    const json = data[0..len];
    const from = jsonExtractString(json, "\"from\"") orelse "";
    const to = jsonExtractString(json, "\"to\"") orelse "";

    // Build and send HKKAZ request
    var msg_buf: [8192]u8 = undefined;
    const msg_len = fints_mod.buildFetchStatements(&fints_session, from, to, &msg_buf) orelse {
        setError("wimg_fints_fetch: failed to build fetch request", .{});
        return null;
    };

    var resp_buf: [65536]u8 = undefined;
    const resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..msg_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_fetch: HTTP request failed", .{});
        return null;
    };

    var resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &resp);
    fints_session.msg_num += 1;

    // Check if TAN is required for statement fetch
    if (fints_session.has_pending_tan) {
        var result_buf: [512]u8 = undefined;
        const challenge = fints_session.challenge[0..fints_session.challenge_len];
        const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\"}}", .{challenge}) catch return null;
        return makeLengthPrefixed(result_json);
    }

    if (resp.mt940_len == 0) {
        return makeLengthPrefixed("{\"imported\":0,\"duplicates\":0}");
    }

    // Parse MT940 data
    const bank = banks_mod.findByBlz(&fints_session.blz);
    const account_name = if (bank) |b| b.nameSlice() else "FinTS";

    var txn_buf: [2000]Transaction = undefined;
    const mt940_result = mt940_mod.parseMt940(
        resp.mt940_data[0..resp.mt940_len],
        account_name,
        &txn_buf,
    );

    // Insert into database
    var imported: u32 = 0;
    var duplicates: u32 = 0;

    for (txn_buf[0..mt940_result.count]) |*txn| {
        const inserted = database.insertTransaction(txn) catch {
            continue;
        };
        if (inserted) {
            imported += 1;
            // Auto-categorize
            if (txn.category == .uncategorized) {
                const matched = categories.matchRules(database.handle, txn.descriptionSlice());
                if (matched != .uncategorized) {
                    database.setCategoryById(&txn.id, matched) catch {};
                }
            }
        } else {
            duplicates += 1;
        }
    }

    // Auto-create account entry
    database.ensureAccount(account_name, account_name, "#4361ee") catch {};

    // End dialog
    const end_len = fints_mod.buildDialogEnd(&fints_session, &msg_buf);
    if (end_len) |el| {
        _ = fints_http_mod.sendFintsMessage(
            std.heap.page_allocator,
            fints_session.urlSlice(),
            msg_buf[0..el],
            &resp_buf,
        ) catch {};
    }

    var result_buf: [256]u8 = undefined;
    const result_json = std.fmt.bufPrint(&result_buf, "{{\"imported\":{d},\"duplicates\":{d}}}", .{ imported, duplicates }) catch return null;
    return makeLengthPrefixed(result_json);
}

/// Get the list of supported banks as JSON.
/// Returns length-prefixed JSON array.
fn wimg_fints_get_banks() callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    var buf: [16384]u8 = undefined;
    const len = banks_mod.toJson(&buf) orelse {
        setError("wimg_fints_get_banks: buffer too small", .{});
        return null;
    };
    return makeLengthPrefixed(buf[0..len]);
}

// --- Helpers ---

fn makeLengthPrefixed(data: []const u8) ?[*]const u8 {
    const out = fba.allocator().alloc(u8, data.len + 5) catch return null;
    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(data.len)));
    out[0] = len_bytes[0];
    out[1] = len_bytes[1];
    out[2] = len_bytes[2];
    out[3] = len_bytes[3];
    @memcpy(out[4 .. 4 + data.len], data);
    out[4 + data.len] = 0;
    return out.ptr;
}

fn formatImportResultEx(buf: *[512]u8, result: *const ImportResult, format: parser.CsvFormat, categorized: u32) ?usize {
    const template = "{{\"total_rows\":{d},\"imported\":{d},\"skipped_duplicates\":{d},\"errors\":{d},\"format\":\"{s}\",\"categorized\":{d}}}";
    const slice = std.fmt.bufPrint(buf, template, .{
        result.total_rows,
        result.imported,
        result.skipped_duplicates,
        result.errors,
        format.name(),
        categorized,
    }) catch return null;
    return slice.len;
}

// --- Simple JSON field extractors (no allocator needed) ---

fn jsonExtractString(json: []const u8, key: []const u8) ?[]const u8 {
    // Find key position
    const key_pos = findSubstring(json, key) orelse return null;
    var i = key_pos + key.len;

    // Skip whitespace and colon
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}

    // Expect opening quote
    if (i >= json.len or json[i] != '"') return null;
    i += 1;

    // Find closing quote (no escape handling needed for simple IDs/names)
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {}
    if (i >= json.len) return null;

    return json[start..i];
}

fn jsonExtractNumber(json: []const u8, key: []const u8) ?i64 {
    const key_pos = findSubstring(json, key) orelse return null;
    var i = key_pos + key.len;

    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}

    // Parse number (may be decimal like 1234.56, convert to cents)
    var negative = false;
    if (i < json.len and json[i] == '-') {
        negative = true;
        i += 1;
    }

    var whole: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        whole = whole * 10 + (json[i] - '0');
    }

    var frac: i64 = 0;
    var frac_digits: u8 = 0;
    if (i < json.len and json[i] == '.') {
        i += 1;
        while (i < json.len and json[i] >= '0' and json[i] <= '9' and frac_digits < 2) : (i += 1) {
            frac = frac * 10 + (json[i] - '0');
            frac_digits += 1;
        }
    }
    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

fn findSubstring(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

const AccountInfo = struct { id: []const u8, name: []const u8, color: []const u8 };

fn accountInfoForFormat(format: parser.CsvFormat) AccountInfo {
    return switch (format) {
        .comdirect => .{ .id = "comdirect", .name = "Comdirect", .color = "#f5a623" },
        .trade_republic => .{ .id = "trade_republic", .name = "Trade Republic", .color = "#1a1a2e" },
        .scalable_capital => .{ .id = "scalable_capital", .name = "Scalable Capital", .color = "#6c5ce7" },
        .unknown => .{ .id = "unknown", .name = "Unbekannt", .color = "#4361ee" },
    };
}
