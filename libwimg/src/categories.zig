const std = @import("std");
const types = @import("types.zig");
const c = @import("sqlite_c.zig");

const Category = types.Category;

/// Match a transaction description against categorization rules in the database.
/// Returns the highest-priority matching category, or .uncategorized if no match.
pub fn matchRules(handle: *c.sqlite3, description: []const u8) Category {
    const sql = "SELECT pattern, category FROM rules ORDER BY priority DESC;";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(handle, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK or stmt == null) return .uncategorized;
    defer _ = c.sqlite3_finalize(stmt.?);

    const s = stmt.?;
    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const pat_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const pat_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const cat_val = c.sqlite3_column_int(s, 1);

        if (pat_len == 0) continue;

        if (containsIgnoreCase(description, pat_ptr[0..pat_len])) {
            return Category.fromInt(@intCast(cat_val));
        }
    }

    return .uncategorized;
}

/// Case-insensitive substring search (ASCII only).
pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        var found = true;
        for (0..needle.len) |j| {
            if (toLowerAscii(haystack[i + j]) != toLowerAscii(needle[j])) {
                found = false;
                break;
            }
        }
        if (found) return true;
    }
    return false;
}

fn toLowerAscii(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}
