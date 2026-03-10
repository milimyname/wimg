// Transformer forward pass for BERT-based embedding models (multilingual-e5-small).
// Pure Zig inference: 12-layer encoder with LayerNorm (post-norm), absolute position embeddings,
// standard FFN with GELU, and biases on all linear layers.
// Reads quantized weights from GGUF. Output: 384-dim L2-normalized embedding.

const std = @import("std");
const gguf = @import("gguf.zig");
const quants = @import("quants.zig");
const tokenizer_mod = @import("tokenizer.zig");

const EMBED_DIM = 384; // Hidden size
const OUTPUT_DIM = 384; // Full output dim (no Matryoshka truncation)
const N_HEADS = 12;
const HEAD_DIM = EMBED_DIM / N_HEADS; // 32
const N_LAYERS = 12;
const MAX_SEQ_LEN = 128; // Max tokens for a single transaction description
const FFN_DIM = 1536; // 384 * 4
const LN_EPS = 1e-12; // LayerNorm epsilon (BERT default)

pub const EmbedError = error{
    ModelNotLoaded,
    TensorNotFound,
    UnsupportedType,
    BufferTooSmall,
    TokenizationFailed,
};

/// Tensor reference — points into GGUF file data (zero-copy).
const TensorRef = struct {
    data: []const u8,
    type_: gguf.GgmlType,
    rows: usize,
    cols: usize,
};

/// Per-layer transformer weights (BERT: biases on all layers, standard FFN).
const LayerWeights = struct {
    // Attention (with biases)
    q_weight: TensorRef,
    q_bias: TensorRef,
    k_weight: TensorRef,
    k_bias: TensorRef,
    v_weight: TensorRef,
    v_bias: TensorRef,
    o_weight: TensorRef,
    o_bias: TensorRef,
    // LayerNorm after attention (weight + bias)
    attn_norm_weight: TensorRef,
    attn_norm_bias: TensorRef,
    // Standard FFN (with biases): up → GELU → down
    ffn_up_weight: TensorRef,
    ffn_up_bias: TensorRef,
    ffn_down_weight: TensorRef,
    ffn_down_bias: TensorRef,
    // LayerNorm after FFN (weight + bias)
    ffn_norm_weight: TensorRef,
    ffn_norm_bias: TensorRef,
};

// Large tokenizer buffer as file-level static (too big for WASM stack)
var g_vocab_buf: [tokenizer_mod.MAX_VOCAB_SIZE][]const u8 = undefined;

