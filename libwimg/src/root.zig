const std = @import("std");
const types = @import("types.zig");
const db_mod = @import("db.zig");
const parser = @import("parser.zig");

const Db = db_mod.Db;
const Transaction = types.Transaction;
const ImportResult = types.ImportResult;

// --- JS interop: imported logging function ---
// The JS host provides this so we can log to browser console.
// On wasm32-freestanding, extern functions become WASM imports (env.js_console_log).
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

/// Import a CSV file. Returns a pointer to a JSON string with the import result,
/// or null on error. The caller must free the returned pointer with `wimg_free`.
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
    parser.parseComdirectCsv(csv_data, txn_buf, &result);

    log("wimg_import_csv: parsed {d} rows, {d} transactions, {d} errors", .{
        result.total_rows, result.imported, result.errors,
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

    log("wimg_import_csv: {d} imported, {d} duplicates, {d} errors", .{
        actual_imported, duplicates, result.errors,
    });

    // Serialize result to JSON
    var json_buf: [256]u8 = undefined;
    const json_len = formatImportResult(&json_buf, &result) orelse {
        setError("wimg_import_csv: failed to format result JSON", .{});
        return null;
    };

    // Allocate output buffer that caller will free
    const out = fba.allocator().alloc(u8, json_len + 5) catch {
        setError("wimg_import_csv: failed to allocate output buffer", .{});
        return null;
    };

    // First 4 bytes = length (little-endian u32)
    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    out[0] = len_bytes[0];
    out[1] = len_bytes[1];
    out[2] = len_bytes[2];
    out[3] = len_bytes[3];
    @memcpy(out[4 .. 4 + json_len], json_buf[0..json_len]);
    out[4 + json_len] = 0;

    return out.ptr;
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
// C functions from wasm_vfs.c
extern fn wasm_vfs_get_db_ptr(name: [*:0]const u8) ?[*]const u8;
extern fn wasm_vfs_get_db_size(name: [*:0]const u8) i32;
extern fn wasm_vfs_load_db(name: [*:0]const u8, data: [*]const u8, size: i32) i32;

/// Get a pointer to the raw SQLite DB bytes in memory.
/// Returns null if the DB file doesn't exist yet.
export fn wimg_db_ptr() ?[*]const u8 {
    return wasm_vfs_get_db_ptr("/wimg.db");
}

/// Get the current size of the SQLite DB in bytes.
export fn wimg_db_size() u32 {
    const size = wasm_vfs_get_db_size("/wimg.db");
    return if (size > 0) @intCast(size) else 0;
}

/// Load DB bytes from JS (OPFS) into the VFS memory BEFORE calling wimg_init.
/// `data` = pointer to bytes already in WASM memory, `size` = byte count.
/// Returns 0 on success, -1 on error.
export fn wimg_db_load(data: [*]const u8, size: u32) i32 {
    log("wimg_db_load: loading {d} bytes", .{size});
    const rc = wasm_vfs_load_db("/wimg.db", data, @intCast(size));
    if (rc != 0) {
        setError("wimg_db_load: failed with rc={d}", .{rc});
        return -1;
    }
    return 0;
}

// --- JSON formatting helpers ---

fn formatImportResult(buf: *[256]u8, result: *const ImportResult) ?usize {
    const template = "{{\"total_rows\":{d},\"imported\":{d},\"skipped_duplicates\":{d},\"errors\":{d}}}";
    const slice = std.fmt.bufPrint(buf, template, .{
        result.total_rows,
        result.imported,
        result.skipped_duplicates,
        result.errors,
    }) catch return null;
    return slice.len;
}
