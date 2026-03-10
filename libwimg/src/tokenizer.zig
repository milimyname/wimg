// SentencePiece BPE tokenizer for XLM-RoBERTa-based embedding models.
// Loads vocab and merges from GGUF metadata. Used by multilingual-e5-small.
// Cased tokenizer (no lowercasing). Uses ▁ (U+2581) as word boundary.

const std = @import("std");
const gguf = @import("gguf.zig");

pub const MAX_VOCAB_SIZE = 260000;
pub const MAX_TOKENS = 512;

// Hash table for fast vocab string → token ID lookup
const VOCAB_HASH_BITS = 19; // 524288 slots (~2x vocab for good load factor)
const VOCAB_HASH_SIZE = 1 << VOCAB_HASH_BITS;
const VOCAB_HASH_MASK = VOCAB_HASH_SIZE - 1;

pub const TokenizerError = error{
    VocabNotFound,
    TooManyTokens,
    BufferTooSmall,
};

// --- File-level statics (BSS on WASM — zero-initialized, no binary bloat) ---

// Vocab hash: stores (vocab_index + 1) per slot; 0 = empty.
var g_vocab_hash: [VOCAB_HASH_SIZE]u32 = undefined;
var g_vocab_hash_ready: bool = false;

// Per-token BPE score. SentencePiece stores a float score per vocab token.
// Higher score = higher priority (merged first). Tokens without scores get -inf.
var g_merge_score: [MAX_VOCAB_SIZE]f32 = undefined;

// Temporary buffer for loading merge strings from GGUF (fallback for GPT-2 style merges).
var g_merge_str_buf: [MAX_VOCAB_SIZE][]const u8 = undefined;

// --- Hash table helpers ---

fn hashStr(s: []const u8) u32 {
    var h: u32 = 5381;
    for (s) |c| h = (h *% 33) +% c;
    return h;
}

fn vocabHashInsert(vocab: []const []const u8, idx: u32) void {
    var slot = hashStr(vocab[idx]) & VOCAB_HASH_MASK;
    while (g_vocab_hash[slot] != 0) {
        slot = (slot + 1) & VOCAB_HASH_MASK;
    }
    g_vocab_hash[slot] = idx + 1; // +1 so 0 means empty
}

fn vocabHashLookup(vocab: []const []const u8, vocab_size: u32, s: []const u8) ?u32 {
    if (!g_vocab_hash_ready) return null;
    const h = hashStr(s);
    var slot = h & VOCAB_HASH_MASK;
    var probes: u32 = 0;
    while (probes < VOCAB_HASH_SIZE) : (probes += 1) {
        const stored = g_vocab_hash[slot];
        if (stored == 0) return null;
        const idx = stored - 1;
        if (idx < vocab_size) {
            const tok = vocab[idx];
            if (tok.len == s.len and std.mem.eql(u8, tok, s)) return idx;
        }
        slot = (slot + 1) & VOCAB_HASH_MASK;
    }
    return null;
}

// --- UTF-8 helpers ---