pub const EmbedModel = struct {
    // Model data (GGUF file, loaded into memory)
    data: []const u8,
    tensor_data_start: usize,

    // Tokenizer
    tokenizer: tokenizer_mod.Tokenizer,

    // Global weights
    token_embed: TensorRef, // [vocab_size, EMBED_DIM]
    position_embed: TensorRef, // [MAX_POS, EMBED_DIM]
    token_type_embed: TensorRef, // [2, EMBED_DIM]
    // Final LayerNorm (weight + bias) — optional, may not exist in all BERT variants
    final_norm_weight: ?TensorRef,
    final_norm_bias: ?TensorRef,

    // Per-layer weights
    layers: [N_LAYERS]LayerWeights,

    /// Embed a text string into a 384-dim vector.
    /// Writes the result to `out_vec` (must be >= OUTPUT_DIM).
    pub fn embed(self: *const EmbedModel, text: []const u8, out_vec: []f32, scratch: []f32) EmbedError!void {
        if (out_vec.len < OUTPUT_DIM) return EmbedError.BufferTooSmall;

        // Tokenize
        var token_ids: [MAX_SEQ_LEN]u32 = undefined;
        const n_tokens = self.tokenizer.encode(text, &token_ids) catch return EmbedError.TokenizationFailed;
        if (n_tokens == 0) {
            @memset(out_vec[0..OUTPUT_DIM], 0);
            return;
        }

        const seq_len: usize = @intCast(n_tokens);

        // Scratch layout:
        // hidden:      [MAX_SEQ_LEN * EMBED_DIM]
        // scratch1:    [EMBED_DIM]
        // ffn_up_buf:  [FFN_DIM]
        // attn_scores: [MAX_SEQ_LEN] (per head per token — reused)
        // q_buf:       [MAX_SEQ_LEN * EMBED_DIM]
        // k_buf:       [MAX_SEQ_LEN * EMBED_DIM]
        // v_buf:       [MAX_SEQ_LEN * EMBED_DIM]
        const hidden_size = MAX_SEQ_LEN * EMBED_DIM;
        const needed = hidden_size + EMBED_DIM + FFN_DIM + MAX_SEQ_LEN + 3 * hidden_size;
        if (scratch.len < needed) return EmbedError.BufferTooSmall;

        var off: usize = 0;
        const hidden = scratch[off .. off + hidden_size];
        off += hidden_size;
        const scratch1 = scratch[off .. off + EMBED_DIM];
        off += EMBED_DIM;
        const ffn_up_buf = scratch[off .. off + FFN_DIM];
        off += FFN_DIM;
        const attn_scores = scratch[off .. off + MAX_SEQ_LEN];
        off += MAX_SEQ_LEN;
        const q_buf = scratch[off .. off + hidden_size];
        off += hidden_size;
        const k_buf = scratch[off .. off + hidden_size];
        off += hidden_size;
        const v_buf = scratch[off .. off + hidden_size];

        // Step 1: Token embeddings + position embeddings + token_type embeddings
        self.lookupEmbeddings(token_ids[0..seq_len], hidden);

        // Step 2: Transformer layers (post-norm BERT style)
        for (0..N_LAYERS) |layer| {
            self.transformerLayer(layer, hidden, seq_len, scratch1, ffn_up_buf, attn_scores, q_buf, k_buf, v_buf);
        }

        // Step 3: Optional final LayerNorm
        if (self.final_norm_weight) |fnw| {
            if (self.final_norm_bias) |fnb| {
                for (0..seq_len) |t| {
                    const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
                    self.layerNorm(h, fnw, fnb, scratch1);
                    @memcpy(h, scratch1[0..EMBED_DIM]);
                }
            }
        }

        // Step 4: Mean pooling over all tokens
        @memset(scratch1[0..EMBED_DIM], 0);
        for (0..seq_len) |t| {
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
            quants.vecAdd(scratch1[0..EMBED_DIM], h);
        }
        const inv_len: f32 = 1.0 / @as(f32, @floatFromInt(seq_len));
        for (scratch1[0..EMBED_DIM]) |*v| {
            v.* *= inv_len;
        }

        // Step 5: Copy full 384-dim output and L2-normalize
        @memcpy(out_vec[0..OUTPUT_DIM], scratch1[0..OUTPUT_DIM]);
        quants.l2Normalize(out_vec[0..OUTPUT_DIM]);
    }

    // --- Internal helpers ---

    fn lookupEmbeddings(self: *const EmbedModel, token_ids: []const u32, hidden: []f32) void {
        var deq_buf: [EMBED_DIM]f32 = undefined;
        var pos_buf: [EMBED_DIM]f32 = undefined;
        var type_buf: [EMBED_DIM]f32 = undefined;

        // Dequantize token_type 0 once (all tokens are type 0 for single-sentence)
        const type_row = self.getTensorRow(self.token_type_embed, 0);
        if (type_row) |rb| {
            quants.dequantize(rb, &type_buf, self.token_type_embed.type_, EMBED_DIM);
        } else {
            @memset(&type_buf, 0);
        }

        for (token_ids, 0..) |tid, t| {
            // Token embedding
            const tok_row = self.getTensorRow(self.token_embed, tid);
            if (tok_row) |rb| {
                quants.dequantize(rb, &deq_buf, self.token_embed.type_, EMBED_DIM);
                @memcpy(hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM], &deq_buf);
            } else {
                @memset(hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM], 0);
            }

            // Add position embedding
            const pos_row = self.getTensorRow(self.position_embed, @intCast(t));
            if (pos_row) |rb| {
                quants.dequantize(rb, &pos_buf, self.position_embed.type_, EMBED_DIM);
                quants.vecAdd(hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM], &pos_buf);
            }

            // Add token type embedding
            quants.vecAdd(hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM], &type_buf);
        }
    }

    fn transformerLayer(
        self: *const EmbedModel,
        layer: usize,
        hidden: []f32,
        seq_len: usize,
        scratch1: []f32,
        ffn_up_buf: []f32,
        attn_scores: []f32,
        q_buf: []f32,
        k_buf: []f32,
        v_buf: []f32,
    ) void {
        const lw = &self.layers[layer];

        // --- Self-attention ---

        // Compute Q, K, V projections (with bias)
        for (0..seq_len) |t| {
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
            self.linearForward(lw.q_weight, lw.q_bias, h, q_buf[t * EMBED_DIM .. (t + 1) * EMBED_DIM], EMBED_DIM, EMBED_DIM);
            self.linearForward(lw.k_weight, lw.k_bias, h, k_buf[t * EMBED_DIM .. (t + 1) * EMBED_DIM], EMBED_DIM, EMBED_DIM);
            self.linearForward(lw.v_weight, lw.v_bias, h, v_buf[t * EMBED_DIM .. (t + 1) * EMBED_DIM], EMBED_DIM, EMBED_DIM);
        }

        // Multi-head attention
        const scale: f32 = 1.0 / @sqrt(@as(f32, @floatFromInt(HEAD_DIM)));

        for (0..seq_len) |t| {
            for (0..N_HEADS) |head| {
                const head_off = head * HEAD_DIM;

                // Compute attention scores for this head + query token (SIMD)
                for (0..seq_len) |ki| {
                    const q_off = t * EMBED_DIM + head_off;
                    const k_off = ki * EMBED_DIM + head_off;
                    var acc: @Vector(4, f32) = @splat(0);
                    var d: usize = 0;
                    while (d + 4 <= HEAD_DIM) : (d += 4) {
                        const qv: @Vector(4, f32) = q_buf[q_off + d ..][0..4].*;
                        const kv: @Vector(4, f32) = k_buf[k_off + d ..][0..4].*;
                        acc += qv * kv;
                    }
                    attn_scores[ki] = @reduce(.Add, acc) * scale;
                }
                // Softmax (bidirectional — no causal mask)
                quants.softmax(attn_scores[0..seq_len]);

                // Apply attention weights to values (SIMD over seq_len)
                var d: usize = 0;
                while (d + 4 <= HEAD_DIM) : (d += 4) {
                    var sum_v: @Vector(4, f32) = @splat(0);
                    for (0..seq_len) |ki| {
                        const score_v: @Vector(4, f32) = @splat(attn_scores[ki]);
                        const vv: @Vector(4, f32) = v_buf[ki * EMBED_DIM + head_off + d ..][0..4].*;
                        sum_v += score_v * vv;
                    }
                    scratch1[head_off + d ..][0..4].* = sum_v;
                }
                while (d < HEAD_DIM) : (d += 1) {
                    var sum: f32 = 0;
                    for (0..seq_len) |ki| {
                        sum += attn_scores[ki] * v_buf[ki * EMBED_DIM + head_off + d];
                    }
                    scratch1[head_off + d] = sum;
                }
            }

            // Output projection (with bias) + residual
            var out_buf: [EMBED_DIM]f32 = undefined;
            self.linearForward(lw.o_weight, lw.o_bias, scratch1[0..EMBED_DIM], &out_buf, EMBED_DIM, EMBED_DIM);
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
            quants.vecAdd(h, &out_buf);
        }

        // Post-attention LayerNorm
        for (0..seq_len) |t| {
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
            self.layerNorm(h, lw.attn_norm_weight, lw.attn_norm_bias, scratch1);
            @memcpy(h, scratch1[0..EMBED_DIM]);
        }

        // --- FFN (standard BERT: up → GELU → down) ---
        for (0..seq_len) |t| {
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];

            // Up projection: [EMBED_DIM] → [FFN_DIM]
            self.linearForward(lw.ffn_up_weight, lw.ffn_up_bias, h, ffn_up_buf[0..FFN_DIM], FFN_DIM, EMBED_DIM);

            // GELU activation
            quants.gelu(ffn_up_buf[0..FFN_DIM]);

            // Down projection: [FFN_DIM] → [EMBED_DIM]
            self.linearForward(lw.ffn_down_weight, lw.ffn_down_bias, ffn_up_buf[0..FFN_DIM], scratch1[0..EMBED_DIM], EMBED_DIM, FFN_DIM);

            // Residual
            quants.vecAdd(h, scratch1[0..EMBED_DIM]);
        }

        // Post-FFN LayerNorm
        for (0..seq_len) |t| {
            const h = hidden[t * EMBED_DIM .. (t + 1) * EMBED_DIM];
            self.layerNorm(h, lw.ffn_norm_weight, lw.ffn_norm_bias, scratch1);
            @memcpy(h, scratch1[0..EMBED_DIM]);
        }
    }

    /// LayerNorm: out = (x - mean) / sqrt(var + eps) * weight + bias
    fn layerNorm(self: *const EmbedModel, input: []const f32, weight_ref: TensorRef, bias_ref: TensorRef, output: []f32) void {
        _ = self;
        const n = input.len;
        const n_f: f32 = @floatFromInt(n);

        // Compute mean
        var mean: f32 = 0;
        for (input) |v| mean += v;
        mean /= n_f;

        // Compute variance
        var variance: f32 = 0;
        for (input) |v| {
            const d = v - mean;
            variance += d * d;
        }
        variance /= n_f;

        const inv_std = 1.0 / @sqrt(variance + LN_EPS);

        // Dequantize weight and bias
        var weight_buf: [EMBED_DIM]f32 = undefined;
        var bias_buf: [EMBED_DIM]f32 = undefined;
        quants.dequantize(weight_ref.data, &weight_buf, weight_ref.type_, n);
        quants.dequantize(bias_ref.data, &bias_buf, bias_ref.type_, n);

        for (0..n) |i| {
            output[i] = (input[i] - mean) * inv_std * weight_buf[i] + bias_buf[i];
        }
    }

    /// Linear layer forward (with bias): out = W * x + b
    fn linearForward(self: *const EmbedModel, weight: TensorRef, bias: TensorRef, input: []const f32, output: []f32, out_dim: usize, in_dim: usize) void {
        // Matrix-vector multiply (weight rows)
        self.linearForwardNoBias(weight, input, output, out_dim, in_dim);

        // Add bias
        var bias_buf: [FFN_DIM]f32 = undefined; // Large enough for FFN_DIM (largest bias)
        const bias_out = bias_buf[0..out_dim];
        quants.dequantize(bias.data, bias_out, bias.type_, out_dim);
        quants.vecAdd(output[0..out_dim], bias_out);
    }

    /// Linear layer forward (no bias): out = W * x
    /// Uses fused dequant-dot to avoid intermediate f32 buffer.
    fn linearForwardNoBias(self: *const EmbedModel, weight: TensorRef, input: []const f32, output: []f32, out_dim: usize, in_dim: usize) void {
        _ = self;

        const bb = quants.blockBytes(weight.type_);
        const bs = quants.blockSize(weight.type_);
        if (bs == 0 or bb == 0) {
            @memset(output[0..out_dim], 0);
            return;
        }
        const row_blocks = in_dim / bs;
        const row_bytes_len = row_blocks * bb;

        for (0..out_dim) |r| {
            const row_start = r * row_bytes_len;
            if (row_start + row_bytes_len <= weight.data.len) {
                output[r] = quants.fusedDot(weight.data[row_start .. row_start + row_bytes_len], input[0..in_dim], weight.type_, in_dim);
            } else {
                output[r] = 0;
            }
        }
    }

    /// Get raw bytes for row `row` of a tensor.
    fn getTensorRow(self: *const EmbedModel, ref: TensorRef, row: u32) ?[]const u8 {
        _ = self;
        const bs = quants.blockSize(ref.type_);
        const bb = quants.blockBytes(ref.type_);
        if (bs == 0 or bb == 0) return null;

        const blocks_per_row = ref.cols / bs;
        const row_bytes = blocks_per_row * bb;
        const start = row * row_bytes;
        const end = start + row_bytes;

        if (end > ref.data.len) return null;
        return ref.data[start..end];
    }
};

