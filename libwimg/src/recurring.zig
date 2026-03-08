const std = @import("std");
const db_mod = @import("db.zig");
const c = @import("sqlite_c.zig");

const Db = db_mod.Db;
const DbError = db_mod.DbError;

// --- Merchant normalization ---

/// Known merchant mappings (uppercase pattern → display name)
const KnownMerchant = struct {
    pattern: []const u8,
    name: []const u8,
};

const known_merchants = [_]KnownMerchant{
    .{ .pattern = "NETFLIX", .name = "Netflix" },
    .{ .pattern = "SPOTIFY", .name = "Spotify" },
    .{ .pattern = "AMAZON PRIME", .name = "Amazon Prime" },
    .{ .pattern = "AMAZON", .name = "Amazon" },
    .{ .pattern = "APPLE.COM", .name = "Apple" },
    .{ .pattern = "GOOGLE", .name = "Google" },
    .{ .pattern = "DISNEY", .name = "Disney+" },
    .{ .pattern = "REWE", .name = "REWE" },
    .{ .pattern = "EDEKA", .name = "EDEKA" },
    .{ .pattern = "LIDL", .name = "Lidl" },
    .{ .pattern = "ALDI", .name = "Aldi" },
    .{ .pattern = "DM DROGERIE", .name = "dm" },
    .{ .pattern = "PAYPAL", .name = "PayPal" },
    .{ .pattern = "MIETE", .name = "Miete" },
    .{ .pattern = "STADTWERKE", .name = "Stadtwerke" },
    .{ .pattern = "VODAFONE", .name = "Vodafone" },
    .{ .pattern = "TELEKOM", .name = "Telekom" },
    .{ .pattern = "O2", .name = "o2" },
    .{ .pattern = "KLARNA", .name = "Klarna" },
    .{ .pattern = "CHECK24", .name = "Check24" },
    .{ .pattern = "GEZ", .name = "Rundfunkbeitrag" },
    .{ .pattern = "RUNDFUNK", .name = "Rundfunkbeitrag" },
    .{ .pattern = "BEITRAGSSERVICE", .name = "Rundfunkbeitrag" },
    .{ .pattern = "YOUTUBE", .name = "YouTube" },
    .{ .pattern = "CHATGPT", .name = "ChatGPT" },
    .{ .pattern = "OPENAI", .name = "OpenAI" },
    .{ .pattern = "GITHUB", .name = "GitHub" },
    .{ .pattern = "HETZNER", .name = "Hetzner" },
    .{ .pattern = "IONOS", .name = "IONOS" },
    .{ .pattern = "CLEVER FIT", .name = "clever fit" },
    .{ .pattern = "MCFIT", .name = "McFit" },
    .{ .pattern = "FIT STAR", .name = "FitStar" },
    .{ .pattern = "FITX", .name = "FitX" },
};

/// Suffixes to strip from merchant names
const strip_suffixes = [_][]const u8{
    ".COM",         ".DE",      ".SE",     ".NL",   " GMBH", " SAGT DANKE", " AG", " SE",
    " DEUTSCHLAND", " GERMANY", " EUROPE", " SARL", " LTD",  " INC",
};

