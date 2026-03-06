const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");

const Transaction = types.Transaction;
const Date = types.Date;

pub const Mt940Result = struct {
    count: u32,
    currency: [3]u8,
    opening_balance: i64, // cents
    closing_balance: i64, // cents
    errors: u32,
};

/// Parse MT940 bank statement data into Transaction structs.
/// `account` is the account name to assign to each transaction (e.g. "Comdirect").
/// Returns the result summary.
pub fn parseMt940(data: []const u8, account: []const u8, out: []Transaction) Mt940Result {
    var result = Mt940Result{
        .count = 0,
        .currency = "EUR".*,
        .opening_balance = 0,
        .closing_balance = 0,
        .errors = 0,
    };

    if (data.len == 0 or out.len == 0) return result;

    // State for collecting multi-line :86: fields
    var pending_txn: ?*Transaction = null;
    var desc_buf: [512]u8 = undefined;
    var desc_len: usize = 0;
    var in_field_86 = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        // Check for field tags (start with :XX:)
        if (line.len >= 4 and line[0] == ':') {
            // If we were collecting :86: data, finalize the previous transaction
            if (in_field_86) {
                finalizeTxnDescription(pending_txn, desc_buf[0..desc_len], account);
                pending_txn = null;
                in_field_86 = false;
                desc_len = 0;
            }

            if (startsWith(line, ":60F:") or startsWith(line, ":60M:")) {
                // Opening balance: :60F:D260301EUR1234,56
                parseBalance(line[5..], &result.opening_balance, &result.currency);
            } else if (startsWith(line, ":62F:") or startsWith(line, ":62M:")) {
                // Closing balance
                parseBalance(line[5..], &result.closing_balance, &result.currency);
            } else if (startsWith(line, ":61:")) {
                // Transaction line
                if (result.count < out.len) {
                    const txn = &out[result.count];
                    if (parseTxnLine(line[4..], txn)) {
                        txn.currency = result.currency;
                        pending_txn = txn;
                        result.count += 1;
                    } else {
                        result.errors += 1;
                    }
                }
            } else if (startsWith(line, ":86:")) {
                // Structured description — may span multiple lines
                in_field_86 = true;
                desc_len = 0;
                const content = line[4..];
                const copy_len = @min(content.len, desc_buf.len);
                @memcpy(desc_buf[0..copy_len], content[0..copy_len]);
                desc_len = copy_len;
            }
        } else if (in_field_86) {
            // Continuation of :86: field (lines not starting with :XX:)
            if (desc_len < desc_buf.len) {
                const remaining = desc_buf.len - desc_len;
                const copy_len = @min(line.len, remaining);
                @memcpy(desc_buf[desc_len .. desc_len + copy_len], line[0..copy_len]);
                desc_len += copy_len;
            }
        }
    }

    // Finalize last transaction if :86: was the last field
    if (in_field_86) {
        finalizeTxnDescription(pending_txn, desc_buf[0..desc_len], account);
    }

    return result;
}

/// Parse :61: transaction line.
/// Format: YYMMDD[MMDD]{D|C|RD|RC}amount{N}type[//ref]
/// Example: 2603010301D12,50NMSC
fn parseTxnLine(data: []const u8, txn: *Transaction) bool {
    if (data.len < 16) return false; // minimum: YYMMDD + D/C + amount + type

    // Date: YYMMDD (positions 0-5)
    const year = parseDigits2(data[0..2]) orelse return false;
    const month = parseDigits2(data[2..4]) orelse return false;
    const day = parseDigits2(data[4..6]) orelse return false;

    txn.date = .{
        .year = if (year < 80) 2000 + @as(u16, year) else 1900 + @as(u16, year),
        .month = month,
        .day = day,
    };

    // Skip optional second date (MMDD — 4 digits)
    var pos: usize = 6;
    if (pos + 4 <= data.len and isDigit(data[pos]) and isDigit(data[pos + 1]) and
        isDigit(data[pos + 2]) and isDigit(data[pos + 3]))
    {
        pos += 4;
    }

    // Credit/Debit indicator: D, C, RD, RC
    var is_debit = false;
    var is_reversal = false;
    if (pos < data.len and data[pos] == 'R') {
        is_reversal = true;
        pos += 1;
    }
    if (pos >= data.len) return false;
    if (data[pos] == 'D') {
        is_debit = true;
        pos += 1;
    } else if (data[pos] == 'C') {
        is_debit = false;
        pos += 1;
    } else {
        return false;
    }

    // Reversal flips the direction
    if (is_reversal) is_debit = !is_debit;

    // Amount: digits with comma as decimal separator, terminated by N or letter
    const amount_start = pos;
    while (pos < data.len and (isDigit(data[pos]) or data[pos] == ',')) : (pos += 1) {}
    if (pos == amount_start) return false;

    const amount = parseGermanAmount(data[amount_start..pos]) orelse return false;
    txn.amount_cents = if (is_debit) -amount else amount;

    // Skip N + booking type code (3 chars) + optional rest
    // We don't need the type for our purposes

    // Initialize remaining fields
    txn.description = undefined;
    txn.description_len = 0;
    txn.category = .uncategorized;
    txn.account = undefined;
    txn.account_len = 0;
    txn.id = undefined;

    return true;
}

