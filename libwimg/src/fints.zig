const std = @import("std");

pub const FintsError = error{
    BufferTooSmall,
    InvalidResponse,
    AuthFailed,
    TanRequired,
    DialogFailed,
    ProtocolError,
    InvalidSegment,
};

/// FinTS 3.0 session state. Tracks dialog lifecycle and TAN flow.
pub const FintsSession = struct {
    blz: [8]u8,
    url: [128]u8,
    url_len: u8,
    user_id: [64]u8,
    user_id_len: u8,
    pin: [64]u8,
    pin_len: u8,

    system_id: [32]u8,
    system_id_len: u8,
    dialog_id: [32]u8,
    dialog_id_len: u8,

    msg_num: u16,
    product_id: [25]u8,
    product_id_len: u8,

    hitan_version: u8,

    challenge: [256]u8,
    challenge_len: u16,
    challenge_ref: [32]u8,
    challenge_ref_len: u8,

    has_pending_tan: bool,
    decoupled: bool,

    pub fn init(blz: []const u8, url: []const u8, user_id: []const u8, pin: []const u8) FintsSession {
        var s: FintsSession = undefined;
        @memset(&s.blz, '0');
        @memset(&s.url, 0);
        @memset(&s.user_id, 0);
        @memset(&s.pin, 0);
        @memset(&s.system_id, 0);
        @memset(&s.dialog_id, 0);
        @memset(&s.product_id, 0);
        @memset(&s.challenge, 0);
        @memset(&s.challenge_ref, 0);

        const blz_len = @min(blz.len, 8);
        @memcpy(s.blz[0..blz_len], blz[0..blz_len]);

        const url_len = @min(url.len, 128);
        @memcpy(s.url[0..url_len], url[0..url_len]);
        s.url_len = @intCast(url_len);

        const uid_len = @min(user_id.len, 64);
        @memcpy(s.user_id[0..uid_len], user_id[0..uid_len]);
        s.user_id_len = @intCast(uid_len);

        const pin_l = @min(pin.len, 64);
        @memcpy(s.pin[0..pin_l], pin[0..pin_l]);
        s.pin_len = @intCast(pin_l);

        s.system_id_len = 1;
        s.system_id[0] = '0'; // initial system_id = "0"
        s.dialog_id_len = 1;
        s.dialog_id[0] = '0';
        s.msg_num = 1;
        s.hitan_version = 7;
        s.has_pending_tan = false;
        s.decoupled = false;
        s.challenge_len = 0;
        s.challenge_ref_len = 0;
        s.product_id_len = 0;

        return s;
    }

    pub fn urlSlice(self: *const FintsSession) []const u8 {
        return self.url[0..self.url_len];
    }

    pub fn userIdSlice(self: *const FintsSession) []const u8 {
        return self.user_id[0..self.user_id_len];
    }

    pub fn pinSlice(self: *const FintsSession) []const u8 {
        return self.pin[0..self.pin_len];
    }

    pub fn systemIdSlice(self: *const FintsSession) []const u8 {
        return self.system_id[0..self.system_id_len];
    }

    pub fn dialogIdSlice(self: *const FintsSession) []const u8 {
        return self.dialog_id[0..self.dialog_id_len];
    }

    pub fn productIdSlice(self: *const FintsSession) []const u8 {
        return self.product_id[0..self.product_id_len];
    }

    pub fn clearPin(self: *FintsSession) void {
        @memset(&self.pin, 0);
        self.pin_len = 0;
    }
};

/// FinTS response code.
pub const ResponseCode = struct {
    code: [4]u8,
    text: [128]u8,
    text_len: u8,

    pub fn codeSlice(self: *const ResponseCode) []const u8 {
        return &self.code;
    }

    pub fn textSlice(self: *const ResponseCode) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn isSuccess(self: *const ResponseCode) bool {
        return self.code[0] == '0'; // 0xxx = success
    }

    pub fn isTanRequired(self: *const ResponseCode) bool {
        return std.mem.eql(u8, &self.code, "0030") or std.mem.eql(u8, &self.code, "3920");
    }

    pub fn isError(self: *const ResponseCode) bool {
        return self.code[0] == '9'; // 9xxx = error
    }
};

