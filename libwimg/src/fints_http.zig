const std = @import("std");
const builtin = @import("builtin");
const fints = @import("fints.zig");

pub const HttpError = error{
    ConnectionFailed,
    RequestFailed,
    ResponseTooLarge,
    Base64Error,
    OutOfMemory,
    NoCallback,
};

/// Callback type for platform-native HTTP POST.
/// Parameters: url, url_len, body, body_len, out_buf, out_buf_len
/// Returns: bytes written to out_buf, or -1 on error.
pub const HttpCallback = *const fn (
    [*]const u8, // url
    u32, // url_len
    [*]const u8, // body (Base64-encoded)
    u32, // body_len
    [*]u8, // out_buf (for Base64-encoded response)
    u32, // out_buf_len
) callconv(.c) i32;

/// Stored callback — set by platform (Swift on iOS, or Zig stdlib fallback on native tests).
var http_callback: ?HttpCallback = null;

/// Set the HTTP callback. Called once from Swift at app init.
pub fn setCallback(cb: HttpCallback) void {
    http_callback = cb;
}

/// Send a FinTS message to the bank server.
/// The raw FinTS message is Base64-encoded before sending.
/// The Base64-encoded response is decoded before returning.
pub fn sendFintsMessage(
    allocator: std.mem.Allocator,
    url: []const u8,
    message: []const u8,
    out_buf: []u8,
) HttpError!usize {
    // Base64-encode the outgoing message
    const encoder = std.base64.standard.Encoder;
    const enc_size = encoder.calcSize(message.len);
    const enc_buf = allocator.alloc(u8, enc_size) catch return HttpError.OutOfMemory;
    defer allocator.free(enc_buf);
    _ = encoder.encode(enc_buf, message);

    if (http_callback) |cb| {
        // Use platform callback (Swift URLSession on iOS)
        var resp_b64_buf: [131072]u8 = undefined; // 128KB for Base64 response
        const resp_b64_len = cb(
            url.ptr,
            @intCast(url.len),
            enc_buf.ptr,
            @intCast(enc_buf.len),
            &resp_b64_buf,
            @intCast(resp_b64_buf.len),
        );

        if (resp_b64_len <= 0) return HttpError.RequestFailed;
        const resp_data = resp_b64_buf[0..@intCast(resp_b64_len)];

        // Strip whitespace/newlines from Base64 response (some banks add line breaks)
        var clean_buf: [131072]u8 = undefined;
        var clean_len: usize = 0;
        for (resp_data) |c| {
            if (c != '\n' and c != '\r' and c != ' ' and c != '\t') {
                clean_buf[clean_len] = c;
                clean_len += 1;
            }
        }

        // Base64-decode the cleaned response
        const decoded_len = fints.base64Decode(out_buf, clean_buf[0..clean_len]) orelse return HttpError.Base64Error;
        return decoded_len;
    }

    // Fallback: Zig stdlib on native, error on iOS (callback must be set)
    return sendViaStdlib(allocator, url, enc_buf, out_buf);
}

/// Zig stdlib HTTP — only available on platforms with filesystem CA certs.
/// Excluded from iOS builds entirely (URLSession callback used instead).
const sendViaStdlib = if (builtin.target.os.tag == .ios)
    struct {
        fn f(_: std.mem.Allocator, _: []const u8, _: []const u8, _: []u8) HttpError!usize {
            return HttpError.NoCallback;
        }
    }.f
else
    sendViaStdlibImpl;

fn sendViaStdlibImpl(
    allocator: std.mem.Allocator,
    url: []const u8,
    body: []const u8,
    out_buf: []u8,
) HttpError!usize {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .headers = .{
            .content_type = .{ .override = "text/plain" },
        },
        .response_writer = &response_body.writer,
    }) catch return HttpError.RequestFailed;

    if (result.status != .ok) {
        return HttpError.RequestFailed;
    }

    const resp_data = response_body.written();
    if (resp_data.len == 0) return HttpError.RequestFailed;

    const decoded_len = fints.base64Decode(out_buf, resp_data) orelse return HttpError.Base64Error;
    return decoded_len;
}

// ============================================================
// Tests (integration only — gated by env var)
// ============================================================

test "sendFintsMessage integration with Subsembly" {
    // Only run when WIMG_FINTS_INTEGRATION is set
    const env = std.process.getEnvVarOwned(std.testing.allocator, "WIMG_FINTS_INTEGRATION") catch return;
    defer std.testing.allocator.free(env);

    // Build a simple anonymous init message against Subsembly FinTS Dummy
    var session = fints.FintsSession.init(
        "99000354",
        "https://fints.subsembly.net/fints",
        "testuser",
        "123456",
    );
    session.product_id_len = 25;
    @memcpy(session.product_id[0..25], "F7C4049477F6136957A46EC28");

    var msg_buf: [4096]u8 = undefined;
    const msg_len = fints.buildAnonInit(&session, &msg_buf) orelse {
        return error.TestUnexpectedResult;
    };

    var out_buf: [65536]u8 = undefined;
    const resp_len = sendFintsMessage(
        std.testing.allocator,
        session.urlSlice(),
        msg_buf[0..msg_len],
        &out_buf,
    ) catch |err| {
        std.debug.print("Integration test failed (expected if no network): {}\n", .{err});
        return;
    };

    // Should get some response
    try std.testing.expect(resp_len > 0);
    // Response should start with HNHBK
    try std.testing.expect(std.mem.startsWith(u8, out_buf[0..resp_len], "HNHBK"));
}
