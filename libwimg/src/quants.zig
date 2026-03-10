// Dequantization routines for GGML quantized tensors + vector math.
// Supports Q4_K, Q8_0, Q6_K, F16 dequantization used by jina-embeddings-v5-text-nano.

const std = @import("std");

// --- Q4_K dequantization ---
// Block size: 32 elements = 144 bytes per block
// Layout: 2xf16 (d, dmin) + 12 bytes scales/mins + 16 bytes quants
const Q4_K_BLOCK_SIZE = 256;
const Q4_K_BYTES = 144;

/// Dequantize a Q4_K block (256 elements) into f32 output.
pub fn dequantQ4K(block: []const u8, output: []f32) void {
    if (block.len < Q4_K_BYTES or output.len < Q4_K_BLOCK_SIZE) return;

    const d = f16ToF32(block[0..2]);
    const dmin = f16ToF32(block[2..4]);
    const scales_bytes = block[4..16]; // 12 bytes of packed scales/mins

    // Decode 8 scale/min pairs from 12 bytes (6-bit packing)
    var scales: [8]f32 = undefined;
    var mins: [8]f32 = undefined;

    for (0..8) |j| {
        if (j < 4) {
            scales[j] = @floatFromInt(scales_bytes[j] & 0x3F);
            mins[j] = @floatFromInt(scales_bytes[j + 4] & 0x3F);
        } else {
            scales[j] = @floatFromInt((scales_bytes[j + 4] & 0x0F) | ((scales_bytes[j - 4] >> 6) << 4));
            mins[j] = @floatFromInt((scales_bytes[j + 4] >> 4) | ((scales_bytes[j] >> 6) << 4));
        }
    }

    const quants = block[16..Q4_K_BYTES];

    // 8 sub-blocks of 32 elements each
    for (0..8) |j| {
        const sc = d * scales[j];
        const mn = dmin * mins[j];
        const qoff = j * 16;

        for (0..16) |l| {
            if (qoff + l >= quants.len) break;
            const q = quants[qoff + l];
            const lo: f32 = @floatFromInt(q & 0x0F);
            const hi: f32 = @floatFromInt(q >> 4);
            const out_idx = j * 32 + l;
            const out_idx2 = j * 32 + l + 16;
            if (out_idx < output.len) output[out_idx] = sc * lo - mn;
            if (out_idx2 < output.len) output[out_idx2] = sc * hi - mn;
        }
    }
}

// --- Q8_0 dequantization ---
// Block size: 32 elements = 34 bytes per block (2 bytes f16 scale + 32 int8 quants)
const Q8_0_BLOCK_SIZE = 32;
const Q8_0_BYTES = 34;

/// Dequantize a Q8_0 block (32 elements) into f32 output.
pub fn dequantQ8_0(block: []const u8, output: []f32) void {
    if (block.len < Q8_0_BYTES or output.len < Q8_0_BLOCK_SIZE) return;

    const d = f16ToF32(block[0..2]);

    for (0..Q8_0_BLOCK_SIZE) |i| {
        const q: i8 = @bitCast(block[2 + i]);
        output[i] = d * @as(f32, @floatFromInt(q));
    }
}

// --- Q6_K dequantization ---
// Block size: 256 elements = 210 bytes per block
const Q6_K_BLOCK_SIZE = 256;
const Q6_K_BYTES = 210;

/// Dequantize a Q6_K block (256 elements) into f32 output.
pub fn dequantQ6K(block: []const u8, output: []f32) void {
    if (block.len < Q6_K_BYTES or output.len < Q6_K_BLOCK_SIZE) return;

    const ql = block[0..128]; // low 4 bits
    const qh = block[128..192]; // high 2 bits
    const sc = block[192..208]; // scales (int8)
    const d = f16ToF32(block[208..210]);

    for (0..256) |n| {
        const il = n / 128; // 0 or 1
        const ib = (n % 128) / 32; // sub-block
        const is_ = n / 16; // scale index
        const ir = n % 32; // within sub-block

        const ql_idx = 64 * il + 32 * (ib / 2) + ir % 32;
        const qh_idx = 32 * il + ir % 32;

        var q_lo: u8 = 0;
        if (ql_idx < ql.len) {
            q_lo = if (ib % 2 == 0) ql[ql_idx] & 0x0F else ql[ql_idx] >> 4;
        }

        var q_hi: u8 = 0;
        if (qh_idx < qh.len) {
            q_hi = (qh[qh_idx] >> @intCast((ib % 4) * 2)) & 0x03;
        }

        const q6: i8 = @intCast(@as(i32, q_lo | (q_hi << 4)) - 32);
        const scale: i8 = if (is_ < sc.len) @bitCast(sc[is_]) else 0;
        output[n] = d * @as(f32, @floatFromInt(scale)) * @as(f32, @floatFromInt(q6));
    }
}

