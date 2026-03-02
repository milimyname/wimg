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

/// Parse a Comdirect CSV export.
/// Format: semicolon-delimited, ISO-8859-1 encoded, dd.MM.yyyy dates,
/// German number format (1.234,56).
///
/// Comdirect CSV columns (typical):
///   Buchungstag;Wertstellung (Valuta);Vorgang;Buchungstext;Umsatz in EUR
///
/// The first line(s) may be metadata headers. We skip lines that don't
/// look like transaction rows (i.e., first column isn't a valid date).
pub fn parseComdirectCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0, // caller determines duplicates at DB level
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

        if (parseLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseLine(line: []const u8) ?Transaction {
    // Split by semicolons
    var cols: [10][]const u8 = undefined;
    var col_count: usize = 0;

    var col_iter = std.mem.splitScalar(u8, line, ';');
    while (col_iter.next()) |col| {
        if (col_count >= 10) break;
        cols[col_count] = col;
        col_count += 1;
    }

    // Need at least 5 columns: Buchungstag, Wertstellung, Vorgang, Buchungstext, Umsatz
    if (col_count < 5) return null;

    const date = parseDate(trim(cols[0])) orelse return null;
    const description_raw = trim(cols[3]);
    const amount_str = trim(cols[4]);

    // Clean amount: strip quotes, handle German format
    const amount = parseGermanAmount(amount_str) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;

    // Copy description (truncate if needed)
    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    // Generate hash ID from date + description + amount
    txn.id = computeHash(date, description_raw, amount);

    return txn;
}

/// Parse "dd.MM.yyyy" into a Date struct.
fn parseDate(s: []const u8) ?Date {
    // Handle quoted dates
    const clean = stripQuotes(s);
    if (clean.len < 10) return null;

    const day = parseTwoDigit(clean[0..2]) orelse return null;
    if (clean[2] != '.') return null;
    const month = parseTwoDigit(clean[3..5]) orelse return null;
    if (clean[5] != '.') return null;

    // Year: 4 digits
    const year = parseFourDigit(clean[6..10]) orelse return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;

    return Date{ .year = year, .month = month, .day = day };
}

/// Parse German-format amount: "1.234,56" or "-1.234,56" or "1234,56"
/// Also handles quoted values like "\"1.234,56\""
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
            // Thousands separator — skip
            continue;
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
            continue; // skip whitespace/quotes
        } else {
            return null; // unexpected character
        }
    }

    // If only 1 frac digit, multiply by 10 (e.g., "1,5" -> 150 cents)
    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;

    return cents;
}

fn computeHash(date: Date, description: []const u8, amount: i64) [32]u8 {
    var hasher = std.hash.Fnv1a_128.init();

    // Hash date
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

    // Hash description
    hasher.update(description);

    // Hash amount
    const amt_bytes: [8]u8 = @bitCast(amount);
    hasher.update(&amt_bytes);

    const hash_val = hasher.final();
    const hash_bytes: [16]u8 = @bitCast(hash_val);

    // Hex encode to 32 chars
    const hex = "0123456789abcdef";
    var result: [32]u8 = undefined;
    for (hash_bytes, 0..) |byte, i| {
        result[i * 2] = hex[byte >> 4];
        result[i * 2 + 1] = hex[byte & 0x0f];
    }
    return result;
}

// --- Helpers ---

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
    // Check for dd.MM pattern — starts with two digits and a dot
    const c0 = s[0];
    const c1 = s[1];
    // Handle optional quote
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
