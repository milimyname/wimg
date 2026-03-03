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

const CURRENT_SCHEMA_VERSION = 3;
const MAX_UNDO_ENTRIES = 50;

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
        \\  category INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_transactions_date
        \\  ON transactions(date_year, date_month, date_day);
        \\CREATE TABLE IF NOT EXISTS meta (
        \\  key TEXT PRIMARY KEY,
        \\  value TEXT NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS rules (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  pattern TEXT NOT NULL,
        \\  category INTEGER NOT NULL,
        \\  priority INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS debts (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  total INTEGER NOT NULL,
        \\  paid INTEGER NOT NULL DEFAULT 0,
        \\  monthly INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS undo_history (
        \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  op INTEGER NOT NULL,
        \\  tbl TEXT NOT NULL,
        \\  row_id TEXT NOT NULL,
        \\  col TEXT,
        \\  old_val TEXT,
        \\  new_val TEXT,
        \\  undone INTEGER NOT NULL DEFAULT 0
        \\);
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

        // Run migrations for existing databases
        try self.migrate();

        return self;
    }

    fn migrate(self: *Db) DbError!void {
        const version = self.getMetaInt("schema_version") orelse 0;

        if (version < 1) {
            // v1: add updated_at to transactions (may already exist from fresh schema)
            self.exec("ALTER TABLE transactions ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;") catch {};
        }

        if (version < 2) {
            // v2: seed default categorization rules
            self.seedDefaultRules() catch {};
        }

        if (version < 3) {
            // v3: undo_history table
            self.exec(
                \\CREATE TABLE IF NOT EXISTS undo_history (
                \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
                \\  op INTEGER NOT NULL,
                \\  tbl TEXT NOT NULL,
                \\  row_id TEXT NOT NULL,
                \\  col TEXT,
                \\  old_val TEXT,
                \\  new_val TEXT,
                \\  undone INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        // Store current version
        if (version < CURRENT_SCHEMA_VERSION) {
            self.setMeta("schema_version", "3") catch {};
        }
    }

    pub fn getMetaInt(self: *Db, key: [*:0]const u8) ?i32 {
        const sql = "SELECT value FROM meta WHERE key = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, key, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return null;

        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;

        const val_ptr = c.sqlite3_column_text(s, 0) orelse return null;
        const val_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const val = val_ptr[0..val_len];

        // Parse integer from string
        var result: i32 = 0;
        for (val) |ch| {
            if (ch >= '0' and ch <= '9') {
                result = result * 10 + @as(i32, ch - '0');
            }
        }
        return result;
    }

    pub fn setMeta(self: *Db, key: [*:0]const u8, value: [*:0]const u8) DbError!void {
        const sql = "INSERT OR REPLACE INTO meta (key, value) VALUES (?1, ?2);";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, key, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, value, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn seedDefaultRules(self: *Db) DbError!void {
        const rules = [_]struct { pattern: [*:0]const u8, category: u8, priority: u8 }{
            // Groceries (1)
            .{ .pattern = "REWE", .category = 1, .priority = 10 },
            .{ .pattern = "LIDL", .category = 1, .priority = 10 },
            .{ .pattern = "ALDI", .category = 1, .priority = 10 },
            .{ .pattern = "EDEKA", .category = 1, .priority = 10 },
            .{ .pattern = "NETTO", .category = 1, .priority = 10 },
            .{ .pattern = "PENNY", .category = 1, .priority = 10 },
            .{ .pattern = "KAUFLAND", .category = 1, .priority = 10 },
            // Dining (2)
            .{ .pattern = "LIEFERANDO", .category = 2, .priority = 10 },
            .{ .pattern = "MCDONALD", .category = 2, .priority = 10 },
            .{ .pattern = "BURGER KING", .category = 2, .priority = 10 },
            // Transport (3)
            .{ .pattern = "DB VERTRIEB", .category = 3, .priority = 10 },
            .{ .pattern = "DEUTSCHE BAHN", .category = 3, .priority = 10 },
            .{ .pattern = "SHELL", .category = 3, .priority = 5 },
            .{ .pattern = "ARAL", .category = 3, .priority = 5 },
            .{ .pattern = "TIER", .category = 3, .priority = 5 },
            // Housing (4)
            .{ .pattern = "MIETE", .category = 4, .priority = 20 },
            // Utilities (5)
            .{ .pattern = "STROM", .category = 5, .priority = 15 },
            .{ .pattern = "WSW", .category = 5, .priority = 15 },
            .{ .pattern = "STADTWERKE", .category = 5, .priority = 15 },
            .{ .pattern = "VODAFONE", .category = 5, .priority = 10 },
            .{ .pattern = "TELEKOM", .category = 5, .priority = 10 },
            .{ .pattern = "O2", .category = 5, .priority = 10 },
            // Entertainment (6)
            .{ .pattern = "SPOTIFY", .category = 6, .priority = 10 },
            .{ .pattern = "KINO", .category = 6, .priority = 10 },
            // Shopping (7)
            .{ .pattern = "AMAZON", .category = 7, .priority = 5 },
            .{ .pattern = "ZALANDO", .category = 7, .priority = 10 },
            .{ .pattern = "IKEA", .category = 7, .priority = 10 },
            .{ .pattern = "DM DROGERIE", .category = 7, .priority = 10 },
            .{ .pattern = "ROSSMANN", .category = 7, .priority = 10 },
            // Health (8)
            .{ .pattern = "APOTHEKE", .category = 8, .priority = 10 },
            .{ .pattern = "ARZT", .category = 8, .priority = 10 },
            // Insurance (9)
            .{ .pattern = "VERSICHERUNG", .category = 9, .priority = 10 },
            .{ .pattern = "ALLIANZ", .category = 9, .priority = 10 },
            .{ .pattern = "HUK", .category = 9, .priority = 10 },
            // Income (10)
            .{ .pattern = "GEHALT", .category = 10, .priority = 20 },
            .{ .pattern = "LOHN", .category = 10, .priority = 20 },
            // Subscriptions (13)
            .{ .pattern = "NETFLIX", .category = 13, .priority = 10 },
            .{ .pattern = "DISNEY", .category = 13, .priority = 10 },
            .{ .pattern = "APPLE.COM", .category = 13, .priority = 10 },
            .{ .pattern = "GOOGLE STORAGE", .category = 13, .priority = 10 },
            // Education (15)
            .{ .pattern = "FOM", .category = 15, .priority = 15 },
        };

        const sql = "INSERT OR IGNORE INTO rules (pattern, category, priority) VALUES (?1, ?2, ?3);";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        for (rules) |rule| {
            _ = c.sqlite3_reset(s);
            if (c.sqlite3_bind_text(s, 1, rule.pattern, -1, c.SQLITE_STATIC) != c.SQLITE_OK) continue;
            if (c.sqlite3_bind_int(s, 2, @intCast(rule.category)) != c.SQLITE_OK) continue;
            if (c.sqlite3_bind_int(s, 3, @intCast(rule.priority)) != c.SQLITE_OK) continue;
            _ = c.sqlite3_step(s);
        }
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
            \\  (id, date_year, date_month, date_day, description, amount_cents, currency, category, updated_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9);
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

        rc = c.sqlite3_bind_int64(s, 9, 0); // updated_at = 0 for new imports
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;

        // Returns true if row was inserted (not a duplicate)
        return c.sqlite3_changes(self.handle) > 0;
    }

    pub fn setCategory(self: *Db, id: [*]const u8, id_len: usize, category: u8) DbError!void {
        // Capture old category for undo history
        const old_cat = self.queryInt("SELECT category FROM transactions WHERE id = ?1;", id, id_len);

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

        // Record history: UPDATE on transactions.category
        if (old_cat) |old| {
            var old_buf: [4]u8 = undefined;
            const old_len = formatInt(&old_buf, @as(u32, @intCast(old))) orelse return;
            var new_buf: [4]u8 = undefined;
            const new_len = formatInt(&new_buf, @as(u32, category)) orelse return;
            self.recordHistory(1, "transactions", id[0..id_len], "category", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }
    }

    /// Update category for a transaction by ID (32-byte hex), using prepared statement.
    pub fn setCategoryById(self: *Db, id: *const [32]u8, category: Category) DbError!void {
        const sql = "UPDATE transactions SET category = ?1 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(@intFromEnum(category))) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, id, 32, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    // --- Debts ---

    pub fn insertDebt(self: *Db, id: [*]const u8, id_len: u32, name: [*]const u8, name_len: u32, total: i64, monthly: i64) DbError!void {
        const sql = "INSERT OR REPLACE INTO debts (id, name, total, paid, monthly, updated_at) VALUES (?1, ?2, ?3, 0, ?4, 0);";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, name, @intCast(name_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, total) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, monthly) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: INSERT on debts, new_val = debt JSON
        var val_buf: [512]u8 = undefined;
        const val_len = self.formatDebtJson(&val_buf, id[0..id_len], name[0..name_len], total, 0, monthly) orelse return;
        self.recordHistory(2, "debts", id[0..id_len], null, null, val_buf[0..val_len]) catch {};
    }

    pub fn markDebtPaid(self: *Db, id: [*]const u8, id_len: u32, amount: i64) DbError!void {
        // Capture old paid value for undo history
        const old_paid = self.queryInt64("SELECT paid FROM debts WHERE id = ?1;", id, id_len);

        const sql = "UPDATE debts SET paid = MIN(paid + ?1, total) WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int64(s, 1, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: UPDATE on debts.paid
        if (old_paid) |old| {
            // Query new paid value
            const new_paid = self.queryInt64("SELECT paid FROM debts WHERE id = ?1;", id, id_len) orelse return;
            var old_buf: [20]u8 = undefined;
            const old_len = formatSignedInt(&old_buf, old) orelse return;
            var new_buf: [20]u8 = undefined;
            const new_len = formatSignedInt(&new_buf, new_paid) orelse return;
            self.recordHistory(1, "debts", id[0..id_len], "paid", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }
    }

    pub fn deleteDebt(self: *Db, id: [*]const u8, id_len: u32) DbError!void {
        // Capture full debt row for undo history before deleting
        var old_buf: [512]u8 = undefined;
        const old_len = self.queryDebtJson(&old_buf, id, id_len);

        const sql = "DELETE FROM debts WHERE id = ?1;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: DELETE on debts, old_val = full debt JSON
        if (old_len) |ol| {
            self.recordHistory(3, "debts", id[0..id_len], null, old_buf[0..ol], null) catch {};
        }
    }

    // --- Undo/Redo helpers ---

    fn queryInt(self: *Db, sql: [*:0]const u8, id: [*]const u8, id_len: usize) ?i32 {
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;
        return c.sqlite3_column_int(s, 0);
    }

    fn queryInt64(self: *Db, sql: [*:0]const u8, id: [*]const u8, id_len: usize) ?i64 {
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;
        return c.sqlite3_column_int64(s, 0);
    }

    fn queryDebtJson(self: *Db, buf: *[512]u8, id: [*]const u8, id_len: u32) ?usize {
        const sql = "SELECT id, name, total, paid, monthly FROM debts WHERE id = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;

        const did_ptr = c.sqlite3_column_text(s, 0) orelse return null;
        const did_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const name_ptr = c.sqlite3_column_text(s, 1) orelse return null;
        const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
        const total = c.sqlite3_column_int64(s, 2);
        const paid = c.sqlite3_column_int64(s, 3);
        const monthly = c.sqlite3_column_int64(s, 4);

        return self.formatDebtJson(buf, did_ptr[0..did_len], name_ptr[0..name_len], total, paid, monthly);
    }

    fn formatDebtJson(_: *Db, buf: *[512]u8, id: []const u8, name: []const u8, total: i64, paid: i64, monthly: i64) ?usize {
        var pos: usize = 0;

        const p1 = "{\"id\":\"";
        if (pos + p1.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;

        pos += jsonEscapeString(buf[pos..], id) orelse return null;

        const p2 = "\",\"name\":\"";
        if (pos + p2.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        pos += jsonEscapeString(buf[pos..], name) orelse return null;

        const p3 = "\",\"total\":";
        if (pos + p3.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        pos += formatSignedInt(buf[pos..], total) orelse return null;

        const p4 = ",\"paid\":";
        if (pos + p4.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;

        pos += formatSignedInt(buf[pos..], paid) orelse return null;

        const p5 = ",\"monthly\":";
        if (pos + p5.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;

        pos += formatSignedInt(buf[pos..], monthly) orelse return null;

        if (pos >= buf.len) return null;
        buf[pos] = '}';
        pos += 1;

        return pos;
    }

    fn recordHistory(self: *Db, op: u8, tbl: []const u8, row_id: []const u8, col: ?[]const u8, old_val: ?[]const u8, new_val: ?[]const u8) DbError!void {
        // Clear redo stack
        self.exec("DELETE FROM undo_history WHERE undone = 1;") catch {};

        const sql = "INSERT INTO undo_history (op, tbl, row_id, col, old_val, new_val, undone) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(op)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(tbl.ptr), @intCast(tbl.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;

        // Unbound params default to NULL in SQLite, so only bind non-null values
        if (col) |cv| {
            if (c.sqlite3_bind_text(s, 4, @ptrCast(cv.ptr), @intCast(cv.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (old_val) |ov| {
            if (c.sqlite3_bind_text(s, 5, @ptrCast(ov.ptr), @intCast(ov.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (new_val) |nv| {
            if (c.sqlite3_bind_text(s, 6, @ptrCast(nv.ptr), @intCast(nv.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Prune to max entries
        self.exec("DELETE FROM undo_history WHERE seq NOT IN (SELECT seq FROM undo_history ORDER BY seq DESC LIMIT 50);") catch {};
    }

    /// Undo the last action. Returns JSON describing what was undone, written into buf.
    /// Returns null if nothing to undo.
    pub fn undo(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        // Find highest seq where undone=0
        const find_sql = "SELECT seq, op, tbl, row_id, col, old_val, new_val FROM undo_history WHERE undone = 0 ORDER BY seq DESC LIMIT 1;";
        var find_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, find_sql, -1, &find_stmt, null) != c.SQLITE_OK or find_stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(find_stmt.?);

        const fs = find_stmt.?;
        if (c.sqlite3_step(fs) != c.SQLITE_ROW) return null; // nothing to undo

        const seq = c.sqlite3_column_int64(fs, 0);
        const op: u8 = @intCast(c.sqlite3_column_int(fs, 1));
        const tbl_ptr = c.sqlite3_column_text(fs, 2) orelse return null;
        const tbl_len: usize = @intCast(c.sqlite3_column_bytes(fs, 2));
        const row_id_ptr = c.sqlite3_column_text(fs, 3) orelse return null;
        const row_id_len: usize = @intCast(c.sqlite3_column_bytes(fs, 3));
        const col_ptr = c.sqlite3_column_text(fs, 4);
        const col_len: usize = @intCast(c.sqlite3_column_bytes(fs, 4));
        const old_ptr = c.sqlite3_column_text(fs, 5);
        const old_len: usize = @intCast(c.sqlite3_column_bytes(fs, 5));

        const tbl = tbl_ptr[0..tbl_len];
        const row_id = row_id_ptr[0..row_id_len];

        // Apply reverse operation
        switch (op) {
            1 => {
                // UPDATE → restore old_val
                if (col_ptr == null or old_ptr == null) return null;
                const col = col_ptr.?[0..col_len];
                const old_val = old_ptr.?[0..old_len];
                try self.applyUpdate(tbl, row_id, col, old_val);
            },
            2 => {
                // INSERT → DELETE the row
                try self.applyDelete(tbl, row_id);
            },
            3 => {
                // DELETE → re-INSERT from old_val JSON
                if (old_ptr == null) return null;
                const old_val = old_ptr.?[0..old_len];
                try self.applyInsertDebt(old_val);
            },
            else => return null,
        }

        // Mark as undone
        try self.markUndone(seq, 1);

        // Format result JSON
        return self.formatUndoResult(buf, buf_len, op, tbl, row_id, col_ptr, col_len);
    }

    /// Redo the last undone action. Returns JSON describing what was redone.
    pub fn redo(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        // Find lowest seq where undone=1
        const find_sql = "SELECT seq, op, tbl, row_id, col, old_val, new_val FROM undo_history WHERE undone = 1 ORDER BY seq ASC LIMIT 1;";
        var find_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, find_sql, -1, &find_stmt, null) != c.SQLITE_OK or find_stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(find_stmt.?);

        const fs = find_stmt.?;
        if (c.sqlite3_step(fs) != c.SQLITE_ROW) return null; // nothing to redo

        const seq = c.sqlite3_column_int64(fs, 0);
        const op: u8 = @intCast(c.sqlite3_column_int(fs, 1));
        const tbl_ptr = c.sqlite3_column_text(fs, 2) orelse return null;
        const tbl_len: usize = @intCast(c.sqlite3_column_bytes(fs, 2));
        const row_id_ptr = c.sqlite3_column_text(fs, 3) orelse return null;
        const row_id_len: usize = @intCast(c.sqlite3_column_bytes(fs, 3));
        const col_ptr = c.sqlite3_column_text(fs, 4);
        const col_len: usize = @intCast(c.sqlite3_column_bytes(fs, 4));
        const new_ptr = c.sqlite3_column_text(fs, 6);
        const new_len: usize = @intCast(c.sqlite3_column_bytes(fs, 6));

        const tbl = tbl_ptr[0..tbl_len];
        const row_id = row_id_ptr[0..row_id_len];

        // Re-apply original operation
        switch (op) {
            1 => {
                // UPDATE → set new_val
                if (col_ptr == null or new_ptr == null) return null;
                const col = col_ptr.?[0..col_len];
                const new_val = new_ptr.?[0..new_len];
                try self.applyUpdate(tbl, row_id, col, new_val);
            },
            2 => {
                // INSERT → re-INSERT from new_val
                if (new_ptr == null) return null;
                const new_val = new_ptr.?[0..new_len];
                try self.applyInsertDebt(new_val);
            },
            3 => {
                // DELETE → DELETE the row
                try self.applyDelete(tbl, row_id);
            },
            else => return null,
        }

        // Mark as not undone
        try self.markUndone(seq, 0);

        return self.formatUndoResult(buf, buf_len, op, tbl, row_id, col_ptr, col_len);
    }

    fn applyUpdate(self: *Db, tbl: []const u8, row_id: []const u8, col: []const u8, val: []const u8) DbError!void {
        // Validate table+column against allowlist
        if (std.mem.eql(u8, tbl, "transactions") and std.mem.eql(u8, col, "category")) {
            // Parse integer value
            var int_val: i32 = 0;
            for (val) |ch| {
                if (ch >= '0' and ch <= '9') {
                    int_val = int_val * 10 + @as(i32, ch - '0');
                }
            }
            const sql = "UPDATE transactions SET category = ?1 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        } else if (std.mem.eql(u8, tbl, "debts") and std.mem.eql(u8, col, "paid")) {
            // Parse i64 value
            const int_val = parseI64(val);
            const sql = "UPDATE debts SET paid = ?1 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        }
        // Unknown table/col combos are silently ignored (safe)
    }

    fn applyDelete(self: *Db, tbl: []const u8, row_id: []const u8) DbError!void {
        if (std.mem.eql(u8, tbl, "debts")) {
            const sql = "DELETE FROM debts WHERE id = ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        }
    }

    fn applyInsertDebt(self: *Db, json: []const u8) DbError!void {
        // Parse debt JSON: {"id":"...","name":"...","total":N,"paid":N,"monthly":N}
        const id = jsonExtractStringFromSlice(json, "\"id\"") orelse return DbError.ExecFailed;
        const name = jsonExtractStringFromSlice(json, "\"name\"") orelse return DbError.ExecFailed;
        const total = jsonExtractI64FromSlice(json, "\"total\"");
        const paid = jsonExtractI64FromSlice(json, "\"paid\"");
        const monthly = jsonExtractI64FromSlice(json, "\"monthly\"");

        const sql = "INSERT OR REPLACE INTO debts (id, name, total, paid, monthly, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, 0);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id.ptr), @intCast(id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, total) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, paid) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, monthly) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn markUndone(self: *Db, seq: i64, val: u8) DbError!void {
        const sql = "UPDATE undo_history SET undone = ?1 WHERE seq = ?2;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(val)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, seq) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn formatUndoResult(_: *Db, buf: [*]u8, buf_len: usize, op: u8, tbl: []const u8, row_id: []const u8, col_ptr: ?[*]const u8, col_len: usize) ?usize {
        var pos: usize = 0;
        const op_str = switch (op) {
            1 => "update",
            2 => "insert",
            3 => "delete",
            else => "unknown",
        };

        // {"op":"...","table":"...","row_id":"..."}
        const p1 = "{\"op\":\"";
        if (pos + p1.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;

        if (pos + op_str.len > buf_len) return null;
        @memcpy(buf[pos .. pos + op_str.len], op_str);
        pos += op_str.len;

        const p2 = "\",\"table\":\"";
        if (pos + p2.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        if (pos + tbl.len > buf_len) return null;
        @memcpy(buf[pos .. pos + tbl.len], tbl);
        pos += tbl.len;

        const p3 = "\",\"row_id\":\"";
        if (pos + p3.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        if (pos + row_id.len > buf_len) return null;
        @memcpy(buf[pos .. pos + row_id.len], row_id);
        pos += row_id.len;

        if (col_ptr != null and col_len > 0) {
            const p4 = "\",\"column\":\"";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;

            const col = col_ptr.?[0..col_len];
            if (pos + col.len > buf_len) return null;
            @memcpy(buf[pos .. pos + col.len], col);
            pos += col.len;
        }

        const p5 = "\"}";
        if (pos + p5.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;

        return pos;
    }

    pub fn getDebtsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, name, total, paid, monthly FROM debts ORDER BY name;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const total = c.sqlite3_column_int64(s, 2);
            const paid = c.sqlite3_column_int64(s, 3);
            const monthly = c.sqlite3_column_int64(s, 4);

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            // {"id":"...","name":"...","total":...,"paid":...,"monthly":...}
            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;

            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            const p2 = "\",\"name\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;

            pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

            const p3 = "\",\"total\":";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;

            pos += formatAmount(buf[pos..buf_len], total) orelse return null;

            const p4 = ",\"paid\":";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;

            pos += formatAmount(buf[pos..buf_len], paid) orelse return null;

            const p5 = ",\"monthly\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;

            pos += formatAmount(buf[pos..buf_len], monthly) orelse return null;

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;

            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
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

pub fn formatSignedInt(buf: []u8, value: i64) ?usize {
    var pos: usize = 0;
    var val = value;
    if (val < 0) {
        if (pos >= buf.len) return null;
        buf[pos] = '-';
        pos += 1;
        val = -val;
    }
    pos += formatInt(buf[pos..], @as(u64, @intCast(val))) orelse return null;
    return pos;
}

fn parseI64(s: []const u8) i64 {
    var result: i64 = 0;
    var negative = false;
    for (s) |ch| {
        if (ch == '-') {
            negative = true;
        } else if (ch >= '0' and ch <= '9') {
            result = result * 10 + @as(i64, ch - '0');
        }
    }
    return if (negative) -result else result;
}

fn jsonExtractStringFromSlice(json: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = findInSlice(json, key) orelse return null;
    var i = key_pos + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {}
    if (i >= json.len) return null;
    return json[start..i];
}

fn jsonExtractI64FromSlice(json: []const u8, key: []const u8) i64 {
    const key_pos = findInSlice(json, key) orelse return 0;
    var i = key_pos + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    var negative = false;
    if (i < json.len and json[i] == '-') {
        negative = true;
        i += 1;
    }
    var result: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        result = result * 10 + @as(i64, json[i] - '0');
    }
    return if (negative) -result else result;
}

fn findInSlice(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

pub fn formatAmount(buf: []u8, cents: i64) ?usize {
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

pub fn formatInt(buf: []u8, value: anytype) ?usize {
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

pub fn jsonEscapeString(buf: []u8, src: []const u8) ?usize {
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