// --- F16 conversion ---

/// Convert 2 bytes (little-endian f16) to f32.
pub fn f16ToF32(bytes: *const [2]u8) f32 {
    const bits = std.mem.readInt(u16, bytes, .little);
    const f16_val: f16 = @bitCast(bits);
    return @floatCast(f16_val);
}

/// Convert f32 to f16 then return as 2 bytes.
pub fn f32ToF16Bytes(val: f32) [2]u8 {
    const f16_val: f16 = @floatCast(val);
    const bits: u16 = @bitCast(f16_val);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, bits, .little);
    return bytes;
}

// --- Vector math ---

/// Dot product of two f32 vectors. For L2-normalized vectors, this equals cosine similarity.
pub fn dotProduct(a: []const f32, b: []const f32) f32 {
    const len = @min(a.len, b.len);
    var acc: @Vector(4, f32) = @splat(0);
    var i: usize = 0;
    while (i + 4 <= len) : (i += 4) {
        const va: @Vector(4, f32) = a[i..][0..4].*;
        const vb: @Vector(4, f32) = b[i..][0..4].*;
        acc += va * vb;
    }
    var sum = @reduce(.Add, acc);
    while (i < len) : (i += 1) {
        sum += a[i] * b[i];
    }
    return sum;
}

/// Cosine similarity between two vectors.
/// For already-normalized vectors, use dotProduct directly.
pub fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    const len = @min(a.len, b.len);
    var dot_acc: @Vector(4, f32) = @splat(0);
    var na_acc: @Vector(4, f32) = @splat(0);
    var nb_acc: @Vector(4, f32) = @splat(0);
    var i: usize = 0;
    while (i + 4 <= len) : (i += 4) {
        const va: @Vector(4, f32) = a[i..][0..4].*;
        const vb: @Vector(4, f32) = b[i..][0..4].*;
        dot_acc += va * vb;
        na_acc += va * va;
        nb_acc += vb * vb;
    }
    var dot = @reduce(.Add, dot_acc);
    var norm_a = @reduce(.Add, na_acc);
    var norm_b = @reduce(.Add, nb_acc);
    while (i < len) : (i += 1) {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }
    const denom = @sqrt(norm_a) * @sqrt(norm_b);
    if (denom < 1e-12) return 0;
    return dot / denom;
}

/// L2-normalize a vector in-place. After this, ||vec|| = 1.0.
pub fn l2Normalize(vec: []f32) void {
    var acc: @Vector(4, f32) = @splat(0);
    var i: usize = 0;
    while (i + 4 <= vec.len) : (i += 4) {
        const v: @Vector(4, f32) = vec[i..][0..4].*;
        acc += v * v;
    }
    var sum_sq = @reduce(.Add, acc);
    while (i < vec.len) : (i += 1) {
        sum_sq += vec[i] * vec[i];
    }
    const norm = @sqrt(sum_sq);
    if (norm < 1e-12) return;
    const inv_v: @Vector(4, f32) = @splat(1.0 / norm);
    i = 0;
    while (i + 4 <= vec.len) : (i += 4) {
        const v: @Vector(4, f32) = vec[i..][0..4].*;
        vec[i..][0..4].* = v * inv_v;
    }
    const inv_norm = 1.0 / norm;
    while (i < vec.len) : (i += 1) {
        vec[i] *= inv_norm;
    }
}

