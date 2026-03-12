// GGUF v3 file parser — reads model metadata and tensor info from GGUF files.
// Used to load embedding model weights (jina-embeddings-v5-text-nano).

const std = @import("std");

// GGUF magic number: "GGUF" in little-endian
const GGUF_MAGIC: u32 = 0x46554747; // "GGUF" as little-endian u32

// GGML tensor types we support
pub const GgmlType = enum(u32) {
    f32 = 0,
    f16 = 1,
    q4_0 = 2,
    q4_1 = 3,
    q5_0 = 6,
    q5_1 = 7,
    q8_0 = 8,
    q8_1 = 9,
    q2_k = 10,
    q3_k = 11,
    q4_k = 12,
    q5_k = 13,
    q6_k = 14,
    _,
};

// GGUF metadata value types
const GgufValueType = enum(u32) {
    uint8 = 0,
    int8 = 1,
    uint16 = 2,
    int16 = 3,
    uint32 = 4,
    int32 = 5,
    float32 = 6,
    bool_ = 7,
    string = 8,
    array = 9,
    uint64 = 10,
    int64 = 11,
    float64 = 12,
    _,
};

pub const GgufHeader = struct {
    version: u32,
    n_tensors: u64,
    n_kv: u64,
    // Offset to start of KV pairs (after the 24-byte fixed header)
    kv_offset: usize,
};

pub const TensorInfo = struct {
    name: []const u8,
    n_dims: u32,
    dims: [4]u64,
    type_: GgmlType,
    offset: u64, // relative to tensor data start
};

pub const ParseError = error{
    InvalidMagic,
    UnsupportedVersion,
    TruncatedData,
    InvalidString,
    InvalidValueType,
};

/// Read a little-endian u32 from data at offset.
pub fn readU32(data: []const u8, off: usize) ParseError!u32 {
    if (off + 4 > data.len) return ParseError.TruncatedData;
    return std.mem.readInt(u32, data[off..][0..4], .little);
}

/// Read a little-endian u64 from data at offset.
pub fn readU64(data: []const u8, off: usize) ParseError!u64 {
    if (off + 8 > data.len) return ParseError.TruncatedData;
    return std.mem.readInt(u64, data[off..][0..8], .little);
}

/// Read a GGUF string (u64 length + bytes). Returns the string slice and new offset.
pub fn readString(data: []const u8, off: usize) ParseError!struct { []const u8, usize } {
    const len = try readU64(data, off);
    const str_start = off + 8;
    const str_end = str_start + @as(usize, @intCast(len));
    if (str_end > data.len) return ParseError.TruncatedData;
    return .{ data[str_start..str_end], str_end };
}

/// Skip a GGUF metadata value, returning the new offset.
pub fn skipValue(data: []const u8, off: usize, vtype: GgufValueType) ParseError!usize {
    switch (vtype) {
        .uint8, .int8, .bool_ => return off + 1,
        .uint16, .int16 => return off + 2,
        .uint32, .int32, .float32 => return off + 4,
        .uint64, .int64, .float64 => return off + 8,
        .string => {
            const result = try readString(data, off);
            return result[1];
        },
        .array => {
            const arr_type_raw = try readU32(data, off);
            const arr_type: GgufValueType = @enumFromInt(arr_type_raw);
            const arr_len = try readU64(data, off + 4);
            var pos = off + 12;
            for (0..@intCast(arr_len)) |_| {
                pos = try skipValue(data, pos, arr_type);
            }
            return pos;
        },
        _ => return ParseError.InvalidValueType,
    }
}

/// Parse the GGUF file header.
pub fn parseHeader(data: []const u8) ParseError!GgufHeader {
    if (data.len < 24) return ParseError.TruncatedData;

    const magic = try readU32(data, 0);
    if (magic != GGUF_MAGIC) return ParseError.InvalidMagic;

    const version = try readU32(data, 4);
    if (version < 2 or version > 3) return ParseError.UnsupportedVersion;

    const n_tensors = try readU64(data, 8);
    const n_kv = try readU64(data, 16);

    return GgufHeader{
        .version = version,
        .n_tensors = n_tensors,
        .n_kv = n_kv,
        .kv_offset = 24,
    };
}

