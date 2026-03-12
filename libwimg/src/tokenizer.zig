// SentencePiece Unigram tokenizer for XLM-RoBERTa-based embedding models.
// Loads vocab and scores from GGUF metadata. Used by multilingual-e5-small.
// Uses Viterbi algorithm to find optimal segmentation (max total log-prob).
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

            // Viterbi segmentation: find segmentation maximizing total score.
            // best_score[j] = best total score for full_word[0..j]
            // best_len[j] = byte length of last token in the best path to j
            // best_id[j] = token ID of that last token
            const wlen = full_word.len;
            var best_score_dp: [513]f32 = undefined;
            var best_len: [513]usize = undefined;
            var best_id: [513]u32 = undefined;
            best_score_dp[0] = 0;
            best_len[0] = 0;
            best_id[0] = 0;
            for (1..wlen + 1) |j| {
                best_score_dp[j] = -std.math.inf(f32);
                best_len[j] = 0;
                best_id[j] = self.unk_id;
            }

            // Max token length in vocab is 48 bytes; limit substring search
            const MAX_TOKEN_BYTES = 48;

            for (1..wlen + 1) |j| {
                // Try all substrings ending at byte position j
                const min_start = if (j > MAX_TOKEN_BYTES) j - MAX_TOKEN_BYTES else 0;
                var start = min_start;
                while (start < j) : (start += 1) {
                    const substr = full_word[start..j];
                    if (vocabHashLookup(self.vocab, self.vocab_size, substr)) |tid| {
                        const score = g_merge_score[tid];
                        const total = best_score_dp[start] + score;
                        if (total > best_score_dp[j]) {
                            best_score_dp[j] = total;
                            best_len[j] = j - start;
                            best_id[j] = tid;
                        }
                    }
                }

                // UNK fallback: if no vocab token ends at j, try single UTF-8 char
                if (best_score_dp[j] == -std.math.inf(f32)) {
                    // Find the UTF-8 char that ends at or contains position j
                    // by backing up to find a valid char start
                    var char_start = j - 1;
                    while (char_start > 0 and (full_word[char_start] & 0xC0) == 0x80) {
                        char_start -= 1;
                    }
                    const clen = utf8CharLen(full_word[char_start]);
                    const char_end = @min(char_start + clen, wlen);
                    if (char_end == j) {
                        // This is a complete UTF-8 char boundary — emit UNK
                        const unk_penalty: f32 = -100.0;
                        const total = best_score_dp[char_start] + unk_penalty;
                        if (total > best_score_dp[j]) {
                            best_score_dp[j] = total;
                            best_len[j] = j - char_start;
                            best_id[j] = self.unk_id;
                        }
                    }
                }
            }

            // Backtrace: collect tokens in reverse, then reverse
            var char_tokens: [256]u32 = undefined;
            var n_chars: usize = 0;
            var pos = wlen;
            while (pos > 0 and n_chars < char_tokens.len) {
                char_tokens[n_chars] = best_id[pos];
                n_chars += 1;
                const step = best_len[pos];
                if (step == 0) break; // shouldn't happen, safety check
                pos -= step;
            }

            // Reverse in-place to get left-to-right order
            if (n_chars > 1) {
                var lo: usize = 0;
                var hi: usize = n_chars - 1;
                while (lo < hi) {
                    const tmp = char_tokens[lo];
                    char_tokens[lo] = char_tokens[hi];
                    char_tokens[hi] = tmp;
                    lo += 1;
                    hi -= 1;
                }
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

    // 1b. Strip spurious ▁ prefix from all vocab entries.
    // Some GGUF converters (convert_hf_to_gguf.py) prepend ▁ to every token
    // in SentencePiece models. Detect and strip if special tokens like <s> have it.
    if (vs > 0 and vocab_buf[0].len >= 3 and
        vocab_buf[0][0] == SPIECE_PREFIX[0] and
        vocab_buf[0][1] == SPIECE_PREFIX[1] and
        vocab_buf[0][2] == SPIECE_PREFIX[2])
    {
        for (0..vs) |idx| {
            const tok = vocab_buf[idx];
            if (tok.len >= 3 and tok[0] == SPIECE_PREFIX[0] and
                tok[1] == SPIECE_PREFIX[1] and tok[2] == SPIECE_PREFIX[2])
            {
                vocab_buf[idx] = tok[3..]; // Strip leading ▁
            }
        }
    }

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

/// Get BPE merge score for a token ID (for diagnostics).
pub fn getMergeScore(id: u32) f32 {
    if (id < MAX_VOCAB_SIZE) return g_merge_score[id];
    return -std.math.inf(f32);
}

// --- Test helpers ---
// Workaround for Zig 0.15.2 x86_64 backend bug: @memset on large arrays in
// test blocks triggers "emit MIR failed: InvalidInstruction". Using noinline
// helpers moves the memset out of the test function's codegen scope.

fn testResetHash() void {
    for (&g_vocab_hash) |*s| s.* = 0;
    g_vocab_hash_ready = false;
}

fn testResetScores() void {
    for (&g_merge_score) |*s| s.* = -std.math.inf(f32);
}

// --- Tests ---

test "tokenizer viterbi basic" {
    // Tiny vocab simulating SentencePiece Unigram model.
    // Viterbi picks the segmentation with maximum total score.
    // For "▁hello", the full token ▁hello has score -5.0,
    // while splitting into ▁hell + o has -8.0 + -2.0 = -10.0 (worse).
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
        "he", // 9
        "ll", // 10
        "hell", // 11
        "hello", // 12
        "\xE2\x96\x81hello", // 13: ▁hello
        "\xE2\x96\x81hell", // 14: ▁hell
    };

    testResetHash();
    testResetScores();
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    // Unigram log-probabilities (higher = more likely)
    g_merge_score[4] = -10.0; // ▁
    g_merge_score[5] = -12.0; // h
    g_merge_score[6] = -11.0; // e
    g_merge_score[7] = -11.5; // l
    g_merge_score[8] = -9.0; // o
    g_merge_score[9] = -10.0; // he
    g_merge_score[10] = -10.5; // ll
    g_merge_score[11] = -8.0; // hell
    g_merge_score[12] = -7.0; // hello
    g_merge_score[13] = -5.0; // ▁hello (best: -5.0 total)
    g_merge_score[14] = -6.0; // ▁hell

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
    // Viterbi picks ▁hello (score -5.0) over ▁hell+o (-6.0+-9.0=-15.0)
    // <s>, ▁hello, </s>
    try std.testing.expectEqual(@as(u32, 3), n);
    try std.testing.expectEqual(@as(u32, 0), ids[0]); // <s>
    try std.testing.expectEqual(@as(u32, 13), ids[1]); // ▁hello
    try std.testing.expectEqual(@as(u32, 2), ids[2]); // </s>
}