/// Matrix-vector multiply: out = mat * vec. mat is row-major [rows][cols].
pub fn matVecMul(mat: []const f32, vec: []const f32, out: []f32, rows: usize, cols: usize) void {
    for (0..rows) |r| {
        var sum: f32 = 0;
        const row_start = r * cols;
        for (0..cols) |c| {
            sum += mat[row_start + c] * vec[c];
        }
        out[r] = sum;
    }
}

/// Element-wise add: out[i] += b[i]
pub fn vecAdd(out: []f32, b: []const f32) void {
    const len = @min(out.len, b.len);
    var i: usize = 0;
    while (i + 4 <= len) : (i += 4) {
        const va: @Vector(4, f32) = out[i..][0..4].*;
        const vb: @Vector(4, f32) = b[i..][0..4].*;
        out[i..][0..4].* = va + vb;
    }
    while (i < len) : (i += 1) {
        out[i] += b[i];
    }
}

/// Element-wise multiply: out[i] *= b[i]
pub fn vecMul(out: []f32, b: []const f32) void {
    const len = @min(out.len, b.len);
    var i: usize = 0;
    while (i + 4 <= len) : (i += 4) {
        const va: @Vector(4, f32) = out[i..][0..4].*;
        const vb: @Vector(4, f32) = b[i..][0..4].*;
        out[i..][0..4].* = va * vb;
    }
    while (i < len) : (i += 1) {
        out[i] *= b[i];
    }
}

/// SiLU activation: x * sigmoid(x) = x / (1 + exp(-x))
pub fn silu(vec: []f32) void {
    for (vec) |*v| {
        v.* = v.* / (1.0 + @exp(-v.*));
    }
}

/// GELU activation (tanh approximation): 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
pub fn gelu(vec: []f32) void {
    const sqrt_2_over_pi: f32 = 0.7978845608;
    const coeff: f32 = 0.044715;
    for (vec) |*v| {
        const x = v.*;
        const t = sqrt_2_over_pi * (x + coeff * x * x * x);
        v.* = 0.5 * x * (1.0 + std.math.tanh(t));
    }
}

/// RMS normalization: x_i = x_i / sqrt(mean(x^2) + eps) * weight_i
pub fn rmsNorm(out: []f32, weight: []const f32, eps: f32) void {
    const len = out.len;
    var sum_sq: f32 = 0;
    for (out) |v| {
        sum_sq += v * v;
    }
    const rms = @sqrt(sum_sq / @as(f32, @floatFromInt(len)) + eps);
    const inv_rms = 1.0 / rms;
    const wlen = @min(len, weight.len);
    for (0..wlen) |i| {
        out[i] = out[i] * inv_rms * weight[i];
    }
}

/// Softmax over a slice of f32 values (in-place).
pub fn softmax(vec: []f32) void {
    // Find max for numerical stability
    var max_val: f32 = -std.math.inf(f32);
    for (vec) |v| {
        if (v > max_val) max_val = v;
    }
    var sum: f32 = 0;
    for (vec) |*v| {
        v.* = @exp(v.* - max_val);
        sum += v.*;
    }
    if (sum > 0) {
        const inv_sum = 1.0 / sum;
        for (vec) |*v| {
            v.* *= inv_sum;
        }
    }
}

// --- Block size helpers ---

/// Number of bytes per block for a given GGML type.
pub fn blockBytes(t: @import("gguf.zig").GgmlType) usize {
    return switch (t) {
        .f32 => 4,
        .f16 => 2,
        .q4_k => Q4_K_BYTES,
        .q8_0 => Q8_0_BYTES,
        .q6_k => Q6_K_BYTES,
        else => 0,
    };
}

/// Number of elements per block for a given GGML type.
pub fn blockSize(t: @import("gguf.zig").GgmlType) usize {
    return switch (t) {
        .f32 => 1,
        .f16 => 1,
        .q4_k => Q4_K_BLOCK_SIZE,
        .q8_0 => Q8_0_BLOCK_SIZE,
        .q6_k => Q6_K_BLOCK_SIZE,
        else => 0,
    };
}