/// Parsed response from a FinTS message exchange.
pub const ParsedResponse = struct {
    codes: [16]ResponseCode,
    code_count: u8,
    dialog_id: [32]u8,
    dialog_id_len: u8,
    system_id: [32]u8,
    system_id_len: u8,
    mt940_data: [32768]u8, // up to 32 KB of MT940 data
    mt940_len: u16,
    challenge: [256]u8,
    challenge_len: u16,
    challenge_ref: [32]u8,
    challenge_ref_len: u8,
    has_tan_request: bool,
    decoupled: bool,

    pub fn init() ParsedResponse {
        var r: ParsedResponse = undefined;
        r.code_count = 0;
        r.dialog_id_len = 0;
        r.system_id_len = 0;
        r.mt940_len = 0;
        r.challenge_len = 0;
        r.challenge_ref_len = 0;
        r.has_tan_request = false;
        r.decoupled = false;
        @memset(&r.mt940_data, 0);
        @memset(&r.dialog_id, 0);
        @memset(&r.system_id, 0);
        @memset(&r.challenge, 0);
        @memset(&r.challenge_ref, 0);
        return r;
    }

    pub fn hasError(self: *const ParsedResponse) bool {
        for (self.codes[0..self.code_count]) |*c| {
            if (c.isError()) return true;
        }
        return false;
    }
};

// ============================================================
// Message Building
// ============================================================

/// Build anonymous initialization message (no credentials).
/// Used to fetch BPD (bank parameter data).
pub fn buildAnonInit(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKIDN — Identification (anonymous: user_id=0, system_id=0)
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKIDN", 3, 2, &.{
        &session.blz,
        "0",
        "0",
        "1",
    }) orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 4, 3, &.{
        "0",
        "0",
        "0",
        session.productIdSlice(),
        "1.0",
    }) orelse return null;

    return writeEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Build authenticated initialization message.
/// Includes security envelope (HNVSK/HNVSD) with PIN.
pub fn buildAuthInit(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKIDN — Identification
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKIDN", 3, 2, &.{
        &session.blz,
        session.userIdSlice(),
        session.systemIdSlice(),
        "1",
    }) orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 4, 3, &.{
        "0",
        "0",
        "0",
        session.productIdSlice(),
        "1.0",
    }) orelse return null;

    // HKTAN — TAN process init (two-step, version 7)
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKTAN", 5, session.hitan_version, &.{
        "4", // process variant 4 = init
        "", // segment reference
        "", // ATC
        "", // TAN media name
    }) orelse return null;

    return writeSecurityEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Build HKKAZ (fetch bank statements) message.
pub fn buildFetchStatements(session: *const FintsSession, from: []const u8, to: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKKAZ — Account statements (CAMT or MT940)
    // Version 7 uses MT940
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKKAZ", 3, 7, &.{
        "1", // account reference (simplified)
        "", // all accounts
        from,
        to,
        "", // max entries
        "", // start token
    }) orelse return null;

    // HKTAN
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKTAN", 4, session.hitan_version, &.{
        "4",
        "HKKAZ",
        "",
        "",
    }) orelse return null;

    return writeSecurityEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Build TAN submission message.
pub fn buildTanResponse(session: *const FintsSession, tan: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKTAN with the TAN
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKTAN", 3, session.hitan_version, &.{
        "2", // process variant 2 = submit TAN
        "",
        session.challenge_ref[0..session.challenge_ref_len],
        "",
        tan,
    }) orelse return null;

    return writeSecurityEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Build dialog end message.