/// Normalize a transaction description to a merchant name.
/// Returns the number of bytes written into out_buf.
pub fn normalizeMerchant(desc: []const u8, out_buf: []u8) ?usize {
    if (desc.len == 0) return null;

    // Uppercase into temp buffer
    var upper: [512]u8 = undefined;
    const upper_len = @min(desc.len, upper.len);
    for (desc[0..upper_len], 0..) |ch, i| {
        upper[i] = asciiUpper(ch);
    }
    var working = upper[0..upper_len];

    // Check known merchants first
    for (known_merchants) |km| {
        if (containsSubstring(working, km.pattern)) {
            if (km.name.len > out_buf.len) return null;
            @memcpy(out_buf[0..km.name.len], km.name);
            return km.name.len;
        }
    }

    // Strip suffixes
    for (strip_suffixes) |suffix| {
        if (working.len > suffix.len) {
            const tail = working[working.len - suffix.len ..];
            if (std.mem.eql(u8, tail, suffix)) {
                working = working[0 .. working.len - suffix.len];
            }
        }
    }

    // Take first meaningful token (skip leading numbers/dates)
    var start: usize = 0;
    // Skip date-like prefixes (e.g. "2026-03-01 " or "01.03.2026 ")
    if (working.len > 10) {
        var digits_or_sep: usize = 0;
        for (working) |ch| {
            if ((ch >= '0' and ch <= '9') or ch == '-' or ch == '.' or ch == '/') {
                digits_or_sep += 1;
            } else break;
        }
        if (digits_or_sep >= 6 and digits_or_sep < working.len) {
            start = digits_or_sep;
            // Skip trailing spaces
            while (start < working.len and working[start] == ' ') : (start += 1) {}
        }
    }

    // Find end of first token (or take up to 30 chars)
    var end = start;
    var token_count: usize = 0;
    while (end < working.len and token_count < 3) : (end += 1) {
        if (working[end] == '/' or working[end] == '\\' or working[end] == ',' or working[end] == ';') break;
        if (working[end] == ' ') token_count += 1;
    }

    // Trim trailing spaces
    while (end > start and working[end - 1] == ' ') : (end -= 1) {}

    const result = working[start..end];
    if (result.len == 0) return null;
    if (result.len > out_buf.len) return null;
    @memcpy(out_buf[0..result.len], result);
    return result.len;
}

fn asciiUpper(ch: u8) u8 {
    return if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
}

fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// --- Date arithmetic ---

const DateTriple = struct {
    year: i32,
    month: i32,
    day: i32,
};

fn daysBetween(a: DateTriple, b: DateTriple) i32 {
    return julianDay(b) - julianDay(a);
}

fn julianDay(d: DateTriple) i32 {
    // Rata Die calculation (days since 0001-01-01)
    var y = d.year;
    var m = d.month;
    if (m <= 2) {
        y -= 1;
        m += 12;
    }
    return 365 * y + @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400) + @divTrunc(306 * (m + 1), 10) + d.day - 428;
}

fn addDays(d: DateTriple, days: i32) DateTriple {
    const jd = julianDay(d) + days;
    return fromRataDie(jd);
}

fn fromRataDie(rd: i32) DateTriple {
    // Inverse of julianDay — convert rata die back to date
    // Using a well-known algorithm
    const y0 = @divTrunc(10000 * @as(i64, rd) + 14780, 3652425);
    const y0_i32: i32 = @intCast(y0);
    var doy = rd - (365 * y0_i32 + @divTrunc(y0_i32, 4) - @divTrunc(y0_i32, 100) + @divTrunc(y0_i32, 400));
    if (doy < 0) {
        const y1 = y0_i32 - 1;
        doy = rd - (365 * y1 + @divTrunc(y1, 4) - @divTrunc(y1, 100) + @divTrunc(y1, 400));
        const mi = @divTrunc(100 * doy + 52, 3060);
        const month = if (mi < 10) mi + 3 else mi - 9;
        const year = if (month <= 2) y1 + 1 else y1;
        const day = doy - @divTrunc(mi * 306 + 5, 10) + 1;
        return .{ .year = year, .month = month, .day = day };
    }
    const mi = @divTrunc(100 * doy + 52, 3060);
    const month = if (mi < 10) mi + 3 else mi - 9;
    const year = if (month <= 2) y0_i32 + 1 else y0_i32;
    const day = doy - @divTrunc(mi * 306 + 5, 10) + 1;
    return .{ .year = year, .month = month, .day = day };
}

fn formatDateStr(buf: []u8, d: DateTriple) ?usize {
    if (buf.len < 10) return null;
    const y: u32 = @intCast(d.year);
    const m: u32 = @intCast(d.month);
    const da: u32 = @intCast(d.day);
    buf[0] = '0' + @as(u8, @intCast(y / 1000));
    buf[1] = '0' + @as(u8, @intCast((y / 100) % 10));
    buf[2] = '0' + @as(u8, @intCast((y / 10) % 10));
    buf[3] = '0' + @as(u8, @intCast(y % 10));
    buf[4] = '-';
    buf[5] = '0' + @as(u8, @intCast(m / 10));
    buf[6] = '0' + @as(u8, @intCast(m % 10));
    buf[7] = '-';
    buf[8] = '0' + @as(u8, @intCast(da / 10));
    buf[9] = '0' + @as(u8, @intCast(da % 10));
    return 10;
}