/// Parse a German amount string like "12,50" or "1234,56" into cents.
fn parseGermanAmount(s: []const u8) ?i64 {
    if (s.len == 0) return null;

    var whole: i64 = 0;
    var frac: i64 = 0;
    var frac_digits: u8 = 0;
    var past_comma = false;

    for (s) |c| {
        if (c == ',') {
            past_comma = true;
            continue;
        }
        if (c < '0' or c > '9') return null;
        if (past_comma) {
            if (frac_digits >= 2) continue; // ignore extra decimal places
            frac = frac * 10 + (c - '0');
            frac_digits += 1;
        } else {
            whole = whole * 10 + (c - '0');
        }
    }

    if (frac_digits == 1) frac *= 10;
    return whole * 100 + frac;
}

/// Parse balance field: D/C + YYMMDD + currency + amount
/// Example: D260301EUR1234,56
fn parseBalance(data: []const u8, balance: *i64, currency: *[3]u8) void {
    if (data.len < 14) return; // D + YYMMDD + EUR + at least 1 digit

    var is_debit = false;
    var pos: usize = 0;

    if (data[pos] == 'D') {
        is_debit = true;
        pos += 1;
    } else if (data[pos] == 'C') {
        pos += 1;
    } else return;

    // Skip date (YYMMDD)
    if (pos + 6 > data.len) return;
    pos += 6;

    // Currency (3 chars)
    if (pos + 3 > data.len) return;
    currency[0] = data[pos];
    currency[1] = data[pos + 1];
    currency[2] = data[pos + 2];
    pos += 3;

    // Amount
    const amount = parseGermanAmount(data[pos..]) orelse return;
    balance.* = if (is_debit) -amount else amount;
}

/// Extract description from :86: structured field.
/// German banks use ?XX subfield codes. Priority:
/// 1. SVWZ+ content (from ?20-?29)
/// 2. Concatenated ?20-?29
/// 3. ?00 (booking text)
fn finalizeTxnDescription(maybe_txn: ?*Transaction, field86: []const u8, account: []const u8) void {
    const txn = maybe_txn orelse return;

    var desc: []const u8 = "";

    // Try structured format (?XX subfields)
    if (std.mem.indexOf(u8, field86, "?20") != null) {
        // Extract SVWZ+ (Verwendungszweck) from ?20-?29
        desc = extractSvwz(field86);

        // Fallback: concatenate ?20-?29
        if (desc.len == 0) {
            desc = extractSubfieldRange(field86, 20, 29);
        }

        // Fallback: ?00 (booking text)
        if (desc.len == 0) {
            desc = extractSubfield(field86, 0);
        }

        // Try counterparty from ?32/?33
        if (desc.len == 0) {
            desc = extractSubfield(field86, 32);
        }
    }

    // Unstructured: use the whole field
    if (desc.len == 0) {
        desc = field86;
    }

    // Write description to transaction
    const copy_len = @min(desc.len, 256);
    @memcpy(txn.description[0..copy_len], desc[0..copy_len]);
    txn.description_len = @intCast(copy_len);

    // Set account
    parser.setAccount(txn, account);

    // Compute hash
    txn.id = parser.computeHash(txn.date, txn.descriptionSlice(), txn.amount_cents, account);
}

/// Extract SVWZ+ content from structured :86: field.
/// SVWZ+ appears after ?20 (or any ?2X) and extends until next ?XX tag.
fn extractSvwz(field: []const u8) []const u8 {
    // Look for "SVWZ+" marker
    const marker = "SVWZ+";
    const svwz_pos = std.mem.indexOf(u8, field, marker) orelse return "";
    const start = svwz_pos + marker.len;
    if (start >= field.len) return "";

    // Find end: next ?XX tag
    var end = start;
    while (end < field.len) : (end += 1) {
        if (end + 2 < field.len and field[end] == '?' and isDigit(field[end + 1]) and isDigit(field[end + 2])) {
            break;
        }
    }

    return std.mem.trim(u8, field[start..end], " ");
}