/// Load an embedding model from GGUF data.
/// The data must remain valid for the lifetime of the model (zero-copy).
pub fn loadModel(data: []const u8) !EmbedModel {
    const header = try gguf.parseHeader(data);

    var model: EmbedModel = undefined;
    model.data = data;

    // Load tokenizer (uses file-level static buffer — too large for stack)
    model.tokenizer = try tokenizer_mod.loadFromGguf(
        data,
        header,
        &g_vocab_buf,
    );

    // Calculate tensor data start
    model.tensor_data_start = try gguf.tensorDataStart(data, header);

    // Skip KV pairs to get to tensor info
    const tensor_info_offset = try gguf.skipAllKV(data, header);

    // Load tensor references — BERT naming convention from llama.cpp
    model.token_embed = try findTensorRef(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, "token_embd.weight") orelse
        return EmbedError.TensorNotFound;

    model.position_embed = try findTensorRef(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, "position_embd.weight") orelse
        return EmbedError.TensorNotFound;

    model.token_type_embed = try findTensorRef(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, "token_types.weight") orelse
        return EmbedError.TensorNotFound;

    // Final norm is optional — some BERT models don't have it
    model.final_norm_weight = try findTensorRef(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, "output_norm.weight");
    model.final_norm_bias = try findTensorRef(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, "output_norm.bias");

    // Load per-layer weights
    for (0..N_LAYERS) |i| {
        model.layers[i] = try loadLayerWeights(data, tensor_info_offset, header.n_tensors, model.tensor_data_start, i);
    }

    return model;
}

