#!/usr/bin/env python3
"""Patch a GGUF file to add tokenizer.ggml.scores from a SentencePiece model.

The llama.cpp convert_hf_to_gguf.py for BERT/XLM-RoBERTa models doesn't include
BPE merge scores. This script adds them from the original SentencePiece model.

Token mapping (XLM-RoBERTa fairseq convention):
  GGUF[0] = <s>       → special, score = 0
  GGUF[1] = <pad>     → special, score = 0
  GGUF[2] = </s>      → special, score = 0
  GGUF[3] = <unk>     → special, score = 0
  GGUF[k] = SP[k-1]   → score = SP.GetScore(k-1)  for k >= 4

Usage:
  python3 scripts/patch-gguf-scores.py input.gguf sentencepiece.bpe.model output.gguf
"""

import struct
import sys
import os
import sentencepiece as spm


def read_u32(f):
    return struct.unpack('<I', f.read(4))[0]

def read_u64(f):
    return struct.unpack('<Q', f.read(8))[0]

def read_string(f):
    length = read_u64(f)
    return f.read(length)

def write_u32(f, v):
    f.write(struct.pack('<I', v))

def write_u64(f, v):
    f.write(struct.pack('<Q', v))

def write_string(f, s):
    if isinstance(s, str):
        s = s.encode('utf-8')
    write_u64(f, len(s))
    f.write(s)


def skip_value(f, vtype):
    """Skip a GGUF metadata value."""
    sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
    if vtype in sizes:
        f.read(sizes[vtype])
    elif vtype == 8:  # string
        read_string(f)
    elif vtype == 9:  # array
        arr_type = read_u32(f)
        arr_len = read_u64(f)
        for _ in range(arr_len):
            skip_value(f, arr_type)
    else:
        raise ValueError(f"Unknown value type: {vtype}")


def copy_value(fin, fout, vtype):
    """Copy a GGUF metadata value from input to output."""
    sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
    if vtype in sizes:
        fout.write(fin.read(sizes[vtype]))
    elif vtype == 8:  # string
        s = read_string(fin)
        write_string(fout, s)
    elif vtype == 9:  # array
        arr_type = read_u32(fin)
        arr_len = read_u64(fin)
        write_u32(fout, arr_type)
        write_u64(fout, arr_len)
        for _ in range(arr_len):
            copy_value(fin, fout, arr_type)
    else:
        raise ValueError(f"Unknown value type: {vtype}")


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} input.gguf sentencepiece.bpe.model output.gguf")
        sys.exit(1)

    in_path, sp_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    # Load SentencePiece model
    sp = spm.SentencePieceProcessor()
    sp.Load(sp_path)
    sp_vocab_size = sp.GetPieceSize()
    print(f"SentencePiece vocab: {sp_vocab_size} tokens")

    with open(in_path, 'rb') as fin:
        # Parse header
        magic = read_u32(fin)
        assert magic == 0x46554747, f"Bad magic: {hex(magic)}"
        version = read_u32(fin)
        n_tensors = read_u64(fin)
        n_kv = read_u64(fin)
        print(f"Input: GGUF v{version}, {n_tensors} tensors, {n_kv} KV pairs")

        # Read KV pairs (remember positions for copying)
        kv_pairs = []
        gguf_vocab_size = 0
        has_scores = False

        for _ in range(n_kv):
            key = read_string(fin)
            vtype = read_u32(fin)
            val_start = fin.tell()

            # Check for existing scores
            key_str = key.decode('utf-8', errors='replace')
            if key_str == 'tokenizer.ggml.scores':
                has_scores = True
                print("WARNING: GGUF already has tokenizer.ggml.scores — will replace")

            # Get vocab size from tokens array
            if key_str == 'tokenizer.ggml.tokens' and vtype == 9:
                arr_type = read_u32(fin)
                gguf_vocab_size = read_u64(fin)
                fin.seek(val_start)  # seek back to re-read during copy

            skip_value(fin, vtype)
            val_end = fin.tell()
            kv_pairs.append((key, vtype, val_start, val_end))

        print(f"GGUF vocab size: {gguf_vocab_size}")

        # Read tensor infos
        tensor_info_start = fin.tell()
        tensor_infos = []
        for _ in range(n_tensors):
            name = read_string(fin)
            n_dims = read_u32(fin)
            dims = [read_u64(fin) for _ in range(n_dims)]
            ttype = read_u32(fin)
            offset = read_u64(fin)
            tensor_infos.append({
                'name': name, 'n_dims': n_dims, 'dims': dims,
                'type': ttype, 'offset': offset,
            })

        # Tensor data starts after alignment
        pos = fin.tell()
        alignment = 32
        tensor_data_start = (pos + alignment - 1) & ~(alignment - 1)

        # Build scores array
        # Mapping: GGUF[k] = SP[k-1] for k >= 4, special tokens get 0
        scores = []
        for k in range(gguf_vocab_size):
            if k < 4:
                scores.append(0.0)  # special tokens
            else:
                sp_id = k - 1
                if sp_id < sp_vocab_size:
                    scores.append(sp.GetScore(sp_id))
                else:
                    scores.append(0.0)  # extra tokens beyond SP vocab

        print(f"Built {len(scores)} scores")
        print(f"  scores[4] = {scores[4]:.4f} (should be {sp.GetScore(3):.4f} for ',')")
        print(f"  scores[7] = {scores[7]:.4f} (should be {sp.GetScore(6):.4f} for 's')")

        # Write output
        new_n_kv = n_kv + (0 if has_scores else 1)

        with open(out_path, 'wb') as fout:
            # Header
            write_u32(fout, magic)
            write_u32(fout, version)
            write_u64(fout, n_tensors)
            write_u64(fout, new_n_kv)

            # Copy existing KV pairs (skip scores if replacing)
            for key, vtype, val_start, val_end in kv_pairs:
                key_str = key.decode('utf-8', errors='replace')
                if key_str == 'tokenizer.ggml.scores' and has_scores:
                    continue  # skip, we'll write new one
                write_string(fout, key)
                write_u32(fout, vtype)
                fin.seek(val_start)
                fout.write(fin.read(val_end - val_start))

            # Add scores KV pair
            write_string(fout, b'tokenizer.ggml.scores')
            write_u32(fout, 9)  # array type
            write_u32(fout, 6)  # float32 element type
            write_u64(fout, len(scores))
            for s in scores:
                fout.write(struct.pack('<f', s))
            print(f"Added tokenizer.ggml.scores ({len(scores)} float32 values)")

            # Copy tensor infos
            for t in tensor_infos:
                write_string(fout, t['name'])
                write_u32(fout, t['n_dims'])
                for d in t['dims']:
                    write_u64(fout, d)
                write_u32(fout, t['type'])
                write_u64(fout, t['offset'])

            # Pad to alignment
            pos = fout.tell()
            pad = ((pos + alignment - 1) & ~(alignment - 1)) - pos
            fout.write(b'\x00' * pad)

            # Copy all tensor data
            fin.seek(tensor_data_start)
            chunk_size = 1024 * 1024  # 1MB chunks
            while True:
                chunk = fin.read(chunk_size)
                if not chunk:
                    break
                fout.write(chunk)

    in_size = os.path.getsize(in_path)
    out_size = os.path.getsize(out_path)
    print(f"\nDone: {in_size / 1024 / 1024:.1f} MB → {out_size / 1024 / 1024:.1f} MB")


if __name__ == '__main__':
    main()