/// Dequantize `count` elements from quantized data into output f32 buffer.
pub fn dequantize(data: []const u8, output: []f32, t: @import("gguf.zig").GgmlType, count: usize) void {
    const bs = blockSize(t);
    const bb = blockBytes(t);
    if (bs == 0 or bb == 0) return;

    const n_blocks = count / bs;
    var out_off: usize = 0;
    var data_off: usize = 0;

    for (0..n_blocks) |_| {
        if (data_off + bb > data.len or out_off + bs > output.len) break;

        switch (t) {
            .f32 => {
                output[out_off] = @bitCast(std.mem.readInt(u32, data[data_off..][0..4], .little));
            },
            .f16 => {
                output[out_off] = f16ToF32(data[data_off..][0..2]);
            },
            .q4_k => {
                dequantQ4K(data[data_off .. data_off + bb], output[out_off .. out_off + bs]);
            },
            .q8_0 => {
                dequantQ8_0(data[data_off .. data_off + bb], output[out_off .. out_off + bs]);
            },
            .q6_k => {
                dequantQ6K(data[data_off .. data_off + bb], output[out_off .. out_off + bs]);
            },
            else => {},
        }

        data_off += bb;
        out_off += bs;
    }
}

// --- Fused dequant + dot product ---
// Computes dot(dequant(quantized_row), input) without intermediate f32 buffer.
// Eliminates double memory traffic: dequant writes + dot reads.

/// Fused dequant + dot product dispatcher.
pub fn fusedDot(data: []const u8, input: []const f32, t: @import("gguf.zig").GgmlType, count: usize) f32 {
    return switch (t) {
        .q4_k => fusedDotQ4K(data, input, count),
        .q6_k => fusedDotQ6K(data, input, count),
        .q8_0 => fusedDotQ8_0(data, input, count),
        .f16 => fusedDotF16(data, input, count),
        .f32 => fusedDotF32(data, input, count),
        else => 0,
    };
}

fn fusedDotQ4K(data: []const u8, input: []const f32, count: usize) f32 {
    const n_blocks = count / Q4_K_BLOCK_SIZE;
    var acc: @Vector(4, f32) = @splat(0);
    var data_off: usize = 0;
    var inp_off: usize = 0;

    const lo_mask: @Vector(4, u8) = @splat(0x0F);
    const hi_shift: @Vector(4, u8) = @splat(4);

    for (0..n_blocks) |_| {
        if (data_off + Q4_K_BYTES > data.len) break;
        const block = data[data_off..];

        const d_val = f16ToF32(block[0..2]);
        const dmin = f16ToF32(block[2..4]);
        const scales_bytes = block[4..16];

        var scales: [8]f32 = undefined;
        var mins: [8]f32 = undefined;
        for (0..8) |j| {
            if (j < 4) {
                scales[j] = @floatFromInt(scales_bytes[j] & 0x3F);
                mins[j] = @floatFromInt(scales_bytes[j + 4] & 0x3F);
            } else {
                scales[j] = @floatFromInt((scales_bytes[j + 4] & 0x0F) | ((scales_bytes[j - 4] >> 6) << 4));
                mins[j] = @floatFromInt((scales_bytes[j + 4] >> 4) | ((scales_bytes[j] >> 6) << 4));
            }
        }

        const q = block[16..Q4_K_BYTES];

        for (0..8) |j| {
            const sc_v: @Vector(4, f32) = @splat(d_val * scales[j]);
            const mn_v: @Vector(4, f32) = @splat(dmin * mins[j]);
            const qoff = j * 16;
            const base_lo = inp_off + j * 32;
            const base_hi = base_lo + 16;

            // Process 16 lo + 16 hi nibble pairs, 4 at a time via SIMD
            var ci: usize = 0;
            while (ci < 16) : (ci += 4) {
                const raw: @Vector(4, u8) = q[qoff + ci ..][0..4].*;
                const lo_v: @Vector(4, f32) = @floatFromInt(raw & lo_mask);
                const hi_v: @Vector(4, f32) = @floatFromInt(raw >> hi_shift);

                const inp_lo: @Vector(4, f32) = input[base_lo + ci ..][0..4].*;
                acc += (sc_v * lo_v - mn_v) * inp_lo;

                const inp_hi: @Vector(4, f32) = input[base_hi + ci ..][0..4].*;
                acc += (sc_v * hi_v - mn_v) * inp_hi;
            }
        }

        data_off += Q4_K_BYTES;
        inp_off += Q4_K_BLOCK_SIZE;
    }
    return @reduce(.Add, acc);
}