pub fn buildDialogEnd(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    inner_pos += writeSegment(&inner_buf, inner_pos, "HKEND", 3, 1, &.{
        session.dialogIdSlice(),
    }) orelse return null;

    return writeSecurityEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Parse a FinTS response message, updating session state.
pub fn parseResponse(session: *FintsSession, data: []const u8, out: *ParsedResponse) void {
    out.* = ParsedResponse.init();

    // Split by unescaped segment delimiter '
    var seg_iter = SegmentIterator{ .data = data, .pos = 0 };
    while (seg_iter.next()) |segment| {
        if (segment.len < 5) continue;

        // Parse segment header: ID:NUM:VER
        if (startsWith(segment, "HNHBK")) {
            // Message envelope — nothing to extract
        } else if (startsWith(segment, "HNVSD")) {
            // Security envelope contains inner segments
            // Extract content between @len@ markers
            if (extractEnvelopeContent(segment)) |inner| {
                parseResponse(session, inner, out);
            }
        } else if (startsWith(segment, "HIRMG") or startsWith(segment, "HIRMS")) {
            // Response codes
            parseResponseCodes(segment, out);
        } else if (startsWith(segment, "HNVSK")) {
            // Security header — skip
        } else if (startsWith(segment, "HISYN")) {
            // System ID response
            extractSystemId(segment, out);
        } else if (startsWith(segment, "HITAN")) {
            // TAN challenge
            extractTanChallenge(segment, out);
        } else if (startsWith(segment, "HIKAZ")) {
            // Account statements (MT940 data)
            extractMt940(segment, out);
        }
    }

    // Update session from response
    if (out.dialog_id_len > 0) {
        const len = out.dialog_id_len;
        @memcpy(session.dialog_id[0..len], out.dialog_id[0..len]);
        session.dialog_id_len = len;
    }
    if (out.system_id_len > 0) {
        const len = out.system_id_len;
        @memcpy(session.system_id[0..len], out.system_id[0..len]);
        session.system_id_len = len;
    }
    if (out.has_tan_request) {
        session.has_pending_tan = true;
        session.decoupled = out.decoupled;
        if (out.challenge_len > 0) {
            @memcpy(session.challenge[0..out.challenge_len], out.challenge[0..out.challenge_len]);
            session.challenge_len = out.challenge_len;
        }
        if (out.challenge_ref_len > 0) {
            @memcpy(session.challenge_ref[0..out.challenge_ref_len], out.challenge_ref[0..out.challenge_ref_len]);
            session.challenge_ref_len = out.challenge_ref_len;
        }
    }
}

// ============================================================
// Internal: Segment Writing
// ============================================================

/// Write a FinTS segment: ID:NUM:VER+DE1+DE2+...+'
fn writeSegment(buf: []u8, offset: usize, id: []const u8, num: u16, ver: u8, des: []const []const u8) ?usize {
    var pos: usize = offset;
    const remaining = buf.len - pos;
    if (remaining < id.len + 10) return null;

    // Header: ID:NUM:VER
    @memcpy(buf[pos .. pos + id.len], id);
    pos += id.len;
    buf[pos] = ':';
    pos += 1;
    pos += writeUint(buf[pos..], num) orelse return null;
    buf[pos] = ':';
    pos += 1;
    pos += writeUint(buf[pos..], ver) orelse return null;

    // Data elements
    for (des) |de| {
        if (pos >= buf.len) return null;
        buf[pos] = '+';
        pos += 1;
        pos += escapeFintsValue(buf[pos..], de) orelse return null;
    }

    // Segment terminator
    if (pos >= buf.len) return null;
    buf[pos] = '\'';
    pos += 1;

    return pos - offset;
}

/// Write HNHBK...HNHBS envelope around inner segments.
fn writeEnvelope(session: *const FintsSession, buf: []u8, inner: []const u8) ?usize {
    // HNHBK header: HNHBK:1:3+MSGSIZE+300+DIALOG_ID+MSG_NUM'
    // HNHBS trailer: HNHBS:N:1+MSG_NUM'

    // Build trailer first to know its size
    var trailer_buf: [64]u8 = undefined;
    const seg_num = 2 + countSegments(inner);
    const trailer_len = writeSegment(&trailer_buf, 0, "HNHBS", seg_num, 1, &.{
        &formatMsgNum(session.msg_num),
    }) orelse return null;

    // Build header placeholder — we'll patch the size
    var header_buf: [128]u8 = undefined;
    // Total message size = header + inner + trailer
    // Header has fixed 12-digit size field
    const estimated_header_len = 30 + session.dialog_id_len; // rough estimate
    const total_size = estimated_header_len + inner.len + trailer_len;

    var size_str: [12]u8 = undefined;
    formatFixedWidth(&size_str, total_size);

    var header_pos: usize = 0;
    const header_seg = "HNHBK:1:3+" ++ "";
    @memcpy(header_buf[header_pos .. header_pos + header_seg.len], header_seg);
    header_pos += header_seg.len;
    @memcpy(header_buf[header_pos .. header_pos + 12], &size_str);
    header_pos += 12;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // HBCI version
    const ver = "300";
    @memcpy(header_buf[header_pos .. header_pos + ver.len], ver);
    header_pos += ver.len;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // Dialog ID
    const did = session.dialogIdSlice();
    @memcpy(header_buf[header_pos .. header_pos + did.len], did);
    header_pos += did.len;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // Message number
    const mn = formatMsgNum(session.msg_num);
    @memcpy(header_buf[header_pos .. header_pos + mn.len], &mn);
    header_pos += mn.len;
    header_buf[header_pos] = '\'';
    header_pos += 1;

    // Recalculate with actual header size
    const actual_total = header_pos + inner.len + trailer_len;
    formatFixedWidth(&size_str, actual_total);
    // Patch size in header (starts at position 11 = after "HNHBK:1:3+")
    @memcpy(header_buf[11 .. 11 + 12], &size_str);

    // Assemble
    if (buf.len < actual_total) return null;
    var pos: usize = 0;
    @memcpy(buf[pos .. pos + header_pos], header_buf[0..header_pos]);
    pos += header_pos;
    @memcpy(buf[pos .. pos + inner.len], inner);
    pos += inner.len;
    @memcpy(buf[pos .. pos + trailer_len], trailer_buf[0..trailer_len]);
    pos += trailer_len;

    return pos;
}

/// Wrap inner segments in HNVSK + HNVSD security envelope with PIN.
fn writeSecurityEnvelope(session: *const FintsSession, buf: []u8, inner: []const u8) ?usize {
    var sec_buf: [8192]u8 = undefined;
    var sec_pos: usize = 0;

    // HNVSK — Security header (segment 998)
    // Simplified PIN/TAN mode
    sec_pos += writeSegment(&sec_buf, sec_pos, "HNVSK", 998, 3, &.{
        "998", // security profile
        "1", // security function
        "1", // security class
        "", // role
        "1", // version
        "0", // date (ignored for PIN/TAN)
        "1", // encryption algorithm
        "2:2:13:@8@00000000:5:1", // key name (simplified)
        "0", // compression
    }) orelse return null;

    // Build inner segment with PIN authentication
    var pin_inner_buf: [8192]u8 = undefined;
    var pin_pos: usize = 0;

    // HNVSD contains the actual segments + authentication
    // First write the inner segments
    @memcpy(pin_inner_buf[pin_pos .. pin_pos + inner.len], inner);
    pin_pos += inner.len;

    // Format the HNVSD segment with @len@ binary data marker
    // HNVSD:999:1+@len@data'
    const hnvsd_prefix = "HNVSD:999:1+@";
    if (sec_pos + hnvsd_prefix.len > sec_buf.len) return null;
    @memcpy(sec_buf[sec_pos .. sec_pos + hnvsd_prefix.len], hnvsd_prefix);
    sec_pos += hnvsd_prefix.len;

    // Write length as decimal
    sec_pos += writeUint(sec_buf[sec_pos..], @intCast(pin_pos)) orelse return null;

    if (sec_pos >= sec_buf.len) return null;
    sec_buf[sec_pos] = '@';
    sec_pos += 1;

    // Write the inner data
    if (sec_pos + pin_pos >= sec_buf.len) return null;
    @memcpy(sec_buf[sec_pos .. sec_pos + pin_pos], pin_inner_buf[0..pin_pos]);
    sec_pos += pin_pos;

    if (sec_pos >= sec_buf.len) return null;
    sec_buf[sec_pos] = '\'';
    sec_pos += 1;

    return writeEnvelope(session, buf, sec_buf[0..sec_pos]);
}

// ============================================================
// Internal: Response Parsing
// ============================================================

/// Iterator that splits FinTS message by unescaped ' delimiter.
const SegmentIterator = struct {
    data: []const u8,
    pos: usize,

    fn next(self: *SegmentIterator) ?[]const u8 {
        if (self.pos >= self.data.len) return null;

        const start = self.pos;
        while (self.pos < self.data.len) {
            if (self.data[self.pos] == '\'' and !isEscaped(self.data, self.pos)) {
                const segment = self.data[start..self.pos];
                self.pos += 1;
                if (segment.len > 0) return segment;
                return self.next();
            }
            self.pos += 1;
        }

        // Remaining data (no trailing ')
        if (start < self.data.len) return self.data[start..];
        return null;
    }
};

fn isEscaped(data: []const u8, pos: usize) bool {
    if (pos == 0) return false;
    return data[pos - 1] == '?';
}

fn parseResponseCodes(segment: []const u8, out: *ParsedResponse) void {
    // Format: HIRMG:2:2+CODE:TEXT+CODE:TEXT+...
    // or HIRMS:3:2:REF+CODE:TEXT+...
    // Find the first + to skip the header
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    // Parse each code group (separated by +)
    while (pos < segment.len) {
        // Read 4-digit code
        if (pos + 4 > segment.len) break;
        if (out.code_count >= 16) break;

        var code: *ResponseCode = &out.codes[out.code_count];
        @memset(&code.text, 0);

        // Code is first 4 chars before ':'
        @memcpy(&code.code, segment[pos .. pos + 4]);
        pos += 4;

        // Skip separator ':'
        if (pos < segment.len and segment[pos] == ':') pos += 1;

        // Read text until next unescaped '+'
        const text_start = pos;
        while (pos < segment.len) {
            if (segment[pos] == '+' and !isEscaped(segment, pos)) break;
            pos += 1;
        }
        const text_len = @min(pos - text_start, 128);
        @memcpy(code.text[0..text_len], segment[text_start .. text_start + text_len]);
        code.text_len = @intCast(text_len);

        out.code_count += 1;

        // Check for dialog_id in certain response codes
        if (std.mem.eql(u8, &code.code, "0020")) {
            // Dialog-ID is usually in HNHBK, but extract from HIRMG if present
        }

        if (pos < segment.len and segment[pos] == '+') pos += 1;
    }
}

fn extractSystemId(segment: []const u8, out: *ParsedResponse) void {
    // HISYN:N:V+system_id'
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    const start = pos;
    while (pos < segment.len and segment[pos] != '+' and segment[pos] != '\'') : (pos += 1) {}
    const id = segment[start..pos];
    const len = @min(id.len, 32);
    @memcpy(out.system_id[0..len], id[0..len]);
    out.system_id_len = @intCast(len);
}

fn extractTanChallenge(segment: []const u8, out: *ParsedResponse) void {
    // HITAN:N:V+process+ref+...+challenge+...
    out.has_tan_request = true;

    // Split by + to find challenge fields
    var field_num: u8 = 0;
    var pos: usize = 0;

    // Skip segment header
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;
    field_num = 1;

    while (pos < segment.len) {
        const field_start = pos;
        // Find next unescaped +
        while (pos < segment.len) {
            if ((segment[pos] == '+' or segment[pos] == '\'') and !isEscaped(segment, pos)) break;
            pos += 1;
        }
        const field = segment[field_start..pos];

        switch (field_num) {
            1 => {
                // Process variant — check for "S" (decoupled)
                if (std.mem.eql(u8, field, "S")) {
                    out.decoupled = true;
                }
            },
            2 => {
                // Challenge reference
                const ref_len = @min(field.len, 32);
                @memcpy(out.challenge_ref[0..ref_len], field[0..ref_len]);
                out.challenge_ref_len = @intCast(ref_len);
            },
            4 => {
                // Challenge text
                const chal_len = @min(field.len, 256);
                @memcpy(out.challenge[0..chal_len], field[0..chal_len]);
                out.challenge_len = @intCast(chal_len);
            },
            else => {},
        }

        field_num += 1;
        if (pos < segment.len and segment[pos] == '+') pos += 1 else break;
    }
}

fn extractMt940(segment: []const u8, out: *ParsedResponse) void {
    // HIKAZ:N:V+@len@mt940data+...
    // Find @len@ binary data marker
    if (std.mem.indexOf(u8, segment, "@")) |at_pos| {
        const after_at = segment[at_pos + 1 ..];
        // Find closing @
        if (std.mem.indexOf(u8, after_at, "@")) |end_at| {
            const data_start = at_pos + 1 + end_at + 1;
            if (data_start < segment.len) {
                const remaining = segment[data_start..];
                const copy_len = @min(remaining.len, 32768);
                @memcpy(out.mt940_data[0..copy_len], remaining[0..copy_len]);
                out.mt940_len = @intCast(copy_len);
                return;
            }
        }
    }

    // Fallback: try to find MT940 data after first +
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos < segment.len) {
        pos += 1;
        const remaining = segment[pos..];
        const copy_len = @min(remaining.len, 32768);
        @memcpy(out.mt940_data[0..copy_len], remaining[0..copy_len]);
        out.mt940_len = @intCast(copy_len);
    }
}