// --- Interval classification ---

const Interval = enum {
    weekly,
    monthly,
    quarterly,
    annual,
    unknown,

    pub fn label(self: Interval) []const u8 {
        return switch (self) {
            .weekly => "weekly",
            .monthly => "monthly",
            .quarterly => "quarterly",
            .annual => "annual",
            .unknown => "unknown",
        };
    }

    pub fn typicalDays(self: Interval) i32 {
        return switch (self) {
            .weekly => 7,
            .monthly => 30,
            .quarterly => 91,
            .annual => 365,
            .unknown => 0,
        };
    }
};

fn classifyInterval(median_days: i32) Interval {
    if (median_days >= 5 and median_days <= 9) return .weekly;
    if (median_days >= 25 and median_days <= 35) return .monthly;
    if (median_days >= 85 and median_days <= 100) return .quarterly;
    if (median_days >= 350 and median_days <= 380) return .annual;
    return .unknown;
}

// --- Detection algorithm ---

const MAX_TX_PER_MERCHANT = 64;
const MAX_MERCHANTS = 256;
const MIN_OCCURRENCES = 3;

const TxEntry = struct {
    date: DateTriple,
    amount: i64,
    category: i32,
};

const MerchantBucket = struct {
    name: [128]u8 = undefined,
    name_len: usize = 0,
    entries: [MAX_TX_PER_MERCHANT]TxEntry = undefined,
    entry_count: usize = 0,
    used: bool = false,
};

/// Detect recurring patterns from transaction history.
/// Returns the number of patterns detected.
pub fn detectRecurring(database: *Db) DbError!i32 {
    // Clear existing patterns
    try database.clearRecurring();

    const sql =
        \\SELECT description, amount_cents, date_year, date_month, date_day, category
        \\FROM transactions WHERE excluded = 0
        \\ORDER BY date_year ASC, date_month ASC, date_day ASC;
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(database.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt.?);
    const s = stmt.?;

    // Hash map: normalized merchant → entries (bounded, linear probing)
    var buckets: [MAX_MERCHANTS]MerchantBucket = @splat(MerchantBucket{});
    var bucket_count: usize = 0;

    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const desc_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const amount = c.sqlite3_column_int64(s, 1);
        const year = c.sqlite3_column_int(s, 2);
        const month = c.sqlite3_column_int(s, 3);
        const day = c.sqlite3_column_int(s, 4);
        const category = c.sqlite3_column_int(s, 5);

        // Normalize merchant
        var norm_buf: [128]u8 = undefined;
        const norm_len = normalizeMerchant(desc_ptr[0..desc_len], &norm_buf) orelse continue;
        const norm = norm_buf[0..norm_len];

        // Find or create bucket for this merchant
        const slot = findOrCreateBucket(&buckets, &bucket_count, norm) orelse continue;
        const b = &buckets[slot];

        // Add entry (sorted by date since query is ORDER BY date ASC)
        if (b.entry_count < MAX_TX_PER_MERCHANT) {
            b.entries[b.entry_count] = .{
                .date = .{ .year = year, .month = month, .day = day },
                .amount = amount,
                .category = category,
            };
            b.entry_count += 1;
        }
    }

    // Process all merchant groups
    var detected: i32 = 0;
    for (&buckets) |*b| {
        if (!b.used or b.entry_count < MIN_OCCURRENCES) continue;
        if (processGroup(database, b.name[0..b.name_len], b.entries[0..b.entry_count]) catch false) {
            detected += 1;
        }
    }

    return detected;
}

/// Simple hash for merchant name (FNV-1a)
fn merchantHash(name: []const u8) u32 {
    var h: u32 = 2166136261;
    for (name) |byte| {
        h ^= byte;
        h *%= 16777619;
    }
    return h;
}

