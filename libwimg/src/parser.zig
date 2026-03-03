const std = @import("std");
const types = @import("types.zig");

const Transaction = types.Transaction;
const Date = types.Date;
const Category = types.Category;
const ImportResult = types.ImportResult;

pub const ParseError = error{
    InvalidDate,
    InvalidAmount,
    TooFewColumns,
    DescriptionTooLong,
};

pub const CsvFormat = enum(u8) {
    unknown = 0,
    comdirect = 1,
    trade_republic = 2,
    scalable_capital = 3,

    pub fn name(self: CsvFormat) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .comdirect => "comdirect",
            .trade_republic => "trade_republic",
            .scalable_capital => "scalable_capital",
        };
    }
};

/// Auto-detect CSV format from the first few lines.
pub fn detectCsvFormat(data: []const u8) CsvFormat {
    // Look at first 1KB for header clues
    const check_len = @min(data.len, 1024);
    const header = data[0..check_len];

    // Comdirect: German, semicolons, starts with "Buchungstag" or metadata rows
    if (containsAscii(header, "Buchungstag") or containsAscii(header, "Umsatz in EUR")) {
        return .comdirect;
    }

    // Trade Republic: "Date","Type","Description" pattern (comma-separated)
    if (containsAscii(header, "\"Date\"") and containsAscii(header, "\"Type\"")) {
        return .trade_republic;
    }
    // Also: Date,Type,Description (unquoted)
    if (startsWithHeader(header, "Date,Type,")) {
        return .trade_republic;
    }

    // Scalable Capital: semicolons, "Datum" or "Buchungsdatum"
    if (containsAscii(header, "Buchungsdatum") and containsAscii(header, "Betrag")) {
        return .scalable_capital;
    }

    // Fallback: check if semicolons with dd.MM.yyyy → likely Comdirect
    if (containsSemicolon(header) and containsGermanDate(header)) {
        return .comdirect;
    }

    return .unknown;
}

/// Parse CSV, auto-detecting the format. Returns the detected format.
pub fn parseCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) CsvFormat {
    const format = detectCsvFormat(data);

    switch (format) {
        .comdirect => parseComdirectCsv(data, out_txns, out_result),
        .trade_republic => parseTradeRepublicCsv(data, out_txns, out_result),
        .scalable_capital => parseScalableCapitalCsv(data, out_txns, out_result),
        .unknown => {
            // Try Comdirect as default
            parseComdirectCsv(data, out_txns, out_result);
        },
    }

    return format;
}

// ============================================================
// Comdirect Parser
// ============================================================

/// Parse a Comdirect CSV export.
/// Format: semicolon-delimited, ISO-8859-1 encoded, dd.MM.yyyy dates,
/// German number format (1.234,56).
pub fn parseComdirectCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        // Skip header/metadata lines — a transaction line starts with a date dd.MM.yyyy
        if (!looksLikeDateStart(line)) continue;

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.errors += 1;
            continue;
        }

        if (parseComdirectLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseComdirectLine(line: []const u8) ?Transaction {
    var cols: [10][]const u8 = undefined;
    var col_count: usize = 0;

    var col_iter = std.mem.splitScalar(u8, line, ';');
    while (col_iter.next()) |col| {
        if (col_count >= 10) break;
        cols[col_count] = col;
        col_count += 1;
    }

    if (col_count < 5) return null;

    const date = parseGermanDate(trim(cols[0])) orelse return null;
    const description_raw = trim(cols[3]);
    const amount_str = trim(cols[4]);
    const amount = parseGermanAmount(amount_str) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount);
    return txn;
}

// ============================================================
// Trade Republic Parser
// ============================================================

/// Parse a Trade Republic CSV export.
/// Format: comma-delimited, UTF-8, YYYY-MM-DD dates, English decimal format.
/// Columns: Date,Type,Description,Amount (may vary)
fn parseTradeRepublicCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;
    var header_skipped = false;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        // Skip header line
        if (!header_skipped) {
            if (containsAscii(line, "Date") or containsAscii(line, "date")) {
                header_skipped = true;
                continue;
            }
            header_skipped = true;
        }

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.errors += 1;
            continue;
        }

        if (parseTradeRepublicLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseTradeRepublicLine(line: []const u8) ?Transaction {
    // CSV with possible quoted fields — simple comma split (no embedded commas in fields expected)
    var cols: [10][]const u8 = undefined;
    var col_count: usize = 0;

    var col_iter = std.mem.splitScalar(u8, line, ',');
    while (col_iter.next()) |col| {
        if (col_count >= 10) break;
        cols[col_count] = stripQuotes(trim(col));
        col_count += 1;
    }

    // Need at least: Date, Type, Description, Amount
    if (col_count < 4) return null;

    const date = parseIsoDate(cols[0]) orelse return null;
    // cols[1] = type (e.g., "Purchase", "Dividend", "Deposit")
    const description_raw = cols[2];
    const amount = parseEnglishAmount(cols[3]) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount);
    return txn;
}