fn loadLayerWeights(data: []const u8, tensor_info_offset: usize, n_tensors: u64, tensor_data_start: usize, layer: usize) !LayerWeights {
    var name_buf: [128]u8 = undefined;

    return LayerWeights{
        .q_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_q.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .q_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_q.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .k_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_k.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .k_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_k.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .v_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_v.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .v_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_v.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .o_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_output.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .o_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_output.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .attn_norm_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_output_norm.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .attn_norm_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "attn_output_norm.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_up_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "ffn_up.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_up_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "ffn_up.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_down_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "ffn_down.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_down_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "ffn_down.bias", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_norm_weight = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "layer_output_norm.weight", &name_buf) orelse return EmbedError.TensorNotFound,
        .ffn_norm_bias = try findLayerTensor(data, tensor_info_offset, n_tensors, tensor_data_start, layer, "layer_output_norm.bias", &name_buf) orelse return EmbedError.TensorNotFound,
    };
}

fn findLayerTensor(
    data: []const u8,
    tensor_info_offset: usize,
    n_tensors: u64,
    tensor_data_start: usize,
    layer: usize,
    suffix: []const u8,
    name_buf: *[128]u8,
) !?TensorRef {
    // BERT naming: "blk.{layer}.{suffix}"
    const name = std.fmt.bufPrint(name_buf, "blk.{d}.{s}", .{ layer, suffix }) catch return null;
    return try findTensorRef(data, tensor_info_offset, n_tensors, tensor_data_start, name);
}