fn utf8CharLen(first_byte: u8) usize {
    if (first_byte < 0x80) return 1;
    if (first_byte < 0xC0) return 1; // continuation byte (shouldn't start a char)
    if (first_byte < 0xE0) return 2;
    if (first_byte < 0xF0) return 3;
    return 4;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// ▁ = U+2581 = 0xE2 0x96 0x81 (3 bytes in UTF-8)
const SPIECE_PREFIX = [3]u8{ 0xE2, 0x96, 0x81 };

pub const Tokenizer = struct {
    // Vocabulary: token_id → string slice (points into GGUF data)
    vocab: [][]const u8,
    vocab_size: u32,

    // Special token IDs (XLM-RoBERTa / fairseq convention)
    cls_id: u32, // <s> = 0
    sep_id: u32, // </s> = 2
    unk_id: u32, // <unk> = 3
    pad_id: u32, // <pad> = 1

    /// Encode text into token IDs using SentencePiece BPE.
    /// Adds <s> at start and </s> at end.
    /// Returns the number of tokens written to output_ids.
    pub fn encode(self: *const Tokenizer, text: []const u8, output_ids: []u32) TokenizerError!u32 {
        if (output_ids.len < 2) return TokenizerError.BufferTooSmall;

        var count: u32 = 0;

        // <s> (CLS) token
        output_ids[count] = self.cls_id;
        count += 1;

        if (text.len == 0) {
            output_ids[count] = self.sep_id;
            count += 1;
            return count;
        }

        // Pre-tokenize: split on whitespace, prepend ▁ to each word
        var i: usize = 0;
        while (i < text.len) {
            // Skip whitespace
            while (i < text.len and isWhitespace(text[i])) i += 1;
            if (i >= text.len) break;

            // Find word end
            var word_end = i;
            while (word_end < text.len and !isWhitespace(text[word_end])) word_end += 1;

            // Build "▁" + word in a buffer (cased — no lowercasing)
            var word_buf: [512]u8 = undefined;
            word_buf[0] = SPIECE_PREFIX[0];
            word_buf[1] = SPIECE_PREFIX[1];
            word_buf[2] = SPIECE_PREFIX[2];
            const raw_word = text[i..word_end];
            const word_len = @min(raw_word.len, word_buf.len - 3);
            @memcpy(word_buf[3 .. 3 + word_len], raw_word[0..word_len]);
            const full_word = word_buf[0 .. 3 + word_len];

            // Split into UTF-8 characters and get initial token IDs
            var char_tokens: [256]u32 = undefined;
            var n_chars: usize = 0;
            var ci: usize = 0;
            while (ci < full_word.len and n_chars < char_tokens.len) {
                const char_len = utf8CharLen(full_word[ci]);
                const char_end = @min(ci + char_len, full_word.len);
                const char_str = full_word[ci..char_end];
                char_tokens[n_chars] = vocabHashLookup(
                    self.vocab,
                    self.vocab_size,
                    char_str,
                ) orelse self.unk_id;
                n_chars += 1;
                ci = char_end;
            }

            // BPE merge loop: repeatedly merge the pair with highest score
            while (n_chars > 1) {
                var best_score: f32 = -std.math.inf(f32);
                var best_i: usize = 0;
                var best_merged: u32 = 0;
                var found = false;

                for (0..n_chars - 1) |j| {
                    // Skip UNK tokens — can't merge them
                    if (char_tokens[j] == self.unk_id or char_tokens[j + 1] == self.unk_id) continue;

                    // Concatenate strings of adjacent tokens
                    const str_a = self.vocab[char_tokens[j]];
                    const str_b = self.vocab[char_tokens[j + 1]];
                    var concat_buf: [256]u8 = undefined;
                    if (str_a.len + str_b.len > concat_buf.len) continue;
                    @memcpy(concat_buf[0..str_a.len], str_a);
                    @memcpy(concat_buf[str_a.len .. str_a.len + str_b.len], str_b);
                    const concat = concat_buf[0 .. str_a.len + str_b.len];

                    // Look up merged token in vocab
                    if (vocabHashLookup(self.vocab, self.vocab_size, concat)) |merged_id| {
                        const score = g_merge_score[merged_id];
                        if (score > best_score) {
                            best_score = score;
                            best_i = j;
                            best_merged = merged_id;
                            found = true;
                        }
                    }
                }

                if (!found) break;

                // Apply the best merge
                char_tokens[best_i] = best_merged;
                // Shift remaining tokens left by 1
                var k: usize = best_i + 1;
                while (k + 1 < n_chars) : (k += 1) {
                    char_tokens[k] = char_tokens[k + 1];
                }
                n_chars -= 1;
            }

            // Emit tokens (truncate if buffer full, reserving 1 slot for </s>)
            for (char_tokens[0..n_chars]) |tid| {
                if (count + 1 >= output_ids.len) break;
                output_ids[count] = tid;
                count += 1;
            }

            i = word_end;
            if (count + 1 >= output_ids.len) break; // No room for more words
        }

        // </s> (SEP) token — always appended (we reserved 1 slot)
        output_ids[count] = self.sep_id;
        count += 1;

        return count;
    }
};

/// Load tokenizer from GGUF model data.
/// Caller provides buffer for vocab array (must be >= MAX_VOCAB_SIZE).
pub fn loadFromGguf(
    data: []const u8,
    header: gguf.GgufHeader,
    vocab_buf: [][]const u8,
) !Tokenizer {
    // 1. Load vocab tokens
    const vocab_count = (try gguf.getStringArrayKV(data, header, "tokenizer.ggml.tokens", vocab_buf)) orelse
        return TokenizerError.VocabNotFound;
    const vs: u32 = @intCast(@min(@as(usize, @intCast(vocab_count)), vocab_buf.len));

    // 2. Build vocab hash table
    @memset(&g_vocab_hash, 0);
    @memset(&g_merge_score, -std.math.inf(f32));
    for (0..vs) |idx| {
        vocabHashInsert(vocab_buf, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    // 3. Load BPE scores — try tokenizer.ggml.scores first (SentencePiece),
    //    fall back to tokenizer.ggml.merges (GPT-2 style).
    const score_count_opt = try gguf.getF32ArrayKV(data, header, "tokenizer.ggml.scores", &g_merge_score);
    if (score_count_opt == null) {
        // Fallback: load explicit merge pairs and assign decreasing scores
        const merge_count_opt = try gguf.getStringArrayKV(data, header, "tokenizer.ggml.merges", &g_merge_str_buf);
        if (merge_count_opt) |mc| {
            const merge_count: usize = @intCast(@min(mc, MAX_VOCAB_SIZE));

            for (0..merge_count) |r| {
                const merge_str = g_merge_str_buf[r];

                var space_pos: usize = 0;
                while (space_pos < merge_str.len and merge_str[space_pos] != ' ') space_pos += 1;
                if (space_pos == 0 or space_pos >= merge_str.len) continue;

                const str_a = merge_str[0..space_pos];
                const str_b = merge_str[space_pos + 1 ..];
                if (str_a.len == 0 or str_b.len == 0) continue;

                var concat_buf: [512]u8 = undefined;
                if (str_a.len + str_b.len > concat_buf.len) continue;
                @memcpy(concat_buf[0..str_a.len], str_a);
                @memcpy(concat_buf[str_a.len .. str_a.len + str_b.len], str_b);
                const concat = concat_buf[0 .. str_a.len + str_b.len];

                if (vocabHashLookup(vocab_buf, vs, concat)) |result_id| {
                    // Earlier merges = higher priority = higher score
                    g_merge_score[result_id] = -@as(f32, @floatFromInt(r));
                }
            }
        }
    }

    // 4. Read special token IDs (XLM-RoBERTa / fairseq defaults)
    const cls = (try gguf.getU32KV(data, header, "tokenizer.ggml.cls_token_id")) orelse
        (try gguf.getU32KV(data, header, "tokenizer.ggml.bos_token_id")) orelse 0;
    const sep = (try gguf.getU32KV(data, header, "tokenizer.ggml.sep_token_id")) orelse
        (try gguf.getU32KV(data, header, "tokenizer.ggml.eos_token_id")) orelse 2;
    const unk = (try gguf.getU32KV(data, header, "tokenizer.ggml.unknown_token_id")) orelse
        ((try gguf.getU32KV(data, header, "tokenizer.ggml.unk_token_id")) orelse 3);
    const pad = (try gguf.getU32KV(data, header, "tokenizer.ggml.padding_token_id")) orelse 1;

    return Tokenizer{
        .vocab = vocab_buf,
        .vocab_size = vs,
        .cls_id = cls,
        .sep_id = sep,
        .unk_id = unk,
        .pad_id = pad,
    };
}

// --- Tests ---

test "tokenizer bpe basic" {
    // Tiny vocab simulating SentencePiece BPE with bottom-up merge chain:
    // "▁hello" = ▁ + h + e + l + l + o
    //   → h+e=he → l+l=ll → he+ll=hell → hell+o=hello → ▁+hello=▁hello
    var vocab = [_][]const u8{
        "<s>", // 0 (CLS)
        "<pad>", // 1
        "</s>", // 2 (SEP)
        "<unk>", // 3 (UNK)
        "\xE2\x96\x81", // 4: ▁
        "h", // 5
        "e", // 6
        "l", // 7
        "o", // 8
        "he", // 9:  h + e
        "ll", // 10: l + l
        "hell", // 11: he + ll
        "hello", // 12: hell + o
        "\xE2\x96\x81hello", // 13: ▁ + hello
    };

    // Build hash table for this test vocab
    @memset(&g_vocab_hash, 0);
    @memset(&g_merge_score, -std.math.inf(f32));
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    // Set merge scores (higher = higher priority, applied first)
    g_merge_score[9] = 5.0; // h + e → he (highest priority)
    g_merge_score[10] = 4.0; // l + l → ll
    g_merge_score[11] = 3.0; // he + ll → hell
    g_merge_score[12] = 2.0; // hell + o → hello
    g_merge_score[13] = 1.0; // ▁ + hello → ▁hello (lowest priority)

    const tok = Tokenizer{
        .vocab = &vocab,
        .vocab_size = @intCast(vocab.len),
        .cls_id = 0,
        .sep_id = 2,
        .unk_id = 3,
        .pad_id = 1,
    };

    var ids: [10]u32 = undefined;
    const n = try tok.encode("hello", &ids);
    // <s>, ▁hello, </s>
    try std.testing.expectEqual(@as(u32, 3), n);
    try std.testing.expectEqual(@as(u32, 0), ids[0]); // <s>
    try std.testing.expectEqual(@as(u32, 13), ids[1]); // ▁hello
    try std.testing.expectEqual(@as(u32, 2), ids[2]); // </s>
}

test "tokenizer empty input" {
    @memset(&g_vocab_hash, 0);
    g_vocab_hash_ready = true;

    var vocab = [_][]const u8{ "<s>", "<pad>", "</s>", "<unk>" };
    const tok = Tokenizer{
        .vocab = &vocab,
        .vocab_size = 4,
        .cls_id = 0,
        .sep_id = 2,
        .unk_id = 3,
        .pad_id = 1,
    };

    var ids: [10]u32 = undefined;
    const n = try tok.encode("", &ids);
    try std.testing.expectEqual(@as(u32, 2), n); // <s> + </s>
    try std.testing.expectEqual(@as(u32, 0), ids[0]); // <s>
    try std.testing.expectEqual(@as(u32, 2), ids[1]); // </s>
}

test "tokenizer no merges falls back to chars" {
    var vocab = [_][]const u8{
        "<s>", // 0
        "<pad>", // 1
        "</s>", // 2
        "<unk>", // 3
        "\xE2\x96\x81", // 4: ▁
        "a", // 5
        "b", // 6
    };

    @memset(&g_vocab_hash, 0);
    @memset(&g_merge_score, -std.math.inf(f32));
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    const tok = Tokenizer{
        .vocab = &vocab,
        .vocab_size = @intCast(vocab.len),
        .cls_id = 0,
        .sep_id = 2,
        .unk_id = 3,
        .pad_id = 1,
    };

    var ids: [20]u32 = undefined;
    const n = try tok.encode("ab", &ids);
    // <s>, ▁, a, b, </s>
    try std.testing.expectEqual(@as(u32, 5), n);
    try std.testing.expectEqual(@as(u32, 0), ids[0]); // <s>
    try std.testing.expectEqual(@as(u32, 4), ids[1]); // ▁
    try std.testing.expectEqual(@as(u32, 5), ids[2]); // a
    try std.testing.expectEqual(@as(u32, 6), ids[3]); // b
    try std.testing.expectEqual(@as(u32, 2), ids[4]); // </s>
}

test "vocab hash lookup" {
    var vocab = [_][]const u8{ "hello", "world", "foo" };

    @memset(&g_vocab_hash, 0);
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    try std.testing.expectEqual(@as(?u32, 0), vocabHashLookup(&vocab, 3, "hello"));
    try std.testing.expectEqual(@as(?u32, 1), vocabHashLookup(&vocab, 3, "world"));
    try std.testing.expectEqual(@as(?u32, 2), vocabHashLookup(&vocab, 3, "foo"));
    try std.testing.expectEqual(@as(?u32, null), vocabHashLookup(&vocab, 3, "bar"));
}
