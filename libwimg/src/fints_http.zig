const std = @import("std");
const fints = @import("fints.zig");

pub const HttpError = error{
    ConnectionFailed,
    RequestFailed,
    ResponseTooLarge,
    Base64Error,
    OutOfMemory,
};

/// Send a FinTS message to the bank server.
/// The raw FinTS message is Base64-encoded before sending.
/// The Base64-encoded response is decoded before returning.
///
/// `url` — bank FinTS endpoint (e.g. "https://fints.comdirect.de/fints")
/// `message` — raw FinTS message bytes
/// `out_buf` — buffer for decoded response
///
/// Returns the number of bytes written to out_buf.
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

    // Create HTTP client
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    // Use the Allocating writer to capture response body
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    // Perform the request using fetch
    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = enc_buf,
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

    // Base64-decode the response
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

    // Build a simple anonymous init message
    var session = fints.FintsSession.init(
        "12345678",
        "https://banking.subsembly.com/fints",
        "testuser",
        "123456",
    );
    session.product_id_len = 25;
    @memcpy(session.product_id[0..25], "0123456789ABCDEF012345678");

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