/// Find a tensor by name in the GGUF file. Returns null if not found.
/// `tensor_info_offset` should be the offset after all KV pairs.
pub fn findTensor(data: []const u8, tensor_info_offset: usize, n_tensors: u64, name: []const u8) ParseError!?struct { TensorInfo, usize } {
    var off = tensor_info_offset;

    for (0..@intCast(n_tensors)) |_| {
        const str_result = try readString(data, off);
        const tensor_name = str_result[0];
        off = str_result[1];

        const n_dims = try readU32(data, off);
        off += 4;

        var dims: [4]u64 = .{ 0, 0, 0, 0 };
        for (0..@intCast(n_dims)) |d| {
            dims[d] = try readU64(data, off);
            off += 8;
        }

        const type_raw = try readU32(data, off);
        off += 4;

        const tensor_offset = try readU64(data, off);
        off += 8;

        if (std.mem.eql(u8, tensor_name, name)) {
            return .{
                TensorInfo{
                    .name = tensor_name,
                    .n_dims = n_dims,
                    .dims = dims,
                    .type_ = @enumFromInt(type_raw),
                    .offset = tensor_offset,
                },
                off,
            };
        }
    }

    return null;
}

/// Get a string-valued metadata key. Returns null if key not found or not a string.
pub fn getStringKV(data: []const u8, header: GgufHeader, key: []const u8) ParseError!?[]const u8 {
    var off = header.kv_offset;

    for (0..@intCast(header.n_kv)) |_| {
        const str_result = try readString(data, off);
        const kv_key = str_result[0];
        off = str_result[1];

        const vtype_raw = try readU32(data, off);
        const vtype: GgufValueType = @enumFromInt(vtype_raw);
        off += 4;

        if (std.mem.eql(u8, kv_key, key)) {
            if (vtype != .string) return null;
            const val_result = try readString(data, off);
            return val_result[0];
        }

        off = try skipValue(data, off, vtype);
    }

    return null;
}

/// Get a u32-valued metadata key. Returns null if key not found.
pub fn getU32KV(data: []const u8, header: GgufHeader, key: []const u8) ParseError!?u32 {
    var off = header.kv_offset;

    for (0..@intCast(header.n_kv)) |_| {
        const str_result = try readString(data, off);
        const kv_key = str_result[0];
        off = str_result[1];

        const vtype_raw = try readU32(data, off);
        const vtype: GgufValueType = @enumFromInt(vtype_raw);
        off += 4;

        if (std.mem.eql(u8, kv_key, key)) {
            if (vtype != .uint32) return null;
            return try readU32(data, off);
        }

        off = try skipValue(data, off, vtype);
    }

    return null;
}

/// Get a string array metadata value (e.g., tokenizer.ggml.tokens).
/// Returns a slice of string slices pointing into the original data.
pub fn getStringArrayKV(data: []const u8, header: GgufHeader, key: []const u8, out: [][]const u8) ParseError!?u64 {
    var off = header.kv_offset;

    for (0..@intCast(header.n_kv)) |_| {
        const str_result = try readString(data, off);
        const kv_key = str_result[0];
        off = str_result[1];

        const vtype_raw = try readU32(data, off);
        const vtype: GgufValueType = @enumFromInt(vtype_raw);
        off += 4;

        if (std.mem.eql(u8, kv_key, key)) {
            if (vtype != .array) return null;

            const arr_type_raw = try readU32(data, off);
            const arr_type: GgufValueType = @enumFromInt(arr_type_raw);
            if (arr_type != .string) return null;

            const arr_len = try readU64(data, off + 4);
            off += 12;

            const count = @min(@as(usize, @intCast(arr_len)), out.len);
            for (0..count) |i| {
                const val_result = try readString(data, off);
                out[i] = val_result[0];
                off = val_result[1];
            }

            return arr_len;
        }

        off = try skipValue(data, off, vtype);
    }

    return null;
}

