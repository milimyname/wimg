const std = @import("std");
const types = @import("types.zig");
const db_mod = @import("db.zig");
const parser = @import("parser.zig");
const categories = @import("categories.zig");
const summary = @import("summary.zig");

const Db = db_mod.Db;
const Transaction = types.Transaction;
const ImportResult = types.ImportResult;

// --- JS interop: imported logging function ---
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
    js_console_log(&error_buf, error_len);
}

fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    js_console_log(&buf, @intCast(slice.len));
}

// --- WASM memory management ---
var wasm_buf: [4 * 1024 * 1024]u8 = undefined; // 4 MB scratch space
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

    // Parse CSV into transactions (max 10000 per import)
    const max_txns = 10000;
    const txn_buf = fba.allocator().alloc(Transaction, max_txns) catch {
        setError("wimg_import_csv: failed to allocate transaction buffer", .{});
        return null;
    };
    defer fba.allocator().free(txn_buf);

    var result: ImportResult = undefined;
    const format = parser.parseCsv(csv_data, txn_buf, &result);

    log("wimg_import_csv: format={s}, parsed {d} rows, {d} transactions, {d} errors", .{
        format.name(), result.total_rows, result.imported, result.errors,
    });

    // Insert parsed transactions into DB
    var actual_imported: u32 = 0;
    var duplicates: u32 = 0;
    var insert_errors: u32 = 0;

    for (txn_buf[0..result.imported]) |*txn| {
        const inserted = database.insertTransaction(txn) catch |err| {
            insert_errors += 1;
            if (insert_errors <= 3) {
                setError("wimg_import_csv: insert failed: {s}", .{@errorName(err)});
            }
            continue;
        };
        if (inserted) {
            actual_imported += 1;
        } else {
            duplicates += 1;
        }
    }

    result.imported = actual_imported;
    result.skipped_duplicates = duplicates;
    result.errors += insert_errors;

    // Auto-categorize newly imported uncategorized transactions
    var categorized: u32 = 0;
    for (txn_buf[0..actual_imported + duplicates]) |*txn| {
        if (txn.category != .uncategorized) continue;

        const matched = categories.matchRules(database.handle, txn.descriptionSlice());
        if (matched != .uncategorized) {
            database.setCategoryById(&txn.id, matched) catch continue;
            categorized += 1;
        }
    }

    log("wimg_import_csv: {d} imported, {d} duplicates, {d} errors, {d} auto-categorized", .{
        actual_imported, duplicates, result.errors, categorized,
    });

    // Serialize result to JSON (with format and categorized count)
    var json_buf: [512]u8 = undefined;
    const json_len = formatImportResultEx(&json_buf, &result, format, categorized) orelse {
        setError("wimg_import_csv: failed to format result JSON", .{});
        return null;
    };

    return makeLengthPrefixed(json_buf[0..json_len]);
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

    const buf_size: usize = 1024 * 1024; // 1 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_transactions: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getTransactionsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_transactions: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_transactions: buffer too small", .{});
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

// --- DB persistence (OPFS) ---
extern fn wasm_vfs_get_db_ptr(name: [*:0]const u8) ?[*]const u8;
extern fn wasm_vfs_get_db_size(name: [*:0]const u8) i32;
extern fn wasm_vfs_load_db(name: [*:0]const u8, data: [*]const u8, size: i32) i32;

export fn wimg_db_ptr() ?[*]const u8 {
    return wasm_vfs_get_db_ptr("/wimg.db");
}

export fn wimg_db_size() u32 {
    const size = wasm_vfs_get_db_size("/wimg.db");
    return if (size > 0) @intCast(size) else 0;
}

export fn wimg_db_load(data: [*]const u8, size: u32) i32 {
    log("wimg_db_load: loading {d} bytes", .{size});
    const rc = wasm_vfs_load_db("/wimg.db", data, @intCast(size));
    if (rc != 0) {
        setError("wimg_db_load: failed with rc={d}", .{rc});
        return -1;
    }
    return 0;
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
