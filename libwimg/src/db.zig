const std = @import("std");
const types = @import("types.zig");
const c = @import("sqlite_c.zig");

const Transaction = types.Transaction;
const Date = types.Date;
const Category = types.Category;
const ImportResult = types.ImportResult;

pub const DbError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
};

pub const Db = struct {
    handle: *c.sqlite3,

    const schema_sql =
        \\CREATE TABLE IF NOT EXISTS transactions (
        \\  id TEXT PRIMARY KEY,
        \\  date_year INTEGER NOT NULL,
        \\  date_month INTEGER NOT NULL,
        \\  date_day INTEGER NOT NULL,
        \\  description TEXT NOT NULL,
        \\  amount_cents INTEGER NOT NULL,
        \\  currency TEXT NOT NULL DEFAULT 'EUR',
        \\  category INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_transactions_date
        \\  ON transactions(date_year, date_month, date_day);
    ;

    pub fn init(path: [*:0]const u8) DbError!Db {
        var handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &handle);
        if (rc != c.SQLITE_OK or handle == null) {
            if (handle) |h| _ = c.sqlite3_close(h);
            return DbError.OpenFailed;
        }

        var self = Db{ .handle = handle.? };
        try self.exec(schema_sql);

        // Enable WAL mode for better concurrent reads
        self.exec("PRAGMA journal_mode=WAL;") catch {};

        return self;
    }

    pub fn close(self: *Db) void {
        _ = c.sqlite3_close(self.handle);
    }

    fn exec(self: *Db, sql: [*:0]const u8) DbError!void {
        const rc = c.sqlite3_exec(self.handle, sql, null, null, null);
        if (rc != c.SQLITE_OK) return DbError.ExecFailed;
    }

    pub fn insertTransaction(self: *Db, txn: *const Transaction) DbError!bool {
        const sql =
            \\INSERT OR IGNORE INTO transactions
            \\  (id, date_year, date_month, date_day, description, amount_cents, currency, category)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);
        ;

        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;

        // Bind id (hex hash string)
        rc = c.sqlite3_bind_text(s, 1, &txn.id, 32, c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 2, @intCast(txn.date.year));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 3, @intCast(txn.date.month));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 4, @intCast(txn.date.day));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_text(s, 5, @ptrCast(&txn.description), @intCast(txn.description_len), c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int64(s, 6, @intCast(txn.amount_cents));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_text(s, 7, &txn.currency, 3, c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 8, @intCast(@intFromEnum(txn.category)));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;

        // Returns true if row was inserted (not a duplicate)
        return c.sqlite3_changes(self.handle) > 0;
    }

    pub fn setCategory(self: *Db, id: [*]const u8, id_len: usize, category: u8) DbError!void {
        const sql = "UPDATE transactions SET category = ?1 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;

        if (c.sqlite3_bind_int(s, 1, @intCast(category)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;

        const rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Write all transactions as JSON into the provided buffer.
    /// Returns the number of bytes written, or null if buffer is too small.
    pub fn getTransactionsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql =
            \\SELECT id, date_year, date_month, date_day, description, amount_cents, currency, category
            \\FROM transactions
            \\ORDER BY date_year DESC, date_month DESC, date_day DESC, rowid DESC;
        ;

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        // Opening bracket
        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            // Get column values
            const id_ptr = c.sqlite3_column_text(s, 0);
            const year = c.sqlite3_column_int(s, 1);
            const month = c.sqlite3_column_int(s, 2);
            const day = c.sqlite3_column_int(s, 3);
            const desc_ptr = c.sqlite3_column_text(s, 4);
            const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 4));
            const amount = c.sqlite3_column_int64(s, 5);
            const curr_ptr = c.sqlite3_column_text(s, 6);
            const cat = c.sqlite3_column_int(s, 7);

            if (id_ptr == null or desc_ptr == null or curr_ptr == null) continue;

            // Format JSON object
            const remaining = buf_len - pos;
            const slice = buf[pos..buf_len];

            const written = jsonFormatTransaction(
                slice,
                remaining,
                first,
                id_ptr.?,
                @intCast(year),
                @intCast(month),
                @intCast(day),
                desc_ptr.?,
                desc_len,
                amount,
                curr_ptr.?,
                @intCast(cat),
            ) orelse return null;

            pos += written;
            first = false;
        }

        // Closing bracket
        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }
};