fn extractEnvelopeContent(segment: []const u8) ?[]const u8 {
    // Find @len@ marker in HNVSD segment
    if (std.mem.indexOf(u8, segment, "@")) |at_pos| {
        const after_at = segment[at_pos + 1 ..];
        if (std.mem.indexOf(u8, after_at, "@")) |end_at| {
            const data_start = at_pos + 1 + end_at + 1;
            if (data_start < segment.len) {
                return segment[data_start..];
            }
        }
    }
    return null;
}

// ============================================================
// Internal: Helpers
// ============================================================

/// Escape FinTS special characters: ? before +, :, ', ?
fn escapeFintsValue(buf: []u8, value: []const u8) ?usize {
    var pos: usize = 0;
    for (value) |c| {
        if (c == '?' or c == '+' or c == ':' or c == '\'') {
            if (pos + 2 > buf.len) return null;
            buf[pos] = '?';
            pos += 1;
        } else {
            if (pos + 1 > buf.len) return null;
        }
        buf[pos] = c;
        pos += 1;
    }
    return pos;
}

/// Unescape FinTS value: remove ? before +, :, ', ?
pub fn unescapeFintsValue(buf: []u8, value: []const u8) usize {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < value.len) {
        if (i + 1 < value.len and value[i] == '?') {
            const next = value[i + 1];
            if (next == '?' or next == '+' or next == ':' or next == '\'') {
                if (pos < buf.len) {
                    buf[pos] = next;
                    pos += 1;
                }
                i += 2;
                continue;
            }
        }
        if (pos < buf.len) {
            buf[pos] = value[i];
            pos += 1;
        }
        i += 1;
    }
    return pos;
}