fn fusedDotQ6K(data: []const u8, input: []const f32, count: usize) f32 {
    const n_blocks = count / Q6_K_BLOCK_SIZE;
    var sum: f32 = 0;
    var data_off: usize = 0;
    var inp_off: usize = 0;

    for (0..n_blocks) |_| {
        if (data_off + Q6_K_BYTES > data.len) break;
        const block = data[data_off..];

        const ql = block[0..128];
        const qh = block[128..192];
        const sc = block[192..208];
        const d_val = f16ToF32(block[208..210]);

        for (0..256) |n| {
            const il = n / 128;
            const ib = (n % 128) / 32;
            const is_ = n / 16;
            const ir = n % 32;

            const ql_idx = 64 * il + 32 * (ib / 2) + ir % 32;
            const qh_idx = 32 * il + ir % 32;

            var q_lo: u8 = 0;
            if (ql_idx < ql.len) {
                q_lo = if (ib % 2 == 0) ql[ql_idx] & 0x0F else ql[ql_idx] >> 4;
            }

            var q_hi: u8 = 0;
            if (qh_idx < qh.len) {
                q_hi = (qh[qh_idx] >> @intCast((ib % 4) * 2)) & 0x03;
            }

            const q6: i8 = @intCast(@as(i32, q_lo | (q_hi << 4)) - 32);
            const scale: i8 = if (is_ < sc.len) @bitCast(sc[is_]) else 0;
            const val = d_val * @as(f32, @floatFromInt(scale)) * @as(f32, @floatFromInt(q6));

            const idx = inp_off + n;
            if (idx < input.len) sum += val * input[idx];
        }

        data_off += Q6_K_BYTES;
        inp_off += Q6_K_BLOCK_SIZE;
    }
    return sum;
}

fn fusedDotQ8_0(data: []const u8, input: []const f32, count: usize) f32 {
    const n_blocks = count / Q8_0_BLOCK_SIZE;
    var acc: @Vector(4, f32) = @splat(0);
    var data_off: usize = 0;
    var inp_off: usize = 0;

    for (0..n_blocks) |_| {
        if (data_off + Q8_0_BYTES > data.len) break;
        const block = data[data_off..];
        const d_v: @Vector(4, f32) = @splat(f16ToF32(block[0..2]));

        // Process 32 int8 quants, 4 at a time (8 SIMD iterations)
        var i: usize = 0;
        while (i < Q8_0_BLOCK_SIZE) : (i += 4) {
            const q_bytes: [4]u8 = block[2 + i ..][0..4].*;
            const q_i8: @Vector(4, i8) = @bitCast(q_bytes);
            const q_f32: @Vector(4, f32) = @floatFromInt(q_i8);
            const inp: @Vector(4, f32) = input[inp_off + i ..][0..4].*;
            acc += d_v * q_f32 * inp;
        }

        data_off += Q8_0_BYTES;
        inp_off += Q8_0_BLOCK_SIZE;
    }
    return @reduce(.Add, acc);
}

fn fusedDotF16(data: []const u8, input: []const f32, count: usize) f32 {
    var acc: @Vector(4, f32) = @splat(0);
    var i: usize = 0;
    while (i + 4 <= count) : (i += 4) {
        const off = i * 2;
        if (off + 8 > data.len) break;
        const v = @Vector(4, f32){
            f16ToF32(data[off..][0..2]),
            f16ToF32(data[off + 2 ..][0..2]),
            f16ToF32(data[off + 4 ..][0..2]),
            f16ToF32(data[off + 6 ..][0..2]),
        };
        const inp: @Vector(4, f32) = input[i..][0..4].*;
        acc += v * inp;
    }
    var sum = @reduce(.Add, acc);
    while (i < count) : (i += 1) {
        const off = i * 2;
        if (off + 2 > data.len or i >= input.len) break;
        sum += f16ToF32(data[off..][0..2]) * input[i];
    }
    return sum;
}