fn jsonFormatTransaction(
    buf: []u8,
    buf_len: usize,
    first: bool,
    id_ptr: [*]const u8,
    year: u16,
    month: u8,
    day: u8,
    desc_ptr: [*]const u8,
    desc_len: usize,
    amount_cents: i64,
    curr_ptr: [*]const u8,
    category: u8,
) ?usize {
    _ = buf_len;

    // Build JSON manually to avoid allocator dependency
    var pos: usize = 0;

    if (!first) {
        if (pos >= buf.len) return null;
        buf[pos] = ',';
        pos += 1;
    }

    // {"id":"
    const prefix = "{\"id\":\"";
    if (pos + prefix.len > buf.len) return null;
    @memcpy(buf[pos .. pos + prefix.len], prefix);

    pos += prefix.len;

    // id value (32 hex chars)
    if (pos + 32 > buf.len) return null;
    @memcpy(buf[pos .. pos + 32], id_ptr[0..32]);
    pos += 32;

    // ","date":"YYYY-MM-DD"
    const date_pre = "\",\"date\":\"";
    if (pos + date_pre.len + 10 > buf.len) return null;
    @memcpy(buf[pos .. pos + date_pre.len], date_pre);
    pos += date_pre.len;

    // Format date
    pos += formatDate(buf[pos..], year, month, day) orelse return null;

    // ","description":"
    const desc_pre = "\",\"description\":\"";
    if (pos + desc_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + desc_pre.len], desc_pre);
    pos += desc_pre.len;

    // Escaped description
    pos += jsonEscapeString(buf[pos..], desc_ptr[0..desc_len]) orelse return null;

    // ","amount":
    const amt_pre = "\",\"amount\":";
    if (pos + amt_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + amt_pre.len], amt_pre);
    pos += amt_pre.len;

    // Format amount as decimal (cents -> X.XX)
    pos += formatAmount(buf[pos..], amount_cents) orelse return null;

    // ,"currency":"
    const cur_pre = ",\"currency\":\"";
    if (pos + cur_pre.len + 3 > buf.len) return null;
    @memcpy(buf[pos .. pos + cur_pre.len], cur_pre);
    pos += cur_pre.len;
    @memcpy(buf[pos .. pos + 3], curr_ptr[0..3]);
    pos += 3;

    // ","category":N}
    const cat_pre = "\",\"category\":";
    if (pos + cat_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + cat_pre.len], cat_pre);
    pos += cat_pre.len;

    pos += formatInt(buf[pos..], category) orelse return null;

    if (pos >= buf.len) return null;
    buf[pos] = '}';
    pos += 1;

    return pos;
}

fn formatDate(buf: []u8, year: u16, month: u8, day: u8) ?usize {
    if (buf.len < 10) return null;
    // YYYY-MM-DD
    buf[0] = '0' + @as(u8, @intCast(year / 1000));
    buf[1] = '0' + @as(u8, @intCast((year / 100) % 10));
    buf[2] = '0' + @as(u8, @intCast((year / 10) % 10));
    buf[3] = '0' + @as(u8, @intCast(year % 10));
    buf[4] = '-';
    buf[5] = '0' + month / 10;
    buf[6] = '0' + month % 10;
    buf[7] = '-';
    buf[8] = '0' + day / 10;
    buf[9] = '0' + day % 10;
    return 10;
}

fn formatAmount(buf: []u8, cents: i64) ?usize {
    var pos: usize = 0;
    var val = cents;

    if (val < 0) {
        if (pos >= buf.len) return null;
        buf[pos] = '-';
        pos += 1;
        val = -val;
    }

    const whole: u64 = @intCast(@divTrunc(val, 100));
    const frac: u64 = @intCast(@mod(val, 100));

    pos += formatInt(buf[pos..], whole) orelse return null;

    if (pos >= buf.len) return null;
    buf[pos] = '.';
    pos += 1;

    if (pos + 2 > buf.len) return null;
    buf[pos] = '0' + @as(u8, @intCast(frac / 10));
    buf[pos + 1] = '0' + @as(u8, @intCast(frac % 10));
    pos += 2;

    return pos;
}

fn formatInt(buf: []u8, value: anytype) ?usize {
    var val = value;
    if (val == 0) {
        if (buf.len < 1) return null;
        buf[0] = '0';
        return 1;
    }

    // Write digits in reverse, then flip
    var tmp: [20]u8 = undefined;
    var len: usize = 0;
    while (val > 0) : (len += 1) {
        tmp[len] = '0' + @as(u8, @intCast(@mod(val, 10)));
        val = @divTrunc(val, 10);
    }

    if (len > buf.len) return null;
    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

fn jsonEscapeString(buf: []u8, src: []const u8) ?usize {
    var pos: usize = 0;
    for (src) |ch| {
        switch (ch) {
            '"' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = '\\';
                pos += 2;
            },
            '\n' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 't';
                pos += 2;
            },
            else => {
                if (pos >= buf.len) return null;
                buf[pos] = ch;
                pos += 1;
            },
        }
    }
    return pos;
}