test "tokenizer viterbi prefers optimal split" {
    // Viterbi should pick ▁hell + o over ▁hel + lo when that has better total score
    var vocab = [_][]const u8{
        "<s>", // 0
        "<pad>", // 1
        "</s>", // 2
        "<unk>", // 3
        "\xE2\x96\x81", // 4: ▁
        "h", // 5
        "e", // 6
        "l", // 7
        "o", // 8
        "\xE2\x96\x81hell", // 9: ▁hell
        "\xE2\x96\x81hel", // 10: ▁hel
        "lo", // 11
    };

    testResetHash();
    testResetScores();
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    // Scores: ▁hell + o = -9.0 + -2.0 = -11.0 (better)
    //         ▁hel + lo = -8.5 + -8.5 = -17.0 (worse)
    g_merge_score[4] = -10.0;
    g_merge_score[5] = -12.0;
    g_merge_score[6] = -11.0;
    g_merge_score[7] = -11.5;
    g_merge_score[8] = -2.0; // o
    g_merge_score[9] = -9.0; // ▁hell
    g_merge_score[10] = -8.5; // ▁hel
    g_merge_score[11] = -8.5; // lo

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
    // Viterbi: ▁hell(-9.0) + o(-2.0) = -11.0 beats ▁hel(-8.5) + lo(-8.5) = -17.0
    try std.testing.expectEqual(@as(u32, 4), n);
    try std.testing.expectEqual(@as(u32, 0), ids[0]); // <s>
    try std.testing.expectEqual(@as(u32, 9), ids[1]); // ▁hell
    try std.testing.expectEqual(@as(u32, 8), ids[2]); // o
    try std.testing.expectEqual(@as(u32, 2), ids[3]); // </s>
}

test "tokenizer empty input" {
    testResetHash();
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
    // When vocab only has single chars (no multi-char tokens for "ab"),
    // Viterbi segments into individual character tokens.
    var vocab = [_][]const u8{
        "<s>", // 0
        "<pad>", // 1
        "</s>", // 2
        "<unk>", // 3
        "\xE2\x96\x81", // 4: ▁
        "a", // 5
        "b", // 6
        "\xE2\x96\x81" ++ "a", // 7: ▁a
        "\xE2\x96\x81" ++ "ab", // 8: ▁ab  (not in vocab → forces char split)
    };
    // Only use first 7 entries (0-6), so ▁ab is NOT available
    const vs: u32 = 7;

    testResetHash();
    testResetScores();
    for (0..vs) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    // Set unigram scores for character tokens
    g_merge_score[4] = -5.0; // ▁
    g_merge_score[5] = -6.0; // a
    g_merge_score[6] = -6.0; // b

    const tok = Tokenizer{
        .vocab = vocab[0..vs],
        .vocab_size = vs,
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

    testResetHash();
    for (0..vocab.len) |idx| {
        vocabHashInsert(&vocab, @intCast(idx));
    }
    g_vocab_hash_ready = true;

    try std.testing.expectEqual(@as(?u32, 0), vocabHashLookup(&vocab, 3, "hello"));
    try std.testing.expectEqual(@as(?u32, 1), vocabHashLookup(&vocab, 3, "world"));
    try std.testing.expectEqual(@as(?u32, 2), vocabHashLookup(&vocab, 3, "foo"));
    try std.testing.expectEqual(@as(?u32, null), vocabHashLookup(&vocab, 3, "bar"));
}
