#!/usr/bin/env python3
"""Convert a FP32 GGUF to Q8_0
 GGUF. No dependencies beyond Python stdlib."""

import struct
import sys
import os
import math

GGUF_MAGIC = 0x46554747
BLOCK_SIZE = 32  # Q8_0 block: 32 elements

# GGML type IDs
GGML_F32 = 0
GGML_F16 = 1
GGML_Q8_0 = 8

# Type sizes: (block_size, block_bytes)
TYPE_INFO = {
    0: (1, 4),    # F32: 1 element = 4 bytes
    1: (1, 2),    # F16: 1 element = 2 bytes
    8: (32, 34),  # Q8_0: 32 elements = 34 bytes
}


def f32_to_f16_bytes(f):
    """Convert a float32 to IEEE 754 float16 bytes (little-endian)."""
    # Use struct to get f32 bits, then manually convert
    bits = struct.unpack('<I', struct.pack('<f', f))[0]
    sign = (bits >> 31) & 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF

    if exp == 0:  # zero / subnormal
        return struct.pack('<H', sign << 15)
    elif exp == 0xFF:  # inf / nan
        h = (sign << 15) | 0x7C00 | (1 if frac else 0)
        return struct.pack('<H', h)
    else:
        new_exp = exp - 127 + 15
        if new_exp >= 31:  # overflow → inf
            return struct.pack('<H', (sign << 15) | 0x7C00)
        elif new_exp <= 0:  # underflow → zero
            return struct.pack('<H', sign << 15)
        else:
            h = (sign << 15) | (new_exp << 10) | (frac >> 13)
            return struct.pack('<H', h)


def quantize_block_q8_0(floats):
    """Quantize 32 f32 values to one Q8_0 block (34 bytes)."""
    max_abs = max(abs(v) for v in floats) if floats else 0.0
    if max_abs == 0:
        return f32_to_f16_bytes(0.0) + bytes(BLOCK_SIZE)

    scale = max_abs / 127.0
    inv_scale = 1.0 / scale

    quants = []
    for v in floats:
        q = int(round(v * inv_scale))
        q = max(-128, min(127, q))
        quants.append(q & 0xFF)  # store as unsigned byte, interpret as signed

    return f32_to_f16_bytes(scale) + bytes(quants)


def read_u32(f):
    return struct.unpack('<I', f.read(4))[0]

def read_u64(f):
    return struct.unpack('<Q', f.read(8))[0]

def read_i64(f):
    return struct.unpack('<q', f.read(8))[0]

def read_string(f):
    length = read_u64(f)
    return f.read(length)

def write_u32(f, v):
    f.write(struct.pack('<I', v))

def write_u64(f, v):
    f.write(struct.pack('<Q', v))