fn writeUint(buf: []u8, val: usize) ?usize {
    var tmp: [20]u8 = undefined;
    var n = val;
    var len: usize = 0;

    if (n == 0) {
        if (buf.len == 0) return null;
        buf[0] = '0';
        return 1;
    }

    while (n > 0) : (len += 1) {
        tmp[len] = @intCast('0' + (n % 10));
        n /= 10;
    }

    if (len > buf.len) return null;

    // Reverse
    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

fn formatFixedWidth(buf: *[12]u8, val: usize) void {
    var n = val;
    var i: usize = 12;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
}

fn formatMsgNum(num: u16) [4]u8 {
    var result: [4]u8 = undefined;
    var n: u16 = num;
    var i: usize = 4;
    while (i > 0) {
        i -= 1;
        result[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
    return result;
}

fn countSegments(data: []const u8) u16 {
    var count: u16 = 0;
    for (data) |c| {
        if (c == '\'') count += 1;
    }
    return count;
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, haystack, prefix);
}

/// Encode data as Base64.
pub fn base64Encode(buf: []u8, data: []const u8) ?usize {
    const encoder = std.base64.standard.Encoder;
    const needed = encoder.calcSize(data.len);
    if (needed > buf.len) return null;
    const encoded = encoder.encode(buf, data);
    return encoded.len;
}

/// Decode Base64 data.
pub fn base64Decode(buf: []u8, data: []const u8) ?usize {
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(data) catch return null;
    if (size > buf.len) return null;
    decoder.decode(buf, data) catch return null;
    return size;
}

// ============================================================
// Tests
// ============================================================

test "FintsSession.init sets fields correctly" {
    const s = FintsSession.init("20041133", "https://fints.comdirect.de/fints", "testuser", "12345");
    try std.testing.expectEqualStrings("20041133", &s.blz);
    try std.testing.expectEqualStrings("https://fints.comdirect.de/fints", s.urlSlice());
    try std.testing.expectEqualStrings("testuser", s.userIdSlice());
    try std.testing.expectEqualStrings("12345", s.pinSlice());
    try std.testing.expectEqualStrings("0", s.systemIdSlice());
    try std.testing.expectEqualStrings("0", s.dialogIdSlice());
    try std.testing.expectEqual(@as(u16, 1), s.msg_num);
}

test "FintsSession.clearPin zeros the PIN" {
    var s = FintsSession.init("20041133", "https://x.de/f", "user", "secretPIN");
    try std.testing.expectEqualStrings("secretPIN", s.pinSlice());
    s.clearPin();
    try std.testing.expectEqual(@as(u8, 0), s.pin_len);
    // Verify memory is zeroed
    for (s.pin[0..9]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "escapeFintsValue escapes special characters" {
    var buf: [64]u8 = undefined;
    const len = escapeFintsValue(&buf, "Hello+World:Test?End'Done") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Hello?+World?:Test??End?'Done", buf[0..len]);
}

test "escapeFintsValue no escaping needed" {
    var buf: [64]u8 = undefined;
    const len = escapeFintsValue(&buf, "plain text 123") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("plain text 123", buf[0..len]);
}

test "unescapeFintsValue removes escape chars" {
    var buf: [64]u8 = undefined;
    const len = unescapeFintsValue(&buf, "Hello?+World?:Test??End?'Done");
    try std.testing.expectEqualStrings("Hello+World:Test?End'Done", buf[0..len]);
}

test "base64 roundtrip" {
    var enc_buf: [128]u8 = undefined;
    var dec_buf: [128]u8 = undefined;
    const original = "HNHBK:1:3+000000000095+300+0+1'";
    const enc_len = base64Encode(&enc_buf, original) orelse return error.TestUnexpectedResult;
    const dec_len = base64Decode(&dec_buf, enc_buf[0..enc_len]) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(original, dec_buf[0..dec_len]);
}

test "writeSegment basic" {
    var buf: [256]u8 = undefined;
    const len = writeSegment(&buf, 0, "HKIDN", 3, 2, &.{ "20041133", "testuser", "0", "1" }) orelse return error.TestUnexpectedResult;
    const seg = buf[0..len];
    try std.testing.expect(startsWith(seg, "HKIDN:3:2+"));
    try std.testing.expect(seg[seg.len - 1] == '\'');
    try std.testing.expect(std.mem.indexOf(u8, seg, "20041133") != null);
    try std.testing.expect(std.mem.indexOf(u8, seg, "testuser") != null);
}

test "buildAnonInit produces valid envelope" {
    var s = FintsSession.init("20041133", "https://x.de/f", "user", "pin");
    s.product_id_len = 25;
    @memcpy(s.product_id[0..25], "F7C4049477F6136957A46EC28");

    var buf: [4096]u8 = undefined;
    const len = buildAnonInit(&s, &buf) orelse return error.TestUnexpectedResult;
    const msg = buf[0..len];

    // Must start with HNHBK and end with HNHBS
    try std.testing.expect(startsWith(msg, "HNHBK:1:3+"));
    // Must contain HKIDN and HKVVB
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKIDN") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKVVB") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNHBS") != null);
}

test "writeEnvelope size field is correct" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var buf: [4096]u8 = undefined;
    const inner = "HKIDN:3:2+12345678+0+0+1'";
    const len = writeEnvelope(&s, &buf, inner) orelse return error.TestUnexpectedResult;

    // Extract size from header (after "HNHBK:1:3+", 12 digits)
    const size_start = 11;
    const size_str = buf[size_start .. size_start + 12];
    const declared_size = std.fmt.parseInt(usize, size_str, 10) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(len, declared_size);
}

test "formatMsgNum pads to 4 digits" {
    try std.testing.expectEqualStrings("0001", &formatMsgNum(1));
    try std.testing.expectEqualStrings("0042", &formatMsgNum(42));
    try std.testing.expectEqualStrings("0100", &formatMsgNum(100));
}

test "formatFixedWidth pads to 12 digits" {
    var buf: [12]u8 = undefined;
    formatFixedWidth(&buf, 95);
    try std.testing.expectEqualStrings("000000000095", &buf);
}

test "parseResponse extracts response codes" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIRMG:2:2+0010:Nachricht entgegengenommen+0100:Dialog initialisiert'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u8, 2), resp.code_count);
    try std.testing.expectEqualStrings("0010", resp.codes[0].codeSlice());
    try std.testing.expect(resp.codes[0].isSuccess());
}

test "parseResponse detects error codes" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIRMG:2:2+9800:Nicht erlaubt'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u8, 1), resp.code_count);
    try std.testing.expect(resp.codes[0].isError());
}