/// Extract a specific ?XX subfield from structured :86: data.
fn extractSubfield(field: []const u8, num: u8) []const u8 {
    var tag_buf: [3]u8 = undefined;
    tag_buf[0] = '?';
    tag_buf[1] = '0' + (num / 10);
    tag_buf[2] = '0' + (num % 10);

    const pos = std.mem.indexOf(u8, field, &tag_buf) orelse return "";
    const start = pos + 3;
    if (start >= field.len) return "";

    // Find end: next ?XX tag
    var end = start;
    while (end < field.len) : (end += 1) {
        if (end + 2 < field.len and field[end] == '?' and isDigit(field[end + 1]) and isDigit(field[end + 2])) {
            break;
        }
    }

    return std.mem.trim(u8, field[start..end], " ");
}

/// Concatenate content from ?XX subfields in the given range.
/// Uses a static buffer — returns a slice into it.
var range_buf: [512]u8 = undefined;

fn extractSubfieldRange(field: []const u8, from: u8, to: u8) []const u8 {
    var pos: usize = 0;

    var num = from;
    while (num <= to) : (num += 1) {
        const content = extractSubfield(field, num);
        if (content.len > 0) {
            if (pos > 0 and pos < range_buf.len) {
                range_buf[pos] = ' ';
                pos += 1;
            }
            const copy_len = @min(content.len, range_buf.len - pos);
            @memcpy(range_buf[pos .. pos + copy_len], content[0..copy_len]);
            pos += copy_len;
        }
    }

    return range_buf[0..pos];
}

// ============================================================
// Helpers
// ============================================================

fn parseDigits2(s: []const u8) ?u8 {
    if (s.len < 2) return null;
    if (!isDigit(s[0]) or !isDigit(s[1])) return null;
    return (s[0] - '0') * 10 + (s[1] - '0');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, haystack, prefix);
}

// ============================================================
// Tests
// ============================================================

const test_mt940 =
    \\:20:STARTUMS
    \\:25:20041133/1234567890
    \\:28C:0/1
    \\:60F:C260301EUR5000,00
    \\:61:2603010301D12,50NMSC
    \\:86:?00KARTENZAHLUNG?20SVWZ+REWE SAGT DANKE 12345?30COBADEFF?31DE89370400440532013000?32REWE Markt GmbH
    \\:61:2603050305C3500,00NMSC
    \\:86:?00GEHALT/LOHN?20SVWZ+GEHALT MAERZ 2026?32ARBEITGEBER GMBH?33LOHNBUERO
    \\:62F:C260305EUR8487,50
    \\-
;

test "parseMt940 full document" {
    var txns: [100]Transaction = undefined;
    const result = parseMt940(test_mt940, "Comdirect", &txns);

    try std.testing.expectEqual(@as(u32, 2), result.count);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqualStrings("EUR", &result.currency);
    try std.testing.expectEqual(@as(i64, 500000), result.opening_balance);
    try std.testing.expectEqual(@as(i64, 848750), result.closing_balance);
}

test "parseMt940 first transaction is debit" {
    var txns: [100]Transaction = undefined;
    const result = parseMt940(test_mt940, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 2), result.count);

    const txn = &txns[0];
    try std.testing.expectEqual(@as(i64, -1250), txn.amount_cents);
    try std.testing.expectEqual(@as(u16, 2026), txn.date.year);
    try std.testing.expectEqual(@as(u8, 3), txn.date.month);
    try std.testing.expectEqual(@as(u8, 1), txn.date.day);
}

test "parseMt940 second transaction is credit" {
    var txns: [100]Transaction = undefined;
    const result = parseMt940(test_mt940, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 2), result.count);

    const txn = &txns[1];
    try std.testing.expectEqual(@as(i64, 350000), txn.amount_cents);
    try std.testing.expectEqual(@as(u16, 2026), txn.date.year);
    try std.testing.expectEqual(@as(u8, 3), txn.date.month);
    try std.testing.expectEqual(@as(u8, 5), txn.date.day);
}

test "parseMt940 SVWZ extraction" {
    var txns: [100]Transaction = undefined;
    _ = parseMt940(test_mt940, "Comdirect", &txns);

    // First tx should have SVWZ+ content
    const desc = txns[0].descriptionSlice();
    try std.testing.expect(std.mem.indexOf(u8, desc, "REWE SAGT DANKE") != null);
}