/// Get a float32 array metadata value (e.g., tokenizer.ggml.scores).
/// Writes values into the output slice. Returns the array length, or null if key not found.
pub fn getF32ArrayKV(data: []const u8, header: GgufHeader, key: []const u8, out: []f32) ParseError!?u64 {
    var off = header.kv_offset;

    for (0..@intCast(header.n_kv)) |_| {
        const str_result = try readString(data, off);
        const kv_key = str_result[0];
        off = str_result[1];

        const vtype_raw = try readU32(data, off);
        const vtype: GgufValueType = @enumFromInt(vtype_raw);
        off += 4;

        if (std.mem.eql(u8, kv_key, key)) {
            if (vtype != .array) return null;

            const arr_type_raw = try readU32(data, off);
            const arr_type: GgufValueType = @enumFromInt(arr_type_raw);
            if (arr_type != .float32) return null;

            const arr_len = try readU64(data, off + 4);
            off += 12;

            const count = @min(@as(usize, @intCast(arr_len)), out.len);
            for (0..count) |i| {
                if (off + 4 > data.len) return ParseError.TruncatedData;
                out[i] = @bitCast(std.mem.readInt(u32, data[off..][0..4], .little));
                off += 4;
            }

            return arr_len;
        }

        off = try skipValue(data, off, vtype);
    }

    return null;
}

/// Skip all KV pairs and return the offset to tensor info section.
pub fn skipAllKV(data: []const u8, header: GgufHeader) ParseError!usize {
    var off = header.kv_offset;

    for (0..@intCast(header.n_kv)) |_| {
        // Skip key string
        const str_result = try readString(data, off);
        off = str_result[1];

        // Read value type
        const vtype_raw = try readU32(data, off);
        const vtype: GgufValueType = @enumFromInt(vtype_raw);
        off += 4;

        // Skip value
        off = try skipValue(data, off, vtype);
    }

    return off;
}

/// Calculate the tensor data start offset (after header + KV + tensor infos).
/// Tensor data is aligned to the GGUF alignment (default 32 bytes).
pub fn tensorDataStart(data: []const u8, header: GgufHeader) ParseError!usize {
    // Skip past all KV pairs
    var off = try skipAllKV(data, header);

    // Skip past all tensor info entries
    for (0..@intCast(header.n_tensors)) |_| {
        const str_result = try readString(data, off);
        off = str_result[1];

        const n_dims = try readU32(data, off);
        off += 4;

        off += @as(usize, @intCast(n_dims)) * 8; // dims
        off += 4; // type
        off += 8; // offset
    }

    // Align to 32 bytes (GGUF default alignment)
    const alignment: usize = 32;
    off = (off + alignment - 1) & ~(alignment - 1);

    return off;
}

// --- Tests ---

test "gguf magic validation" {
    const bad_data = [_]u8{ 0, 0, 0, 0 } ++ [_]u8{0} ** 20;
    const result = parseHeader(&bad_data);
    try std.testing.expectError(ParseError.InvalidMagic, result);
}

test "gguf truncated data" {
    const result = parseHeader(&[_]u8{ 0, 1, 2 });
    try std.testing.expectError(ParseError.TruncatedData, result);
}

test "gguf valid header" {
    // GGUF magic + version 3 + 0 tensors + 0 KV pairs
    var data: [24]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], GGUF_MAGIC, .little);
    std.mem.writeInt(u32, data[4..8], 3, .little);
    std.mem.writeInt(u64, data[8..16], 0, .little);
    std.mem.writeInt(u64, data[16..24], 0, .little);

    const header = try parseHeader(&data);
    try std.testing.expectEqual(@as(u32, 3), header.version);
    try std.testing.expectEqual(@as(u64, 0), header.n_tensors);
    try std.testing.expectEqual(@as(u64, 0), header.n_kv);
}