/// Find existing bucket or create new one. Returns slot index or null if full.
fn findOrCreateBucket(buckets: *[MAX_MERCHANTS]MerchantBucket, count: *usize, name: []const u8) ?usize {
    const start = merchantHash(name) % MAX_MERCHANTS;
    var idx = start;
    while (true) {
        const b = &buckets[idx];
        if (b.used and b.name_len == name.len and std.mem.eql(u8, b.name[0..b.name_len], name)) {
            return idx; // Found existing
        }
        if (!b.used) {
            if (count.* >= MAX_MERCHANTS - 1) return null; // Table full
            b.used = true;
            @memcpy(b.name[0..name.len], name);
            b.name_len = name.len;
            b.entry_count = 0;
            count.* += 1;
            return idx; // Created new
        }
        idx = (idx + 1) % MAX_MERCHANTS;
        if (idx == start) return null; // Wrapped around, table full
    }
}

fn processGroup(database: *Db, merchant: []const u8, entries: []const TxEntry) DbError!bool {
    if (entries.len < MIN_OCCURRENCES) return false;

    // Calculate intervals between consecutive dates
    var intervals: [MAX_TX_PER_MERCHANT]i32 = undefined;
    var interval_count: usize = 0;
    for (1..entries.len) |i| {
        const days = daysBetween(entries[i - 1].date, entries[i].date);
        if (days > 0) {
            intervals[interval_count] = days;
            interval_count += 1;
        }
    }

    if (interval_count < 2) return false;

    // Find median interval
    // Simple selection sort on first interval_count elements
    var sorted: [MAX_TX_PER_MERCHANT]i32 = undefined;
    @memcpy(sorted[0..interval_count], intervals[0..interval_count]);
    for (0..interval_count) |i| {
        var min_idx = i;
        for (i + 1..interval_count) |j| {
            if (sorted[j] < sorted[min_idx]) min_idx = j;
        }
        const tmp = sorted[i];
        sorted[i] = sorted[min_idx];
        sorted[min_idx] = tmp;
    }
    const median = sorted[interval_count / 2];

    // Classify interval
    const interval = classifyInterval(median);
    if (interval == .unknown) return false;

    // Check consistency: ≥60% of intervals within range
    var in_range: usize = 0;
    const lo: i32 = switch (interval) {
        .weekly => 5,
        .monthly => 25,
        .quarterly => 85,
        .annual => 350,
        .unknown => 0,
    };
    const hi: i32 = switch (interval) {
        .weekly => 9,
        .monthly => 35,
        .quarterly => 100,
        .annual => 380,
        .unknown => 0,
    };
    for (intervals[0..interval_count]) |iv| {
        if (iv >= lo and iv <= hi) in_range += 1;
    }
    if (in_range * 100 < interval_count * 60) return false;

    // Check amount consistency: ≥70% within ±10% of median amount
    var amounts: [MAX_TX_PER_MERCHANT]i64 = undefined;
    for (entries, 0..) |e, i| {
        amounts[i] = if (e.amount < 0) -e.amount else e.amount;
    }
    // Sort amounts for median
    for (0..entries.len) |i| {
        var min_idx = i;
        for (i + 1..entries.len) |j| {
            if (amounts[j] < amounts[min_idx]) min_idx = j;
        }
        const tmp = amounts[i];
        amounts[i] = amounts[min_idx];
        amounts[min_idx] = tmp;
    }
    const median_amount = amounts[entries.len / 2];

    var amount_in_range: usize = 0;
    const amt_lo = @divTrunc(median_amount * 90, 100);
    const amt_hi = @divTrunc(median_amount * 110, 100);
    for (entries) |e| {
        const abs_amt = if (e.amount < 0) -e.amount else e.amount;
        if (abs_amt >= amt_lo and abs_amt <= amt_hi) amount_in_range += 1;
    }
    if (amount_in_range * 100 < entries.len * 70) return false;

    // Compute values
    const last_entry = entries[entries.len - 1];
    const prev_entry = entries[entries.len - 2];
    const last_amount = last_entry.amount;
    const prev_amount_val = prev_entry.amount;
    const category = last_entry.category;

    // Price change detection: >50 cents difference
    const prev_amount: ?i64 = if (entries.len >= 2)
        prev_amount_val
    else
        null;

    // Calculate next_due
    const next_due_date = addDays(last_entry.date, interval.typicalDays());

    // Generate deterministic ID from merchant hash
    var id_buf: [32]u8 = undefined;
    hashMerchantId(merchant, &id_buf);

    // Format last_seen date
    var ls_buf: [10]u8 = undefined;
    const ls_len = formatDateStr(&ls_buf, last_entry.date) orelse return false;

    // Format next_due date
    var nd_buf: [10]u8 = undefined;
    const nd_len = formatDateStr(&nd_buf, next_due_date) orelse return false;

    const intv_label = interval.label();

    try database.insertOrUpdateRecurring(
        &id_buf,
        32,
        merchant.ptr,
        @intCast(merchant.len),
        last_amount,
        intv_label.ptr,
        @intCast(intv_label.len),
        category,
        &ls_buf,
        @intCast(ls_len),
        &nd_buf,
        @intCast(nd_len),
        prev_amount,
    );

    return true;
}