fn fusedDotF32(data: []const u8, input: []const f32, count: usize) f32 {
    var acc: @Vector(4, f32) = @splat(0);
    var i: usize = 0;
    while (i + 4 <= count) : (i += 4) {
        const off = i * 4;
        if (off + 16 > data.len) break;
        const v = @Vector(4, f32){
            @bitCast(std.mem.readInt(u32, data[off..][0..4], .little)),
            @bitCast(std.mem.readInt(u32, data[off + 4 ..][0..4], .little)),
            @bitCast(std.mem.readInt(u32, data[off + 8 ..][0..4], .little)),
            @bitCast(std.mem.readInt(u32, data[off + 12 ..][0..4], .little)),
        };
        const inp: @Vector(4, f32) = input[i..][0..4].*;
        acc += v * inp;
    }
    var sum = @reduce(.Add, acc);
    while (i < count) : (i += 1) {
        const off = i * 4;
        if (off + 4 > data.len or i >= input.len) break;
        const val: f32 = @bitCast(std.mem.readInt(u32, data[off..][0..4], .little));
        sum += val * input[i];
    }
    return sum;
}

// --- Tests ---

test "f16 roundtrip" {
    const val: f32 = 3.14;
    const bytes = f32ToF16Bytes(val);
    const back = f16ToF32(&bytes);
    try std.testing.expectApproxEqAbs(val, back, 0.01);
}

test "l2 normalize" {
    var vec = [_]f32{ 3.0, 4.0 };
    l2Normalize(&vec);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), vec[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), vec[1], 0.001);

    // Check norm is 1.0
    const norm = @sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), norm, 0.001);
}

test "dot product" {
    const a = [_]f32{ 1.0, 2.0, 3.0 };
    const b = [_]f32{ 4.0, 5.0, 6.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), dotProduct(&a, &b), 0.001);
}

test "cosine similarity identical" {
    const a = [_]f32{ 1.0, 2.0, 3.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cosineSimilarity(&a, &a), 0.001);
}

test "rms norm" {
    var vec = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const weight = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    rmsNorm(&vec, &weight, 1e-5);

    // RMS of [1,2,3,4] = sqrt((1+4+9+16)/4) = sqrt(7.5) ≈ 2.7386
    // Each element divided by RMS
    const expected_rms = @sqrt(@as(f32, 7.5) + 1e-5);
    try std.testing.expectApproxEqAbs(1.0 / expected_rms, vec[0], 0.001);
}

test "softmax" {
    var vec = [_]f32{ 1.0, 2.0, 3.0 };
    softmax(&vec);

    // Sum should be 1.0
    const sum = vec[0] + vec[1] + vec[2];
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sum, 0.001);

    // Values should be monotonically increasing
    try std.testing.expect(vec[0] < vec[1]);
    try std.testing.expect(vec[1] < vec[2]);
}

test "silu" {
    var vec = [_]f32{ 0.0, 1.0, -1.0 };
    silu(&vec);

    // silu(0) = 0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vec[0], 0.001);
    // silu(1) = 1 * sigmoid(1) ≈ 0.7311
    try std.testing.expectApproxEqAbs(@as(f32, 0.7311), vec[1], 0.001);
    // silu(-1) = -1 * sigmoid(-1) ≈ -0.2689
    try std.testing.expectApproxEqAbs(@as(f32, -0.2689), vec[2], 0.001);
}

test "gelu" {
    var vec = [_]f32{ 0.0, 1.0, -1.0 };
    gelu(&vec);

    // gelu(0) = 0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vec[0], 0.001);
    // gelu(1) ≈ 0.8412
    try std.testing.expectApproxEqAbs(@as(f32, 0.8412), vec[1], 0.001);
    // gelu(-1) ≈ -0.1588
    try std.testing.expectApproxEqAbs(@as(f32, -0.1588), vec[2], 0.001);
}

test "q8_0 dequantize" {
    // Create a simple Q8_0 block: scale=1.0, quants=0,1,2,...,31
    var block: [Q8_0_BYTES]u8 = undefined;
    const scale_bytes = f32ToF16Bytes(1.0);
    block[0] = scale_bytes[0];
    block[1] = scale_bytes[1];
    for (0..32) |i| {
        block[2 + i] = @intCast(i);
    }

    var output: [32]f32 = undefined;
    dequantQ8_0(&block, &output);

    for (0..32) |i| {
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(i)), output[i], 0.01);
    }
}