// ============================================================
// Scalable Capital Parser
// ============================================================

/// Parse a Scalable Capital CSV export.
/// Format: semicolon-delimited, UTF-8, dd.MM.yyyy or YYYY-MM-DD dates.
fn parseScalableCapitalCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;
    var header_skipped = false;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        if (!header_skipped) {
            if (containsAscii(line, "Buchungsdatum") or containsAscii(line, "Datum") or containsAscii(line, "Date")) {
                header_skipped = true;
                continue;
            }
            header_skipped = true;
        }

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.errors += 1;
            continue;
        }

        if (parseScalableLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseScalableLine(line: []const u8) ?Transaction {
    var cols: [10][]const u8 = undefined;
    var col_count: usize = 0;

    var col_iter = std.mem.splitScalar(u8, line, ';');
    while (col_iter.next()) |col| {
        if (col_count >= 10) break;
        cols[col_count] = stripQuotes(trim(col));
        col_count += 1;
    }

    // Need at least: Buchungsdatum, Beschreibung/Typ, Betrag
    if (col_count < 3) return null;

    // Try ISO date first, then German date
    const date = parseIsoDate(cols[0]) orelse parseGermanDate(cols[0]) orelse return null;

    // Description is typically in column 1 or 2
    const description_raw = if (col_count >= 4) cols[2] else cols[1];
    // Amount is the last meaningful column
    const amount_str = if (col_count >= 4) cols[3] else cols[2];
    const amount = parseGermanAmount(amount_str) orelse parseEnglishAmount(amount_str) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount);
    return txn;
}

// ============================================================
// Date Parsers
// ============================================================

/// Parse "dd.MM.yyyy" into a Date struct.
fn parseGermanDate(s: []const u8) ?Date {
    const clean = stripQuotes(s);
    if (clean.len < 10) return null;

    const day = parseTwoDigit(clean[0..2]) orelse return null;
    if (clean[2] != '.') return null;
    const month = parseTwoDigit(clean[3..5]) orelse return null;
    if (clean[5] != '.') return null;
    const year = parseFourDigit(clean[6..10]) orelse return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    return Date{ .year = year, .month = month, .day = day };
}

/// Parse "YYYY-MM-DD" into a Date struct.
fn parseIsoDate(s: []const u8) ?Date {
    const clean = stripQuotes(s);
    if (clean.len < 10) return null;

    const year = parseFourDigit(clean[0..4]) orelse return null;
    if (clean[4] != '-') return null;
    const month = parseTwoDigit(clean[5..7]) orelse return null;
    if (clean[7] != '-') return null;
    const day = parseTwoDigit(clean[8..10]) orelse return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    return Date{ .year = year, .month = month, .day = day };
}

// ============================================================
// Amount Parsers
// ============================================================