fn findTensorRef(
    data: []const u8,
    tensor_info_offset: usize,
    n_tensors: u64,
    tensor_data_start: usize,
    name: []const u8,
) !?TensorRef {
    const result = try gguf.findTensor(data, tensor_info_offset, n_tensors, name);
    if (result) |r| {
        const info = r[0];
        const abs_offset = tensor_data_start + @as(usize, @intCast(info.offset));

        // Calculate total bytes for this tensor
        const rows = if (info.n_dims >= 2) @as(usize, @intCast(info.dims[1])) else 1;
        const cols = @as(usize, @intCast(info.dims[0]));
        const bs = quants.blockSize(info.type_);
        const bb = quants.blockBytes(info.type_);
        if (bs == 0) return null;
        const total_elements = rows * cols;
        const total_blocks = total_elements / bs;
        const total_bytes = total_blocks * bb;

        if (abs_offset + total_bytes > data.len) return null;

        return TensorRef{
            .data = data[abs_offset .. abs_offset + total_bytes],
            .type_ = info.type_,
            .rows = rows,
            .cols = cols,
        };
    }
    return null;
}

/// Required scratch buffer size for embedding inference.
pub fn scratchSize() usize {
    const hidden_size = MAX_SEQ_LEN * EMBED_DIM;
    return hidden_size + EMBED_DIM + FFN_DIM + MAX_SEQ_LEN + 3 * hidden_size;
}

// --- Tests ---

test "scratch size" {
    const size = scratchSize();
    try std.testing.expect(size > 0);
    // ~776KB at f32 — scratch is per-token, doesn't scale with layer count
    try std.testing.expect(size * 4 < 1 * 1024 * 1024);
}