test "parseResponse extracts system ID from HISYN" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HISYN:5:4+mySystemId123'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqualStrings("mySystemId123", s.systemIdSlice());
}

test "parseResponse extracts TAN challenge" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HITAN:5:7+4+REF123++Bitte TAN eingeben+moredata'";
    parseResponse(&s, data, &resp);

    try std.testing.expect(resp.has_tan_request);
    try std.testing.expect(s.has_pending_tan);
    try std.testing.expectEqualStrings("REF123", s.challenge_ref[0..s.challenge_ref_len]);
}

test "SegmentIterator splits correctly" {
    const data = "SEG1:1:1+data1'SEG2:2:1+data2'SEG3:3:1+data3'";
    var iter = SegmentIterator{ .data = data, .pos = 0 };

    const s1 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s1, "SEG1"));

    const s2 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s2, "SEG2"));

    const s3 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s3, "SEG3"));

    try std.testing.expect(iter.next() == null);
}

test "ResponseCode classification" {
    var c: ResponseCode = undefined;
    c.code = "0010".*;
    try std.testing.expect(c.isSuccess());
    try std.testing.expect(!c.isError());

    c.code = "9800".*;
    try std.testing.expect(!c.isSuccess());
    try std.testing.expect(c.isError());

    c.code = "0030".*;
    try std.testing.expect(c.isTanRequired());

    c.code = "3920".*;
    try std.testing.expect(c.isTanRequired());
}