/// Parse German-format amount: "1.234,56" or "-1.234,56"
fn parseGermanAmount(s: []const u8) ?i64 {
    const clean = stripQuotes(s);
    if (clean.len == 0) return null;

    var negative = false;
    var start: usize = 0;
    if (clean[0] == '-') {
        negative = true;
        start = 1;
    } else if (clean[0] == '+') {
        start = 1;
    }

    var whole: i64 = 0;
    var frac: i64 = 0;
    var in_frac = false;
    var frac_digits: u8 = 0;

    for (clean[start..]) |ch| {
        if (ch == '.') {
            continue; // Thousands separator
        } else if (ch == ',') {
            in_frac = true;
            continue;
        } else if (ch >= '0' and ch <= '9') {
            if (in_frac) {
                if (frac_digits < 2) {
                    frac = frac * 10 + (ch - '0');
                    frac_digits += 1;
                }
            } else {
                whole = whole * 10 + (ch - '0');
            }
        } else if (ch == ' ' or ch == '"') {
            continue;
        } else {
            return null;
        }
    }

    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

/// Parse English-format amount: "1234.56" or "-1234.56"
fn parseEnglishAmount(s: []const u8) ?i64 {
    const clean = stripQuotes(trim(s));
    if (clean.len == 0) return null;

    var negative = false;
    var start: usize = 0;
    if (clean[0] == '-') {
        negative = true;
        start = 1;
    } else if (clean[0] == '+') {
        start = 1;
    }

    var whole: i64 = 0;
    var frac: i64 = 0;
    var in_frac = false;
    var frac_digits: u8 = 0;

    for (clean[start..]) |ch| {
        if (ch == ',') {
            continue; // Thousands separator in English format
        } else if (ch == '.') {
            in_frac = true;
            continue;
        } else if (ch >= '0' and ch <= '9') {
            if (in_frac) {
                if (frac_digits < 2) {
                    frac = frac * 10 + (ch - '0');
                    frac_digits += 1;
                }
            } else {
                whole = whole * 10 + (ch - '0');
            }
        } else if (ch == ' ' or ch == '"') {
            continue;
        } else {
            return null;
        }
    }

    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

// ============================================================
// Hash + Helpers
// ============================================================

fn computeHash(date: Date, description: []const u8, amount: i64) [32]u8 {
    var hasher = std.hash.Fnv1a_128.init();

    var date_buf: [10]u8 = undefined;
    date_buf[0] = @intCast(date.day / 10 + '0');
    date_buf[1] = @intCast(date.day % 10 + '0');
    date_buf[2] = '.';
    date_buf[3] = @intCast(date.month / 10 + '0');
    date_buf[4] = @intCast(date.month % 10 + '0');
    date_buf[5] = '.';
    date_buf[6] = @intCast(date.year / 1000 + '0');
    date_buf[7] = @intCast((date.year / 100) % 10 + '0');
    date_buf[8] = @intCast((date.year / 10) % 10 + '0');
    date_buf[9] = @intCast(date.year % 10 + '0');
    hasher.update(&date_buf);

    hasher.update(description);

    const amt_bytes: [8]u8 = @bitCast(amount);
    hasher.update(&amt_bytes);

    const hash_val = hasher.final();
    const hash_bytes: [16]u8 = @bitCast(hash_val);

    const hex = "0123456789abcdef";
    var result: [32]u8 = undefined;
    for (hash_bytes, 0..) |byte, i| {
        result[i * 2] = hex[byte >> 4];
        result[i * 2 + 1] = hex[byte & 0x0f];
    }
    return result;
}

fn splitLines(data: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, data, '\n');
}

fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn stripQuotes(s: []const u8) []const u8 {
    var result = s;
    if (result.len >= 2 and result[0] == '"' and result[result.len - 1] == '"') {
        result = result[1 .. result.len - 1];
    }
    return result;
}

fn looksLikeDateStart(line: []const u8) bool {
    const s = trim(line);
    if (s.len < 10) return false;
    const c0 = s[0];
    const c1 = s[1];
    if (c0 == '"') {
        if (s.len < 12) return false;
        return s[1] >= '0' and s[1] <= '9' and s[2] >= '0' and s[2] <= '9' and s[3] == '.';
    }
    return c0 >= '0' and c0 <= '9' and c1 >= '0' and c1 <= '9' and s[2] == '.';
}

fn parseTwoDigit(s: []const u8) ?u8 {
    if (s.len < 2) return null;
    const d0 = s[0];
    const d1 = s[1];
    if (d0 < '0' or d0 > '9' or d1 < '0' or d1 > '9') return null;
    return (d0 - '0') * 10 + (d1 - '0');
}

fn parseFourDigit(s: []const u8) ?u16 {
    if (s.len < 4) return null;
    var result: u16 = 0;
    for (s[0..4]) |ch| {
        if (ch < '0' or ch > '9') return null;
        result = result * 10 + (ch - '0');
    }
    return result;
}

// --- Detection helpers ---

fn containsAscii(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn startsWithHeader(data: []const u8, prefix: []const u8) bool {
    if (data.len < prefix.len) return false;
    // Skip BOM if present
    var start: usize = 0;
    if (data.len >= 3 and data[0] == 0xEF and data[1] == 0xBB and data[2] == 0xBF) {
        start = 3;
    }
    const trimmed = trim(data[start..]);
    if (trimmed.len < prefix.len) return false;
    return std.mem.eql(u8, trimmed[0..prefix.len], prefix);
}

fn containsSemicolon(data: []const u8) bool {
    for (data) |ch| {
        if (ch == ';') return true;
    }
    return false;
}

fn containsGermanDate(data: []const u8) bool {
    // Look for dd.MM.yyyy pattern
    if (data.len < 10) return false;
    for (0..data.len - 9) |i| {
        if (data[i] >= '0' and data[i] <= '9' and
            data[i + 1] >= '0' and data[i + 1] <= '9' and
            data[i + 2] == '.' and
            data[i + 3] >= '0' and data[i + 3] <= '9' and
            data[i + 4] >= '0' and data[i + 4] <= '9' and
            data[i + 5] == '.')
        {
            return true;
        }
    }
    return false;
}
