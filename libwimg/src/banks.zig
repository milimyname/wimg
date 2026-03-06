const std = @import("std");

pub const BankInfo = struct {
    blz: [8]u8,
    name: [64]u8,
    name_len: u8,
    url: [128]u8,
    url_len: u8,

    pub fn nameSlice(self: *const BankInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn urlSlice(self: *const BankInfo) []const u8 {
        return self.url[0..self.url_len];
    }

    pub fn blzSlice(self: *const BankInfo) []const u8 {
        return &self.blz;
    }
};

fn makeBank(blz: *const [8]u8, name: []const u8, url: []const u8) BankInfo {
    var b: BankInfo = .{
        .blz = blz.*,
        .name = undefined,
        .name_len = @intCast(name.len),
        .url = undefined,
        .url_len = @intCast(url.len),
    };
    @memset(&b.name, 0);
    @memset(&b.url, 0);
    @memcpy(b.name[0..name.len], name);
    @memcpy(b.url[0..url.len], url);
    return b;
}

pub const banks = [_]BankInfo{
    // Comdirect (now Commerzbank subsidiary)
    makeBank("20041133", "Comdirect", "https://fints.comdirect.de/fints"),
    // ING-DiBa
    makeBank("50010517", "ING", "https://fints.ing-diba.de/fints"),
    // DKB
    makeBank("12030000", "DKB", "https://banking-dkb.s-fints-pt-dkb.de/fints30"),
    // Commerzbank
    makeBank("50040000", "Commerzbank", "https://fints.commerzbank.de/fints"),
    // Postbank
    makeBank("37010050", "Postbank", "https://fints.postbank.de/fints"),
    // Deutsche Bank
    makeBank("50070010", "Deutsche Bank", "https://fints.deutsche-bank.de/fints"),
    // Deutsche Bank (Berliner)
    makeBank("10070000", "Deutsche Bank Berlin", "https://fints.deutsche-bank.de/fints"),
    // HypoVereinsbank (UniCredit)
    makeBank("70020270", "HypoVereinsbank", "https://fints.hypovereinsbank.de/fints"),
    // Targobank
    makeBank("30020900", "Targobank", "https://fints.targobank.de/fints"),
    // Norisbank
    makeBank("10077777", "Norisbank", "https://fints.norisbank.de/fints"),
    // Santander
    makeBank("31010833", "Santander", "https://fints.santander.de/fints"),
    // Consorsbank (BNP Paribas)
    makeBank("76030080", "Consorsbank", "https://fints.consorsbank.de/fints"),
    // Sparkasse Koeln/Bonn (Atruvia)
    makeBank("37050198", "Sparkasse KoelnBonn", "https://banking-bw1.s-fints-pt-bw.de/fints30"),
    // Sparkasse Duesseldorf
    makeBank("30050110", "Stadtsparkasse Duesseldorf", "https://banking-nrw2.s-fints-pt-nrw.de/fints30"),
    // Sparkasse Muenchen
    makeBank("70150000", "Stadtsparkasse Muenchen", "https://banking-by1.s-fints-pt-by.de/fints30"),
    // Sparkasse Berlin
    makeBank("10050000", "Berliner Sparkasse", "https://banking-be1.s-fints-pt-be.de/fints30"),
    // Sparkasse Hamburg
    makeBank("20050550", "Haspa", "https://banking-hh1.s-fints-pt-hh.de/fints30"),
    // Volksbank (various — Frankfurt as example)
    makeBank("50190000", "Frankfurter Volksbank", "https://fints.gad.de/fints"),
    // Sparda-Bank West
    makeBank("33060592", "Sparda-Bank West", "https://fints.sparda-west.de/fints"),
    // N26 (does not support FinTS — placeholder for bank list display)
    makeBank("10011001", "N26", "https://not-supported.n26.com/fints"),
    // PSD Bank Nord
    makeBank("20090900", "PSD Bank Nord", "https://banking-hh1.s-fints-pt-hh.de/fints30"),
    // 1822direkt
    makeBank("50050201", "1822direkt", "https://banking-he5.s-fints-pt-he.de/fints30"),
    // Oldenburgische Landesbank
    makeBank("28020050", "OLB", "https://fints.olb.de/fints"),
    // Subsembly FinTS Test Server (for development/testing)
    makeBank("12345678", "Subsembly Test Bank", "https://banking.subsembly.com/fints"),
};

/// Find a bank by BLZ (8-digit bank routing code).
pub fn findByBlz(blz: []const u8) ?*const BankInfo {
    if (blz.len != 8) return null;
    for (&banks) |*bank| {
        if (std.mem.eql(u8, &bank.blz, blz)) return bank;
    }
    return null;
}

/// Serialize the bank list to JSON.
/// Returns the number of bytes written, or null if buffer too small.
pub fn toJson(buf: []u8) ?usize {
    var pos: usize = 0;

    if (pos >= buf.len) return null;
    buf[pos] = '[';
    pos += 1;

    for (&banks, 0..) |*bank, i| {
        if (i > 0) {
            if (pos >= buf.len) return null;
            buf[pos] = ',';
            pos += 1;
        }

        const entry = std.fmt.bufPrint(buf[pos..], "{{\"blz\":\"{s}\",\"name\":\"{s}\",\"url\":\"{s}\"}}", .{
            bank.blzSlice(),
            bank.nameSlice(),
            bank.urlSlice(),
        }) catch return null;
        pos += entry.len;
    }

    if (pos >= buf.len) return null;
    buf[pos] = ']';
    pos += 1;

    return pos;
}

// ============================================================
// Tests
// ============================================================

test "findByBlz returns Comdirect for 20041133" {
    const bank = findByBlz("20041133") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Comdirect", bank.nameSlice());
    try std.testing.expectEqualStrings("https://fints.comdirect.de/fints", bank.urlSlice());
}

test "findByBlz returns ING for 50010517" {
    const bank = findByBlz("50010517") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ING", bank.nameSlice());
}

test "findByBlz returns null for unknown BLZ" {
    try std.testing.expect(findByBlz("99999999") == null);
}

test "findByBlz returns null for wrong length" {
    try std.testing.expect(findByBlz("123") == null);
    try std.testing.expect(findByBlz("123456789") == null);
}

test "findByBlz returns Subsembly test bank" {
    const bank = findByBlz("12345678") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Subsembly Test Bank", bank.nameSlice());
    try std.testing.expectEqualStrings("https://banking.subsembly.com/fints", bank.urlSlice());
}

test "toJson produces valid JSON array" {
    var buf: [16384]u8 = undefined;
    const len = toJson(&buf) orelse return error.TestUnexpectedResult;
    const json = buf[0..len];

    // Must start with [ and end with ]
    try std.testing.expect(json[0] == '[');
    try std.testing.expect(json[json.len - 1] == ']');

    // Must contain known entries
    try std.testing.expect(std.mem.indexOf(u8, json, "20041133") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Comdirect") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "12345678") != null);
}

test "toJson returns null for tiny buffer" {
    var buf: [2]u8 = undefined;
    try std.testing.expect(toJson(&buf) == null);
}

test "all bank URLs start with https" {
    for (&banks) |*bank| {
        const url = bank.urlSlice();
        try std.testing.expect(std.mem.startsWith(u8, url, "https://"));
    }
}

test "all bank BLZs are 8 digits" {
    for (&banks) |*bank| {
        for (&bank.blz) |c| {
            try std.testing.expect(c >= '0' and c <= '9');
        }
    }
}