test "parseMt940 salary description" {
    var txns: [100]Transaction = undefined;
    _ = parseMt940(test_mt940, "Comdirect", &txns);

    const desc = txns[1].descriptionSlice();
    try std.testing.expect(std.mem.indexOf(u8, desc, "GEHALT MAERZ 2026") != null);
}

test "parseMt940 account assignment" {
    var txns: [100]Transaction = undefined;
    _ = parseMt940(test_mt940, "Comdirect", &txns);

    try std.testing.expectEqualStrings("Comdirect", txns[0].accountSlice());
    try std.testing.expectEqualStrings("Comdirect", txns[1].accountSlice());
}

test "parseMt940 IDs are unique" {
    var txns: [100]Transaction = undefined;
    _ = parseMt940(test_mt940, "Comdirect", &txns);

    try std.testing.expect(!std.mem.eql(u8, &txns[0].id, &txns[1].id));
}

test "parseMt940 empty input" {
    var txns: [10]Transaction = undefined;
    const result = parseMt940("", "test", &txns);
    try std.testing.expectEqual(@as(u32, 0), result.count);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
}

test "parseMt940 reversal debit (RD)" {
    const mt940_rd =
        \\:60F:C1000,00
        \\:61:260310RD50,00NMSC
        \\:86:Storno Lastschrift
        \\:62F:C1050,00
        \\-
    ;
    var txns: [10]Transaction = undefined;
    const result = parseMt940(mt940_rd, "Test", &txns);
    try std.testing.expectEqual(@as(u32, 1), result.count);
    // RD = reversal debit = credit (positive)
    try std.testing.expectEqual(@as(i64, 5000), txns[0].amount_cents);
}

test "parseMt940 reversal credit (RC)" {
    const mt940_rc =
        \\:60F:C1000,00
        \\:61:260310RC50,00NMSC
        \\:86:Storno Gutschrift
        \\:62F:C950,00
        \\-
    ;
    var txns: [10]Transaction = undefined;
    const result = parseMt940(mt940_rc, "Test", &txns);
    try std.testing.expectEqual(@as(u32, 1), result.count);
    // RC = reversal credit = debit (negative)
    try std.testing.expectEqual(@as(i64, -5000), txns[0].amount_cents);
}

test "parseMt940 multi-line :86:" {
    const mt940_multiline =
        \\:60F:C1000,00
        \\:61:260310D25,00NMSC
        \\:86:?00ONLINE-UEBERWEISUNG?20SVWZ+Miete Maerz
        \\ 2026 Wohnung 3OG?30COBADEFF?31DE123456789
        \\:62F:C975,00
        \\-
    ;
    var txns: [10]Transaction = undefined;
    const result = parseMt940(mt940_multiline, "Test", &txns);
    try std.testing.expectEqual(@as(u32, 1), result.count);
    const desc = txns[0].descriptionSlice();
    try std.testing.expect(std.mem.indexOf(u8, desc, "Miete Maerz") != null);
}

test "parseMt940 unstructured :86:" {
    const mt940_unstruct =
        \\:60F:C1000,00
        \\:61:260310D10,00NMSC
        \\:86:KARTENZAHLUNG EDEKA 12345
        \\:62F:C990,00
        \\-
    ;
    var txns: [10]Transaction = undefined;
    const result = parseMt940(mt940_unstruct, "Test", &txns);
    try std.testing.expectEqual(@as(u32, 1), result.count);
    try std.testing.expectEqualStrings("KARTENZAHLUNG EDEKA 12345", txns[0].descriptionSlice());
}

test "parseGermanAmount basic" {
    try std.testing.expectEqual(@as(i64, 1250), parseGermanAmount("12,50").?);
    try std.testing.expectEqual(@as(i64, 100), parseGermanAmount("1,00").?);
    try std.testing.expectEqual(@as(i64, 123456), parseGermanAmount("1234,56").?);
    try std.testing.expectEqual(@as(i64, 500), parseGermanAmount("5,00").?);
}

test "parseGermanAmount single digit fractional" {
    try std.testing.expectEqual(@as(i64, 50), parseGermanAmount("0,5").?);
}

test "parseGermanAmount no fractional" {
    try std.testing.expectEqual(@as(i64, 1200), parseGermanAmount("12,00").?);
}

test "parseMt940 debit balance" {
    const mt940_debit =
        \\:60F:D260301EUR500,00
        \\:62F:D260305EUR600,00
        \\-
    ;
    var txns: [10]Transaction = undefined;
    const result = parseMt940(mt940_debit, "Test", &txns);
    try std.testing.expectEqual(@as(i64, -50000), result.opening_balance);
    try std.testing.expectEqual(@as(i64, -60000), result.closing_balance);
}
