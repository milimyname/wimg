// Zig bindings for the SQLite C API subset we need.
// Using @cImport on native, manual declarations for WASM.

pub const SQLITE_OK = 0;
pub const SQLITE_ROW = 100;
pub const SQLITE_DONE = 101;
pub const SQLITE_STATIC = @as(isize, 0);
pub const SQLITE_NULL = 5;

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

// We link against sqlite3.c compiled as a C source, so these are
// resolved at link time regardless of target.
pub extern fn sqlite3_open(filename: [*:0]const u8, ppDb: *?*sqlite3) c_int;
pub extern fn sqlite3_close(db: *sqlite3) c_int;
pub extern fn sqlite3_exec(
    db: *sqlite3,
    sql: [*:0]const u8,
    callback: ?*const anyopaque,
    arg: ?*anyopaque,
    errmsg: ?*?[*:0]u8,
) c_int;
pub extern fn sqlite3_prepare_v2(
    db: *sqlite3,
    sql: [*:0]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: ?*?[*:0]const u8,
) c_int;
pub extern fn sqlite3_finalize(stmt: *sqlite3_stmt) c_int;
pub extern fn sqlite3_step(stmt: *sqlite3_stmt) c_int;
pub extern fn sqlite3_reset(stmt: *sqlite3_stmt) c_int;

pub extern fn sqlite3_bind_int(stmt: *sqlite3_stmt, col: c_int, value: c_int) c_int;
pub extern fn sqlite3_bind_int64(stmt: *sqlite3_stmt, col: c_int, value: i64) c_int;
pub extern fn sqlite3_bind_text(
    stmt: *sqlite3_stmt,
    col: c_int,
    text: [*]const u8,
    len: c_int,
    destructor: isize,
) c_int;
pub extern fn sqlite3_bind_null(stmt: *sqlite3_stmt, col: c_int) c_int;

pub extern fn sqlite3_column_int(stmt: *sqlite3_stmt, col: c_int) c_int;
pub extern fn sqlite3_column_int64(stmt: *sqlite3_stmt, col: c_int) i64;
pub extern fn sqlite3_column_text(stmt: *sqlite3_stmt, col: c_int) ?[*]const u8;
pub extern fn sqlite3_column_bytes(stmt: *sqlite3_stmt, col: c_int) c_int;
pub extern fn sqlite3_column_type(stmt: *sqlite3_stmt, col: c_int) c_int;

pub extern fn sqlite3_changes(db: *sqlite3) c_int;