def write_string(f, s):
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
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input-fp32.gguf output-q8_0.gguf")
        sys.exit(1)

    in_path, out_path = sys.argv[1], sys.argv[2]
    in_size = os.path.getsize(in_path)

    with open(in_path, 'rb') as fin:
        # --- Parse header ---
        magic = read_u32(fin)
        assert magic == GGUF_MAGIC, f"Bad magic: {hex(magic)}"
        version = read_u32(fin)
        n_tensors = read_u64(fin)
        n_kv = read_u64(fin)
        print(f"GGUF v{version}: {n_tensors} tensors, {n_kv} KV pairs")

        # --- Read and buffer KV pairs ---
        kv_start = fin.tell()
        # We need to copy KV data verbatim, so remember the position
        kv_pairs = []
        for _ in range(n_kv):
            key = read_string(fin)
            vtype = read_u32(fin)
            val_start = fin.tell()
            skip_value(fin, vtype)
            val_end = fin.tell()
            kv_pairs.append((key, vtype, val_start, val_end))

        # --- Read tensor infos ---
        tensor_infos = []
        for _ in range(n_tensors):
            name = read_string(fin)
            n_dims = read_u32(fin)
            dims = [read_u64(fin) for _ in range(n_dims)]
            ttype = read_u32(fin)
            offset = read_u64(fin)
            tensor_infos.append({
                'name': name,
                'n_dims': n_dims,
                'dims': dims,
                'type': ttype,
                'offset': offset,
            })

        # Align to 32 bytes for tensor data start
        pos = fin.tell()
        alignment = 32
        tensor_data_start = (pos + alignment - 1) & ~(alignment - 1)

        # --- Plan quantization ---
        # Only quantize F32 weight tensors with element count divisible by 32.
        # Leave biases, norms, embeddings as-is (small, need precision).
        tensors_to_quantize = set()
        for t in tensor_infos:
            name = t['name'].decode('utf-8', errors='replace')
            n_elements = 1
            for d in t['dims']:
                n_elements *= d

            # Quantize all F32 tensors with enough elements for Q8_0 blocks.
            # Skip only biases (1D small) and norms (1D small) — these need precision.
            is_large = n_elements >= BLOCK_SIZE and n_elements % BLOCK_SIZE == 0

            if t['type'] == GGML_F32 and is_large:
                tensors_to_quantize.add(t['name'])

        n_quant = len(tensors_to_quantize)
        print(f"Quantizing {n_quant}/{n_tensors} tensors to Q8_0")

        # --- Write output ---
        with open(out_path, 'wb') as fout:
            # Header
            write_u32(fout, GGUF_MAGIC)
            write_u32(fout, version)
            write_u64(fout, n_tensors)
            write_u64(fout, n_kv)

            # KV pairs (copy verbatim from input)
            for key, vtype, val_start, val_end in kv_pairs:
                write_string(fout, key)
                write_u32(fout, vtype)
                fin.seek(val_start)
                fout.write(fin.read(val_end - val_start))

            # Tensor infos — compute new offsets with Q8_0 sizes
            new_offsets = []
            current_offset = 0
            for t in tensor_infos:
                n_elements = 1
                for d in t['dims']:
                    n_elements *= d

                if t['name'] in tensors_to_quantize:
                    new_type = GGML_Q8_0
                    bs, bb = TYPE_INFO[GGML_Q8_0]
                    new_size = (n_elements // bs) * bb
                else:
                    new_type = t['type']
                    if t['type'] in TYPE_INFO:
                        bs, bb = TYPE_INFO[t['type']]
                        new_size = (n_elements // bs) * bb
                    else:
                        # Unknown type, keep original size
                        bs, bb = TYPE_INFO.get(t['type'], (1, 4))
                        new_size = (n_elements // bs) * bb

                # Align offset to 32 bytes
                current_offset = (current_offset + 31) & ~31

                new_offsets.append((current_offset, new_type, new_size))
                current_offset += new_size

                write_string(fout, t['name'])
                write_u32(fout, t['n_dims'])
                for d in t['dims']:
                    write_u64(fout, d)
                write_u32(fout, new_type)
                write_u64(fout, new_offsets[-1][0])

            # Pad to alignment
            pos = fout.tell()
            pad = ((pos + alignment - 1) & ~(alignment - 1)) - pos
            fout.write(b'\x00' * pad)
            out_tensor_data_start = fout.tell()

            # --- Write tensor data ---
            for i, t in enumerate(tensor_infos):
                name = t['name'].decode('utf-8', errors='replace')
                new_offset, new_type, new_size = new_offsets[i]

                # Pad to alignment
                pos = fout.tell() - out_tensor_data_start
                target = new_offset
                if target > pos:
                    fout.write(b'\x00' * (target - pos))

                n_elements = 1
                for d in t['dims']:
                    n_elements *= d

                # Seek to original tensor data
                fin.seek(tensor_data_start + t['offset'])

                if t['name'] in tensors_to_quantize:
                    # Read FP32 and quantize to Q8_0
                    raw = fin.read(n_elements * 4)
                    floats = list(struct.unpack(f'<{n_elements}f', raw))

                    n_blocks = n_elements // BLOCK_SIZE
                    for b in range(n_blocks):
                        block_floats = floats[b * BLOCK_SIZE:(b + 1) * BLOCK_SIZE]
                        fout.write(quantize_block_q8_0(block_floats))

                    pct = (i + 1) * 100 // n_tensors
                    print(f"  [{pct:3d}%] Q8_0: {name} ({n_elements} elements)")
                else:
                    # Copy verbatim
                    if t['type'] in TYPE_INFO:
                        bs, bb = TYPE_INFO[t['type']]
                        orig_size = (n_elements // bs) * bb
                    else:
                        orig_size = n_elements * 4
                    data = fin.read(orig_size)
                    fout.write(data)

    out_size = os.path.getsize(out_path)
    ratio = out_size / in_size * 100
    print(f"\nDone: {in_size / 1024 / 1024:.1f} MB → {out_size / 1024 / 1024:.1f} MB ({ratio:.1f}%)")


if __name__ == '__main__':
    main()