fn hashMerchantId(merchant: []const u8, out: *[32]u8) void {
    // Simple hash → hex string for deterministic ID
    var hash: u64 = 5381;
    for (merchant) |ch| {
        hash = hash *% 33 +% ch;
    }
    const hex_chars = "0123456789abcdef";
    // Fill 32-char ID: repeat hash bytes as hex
    var h = hash;
    for (0..16) |i| {
        out[i * 2] = hex_chars[@intCast((h >> 4) & 0x0F)];
        out[i * 2 + 1] = hex_chars[@intCast(h & 0x0F)];
        h = h *% 2654435761 +% @as(u64, @intCast(i));
    }
}

// --- Tests ---

test "normalizeMerchant: known merchants" {
    var buf: [128]u8 = undefined;

    const len1 = normalizeMerchant("NETFLIX.COM/BILL", &buf).?;
    try std.testing.expectEqualStrings("Netflix", buf[0..len1]);

    const len2 = normalizeMerchant("Spotify AB Stockholm", &buf).?;
    try std.testing.expectEqualStrings("Spotify", buf[0..len2]);

    const len3 = normalizeMerchant("REWE SAGT DANKE 1234", &buf).?;
    try std.testing.expectEqualStrings("REWE", buf[0..len3]);

    const len4 = normalizeMerchant("RUNDFUNK ARD ZDF", &buf).?;
    try std.testing.expectEqualStrings("Rundfunkbeitrag", buf[0..len4]);
}

test "normalizeMerchant: generic merchants" {
    var buf: [128]u8 = undefined;

    const len1 = normalizeMerchant("MUELLER DROGERIE GMBH", &buf).?;
    // Should strip GMBH
    try std.testing.expect(len1 > 0);
    // Result should be uppercase (since it's not a known merchant)
    try std.testing.expect(buf[0] == 'M');
}

test "classifyInterval" {
    try std.testing.expectEqual(Interval.weekly, classifyInterval(7));
    try std.testing.expectEqual(Interval.monthly, classifyInterval(30));
    try std.testing.expectEqual(Interval.monthly, classifyInterval(31));
    try std.testing.expectEqual(Interval.quarterly, classifyInterval(91));
    try std.testing.expectEqual(Interval.annual, classifyInterval(365));
    try std.testing.expectEqual(Interval.unknown, classifyInterval(15));
    try std.testing.expectEqual(Interval.unknown, classifyInterval(200));
}

test "daysBetween" {
    const d1 = DateTriple{ .year = 2026, .month = 1, .day = 1 };
    const d2 = DateTriple{ .year = 2026, .month = 2, .day = 1 };
    try std.testing.expectEqual(@as(i32, 31), daysBetween(d1, d2));

    const d3 = DateTriple{ .year = 2026, .month = 1, .day = 1 };
    const d4 = DateTriple{ .year = 2026, .month = 1, .day = 8 };
    try std.testing.expectEqual(@as(i32, 7), daysBetween(d3, d4));
}

test "formatDateStr" {
    var buf: [10]u8 = undefined;
    const d = DateTriple{ .year = 2026, .month = 3, .day = 8 };
    const len = formatDateStr(&buf, d).?;
    try std.testing.expectEqual(@as(usize, 10), len);
    try std.testing.expectEqualStrings("2026-03-08", &buf);
}

test "hashMerchantId produces 32 hex chars" {
    var id: [32]u8 = undefined;
    hashMerchantId("Netflix", &id);
    for (id) |ch| {
        try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
    }
}
