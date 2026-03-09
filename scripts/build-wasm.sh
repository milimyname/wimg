#!/bin/bash
set -euo pipefail

# Build libwimg for WASM — two variants:
#   1. Web app (normal buffers: 64MB FBA + 32MB VFS + 16MB heap)
#   2. MCP server (compact: 16MB FBA + 8MB VFS + 4MB heap — fits CF Workers 128MB)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/libwimg"

echo "=== Building libwimg.wasm (web) ==="
zig build --release=small
cp zig-out/bin/libwimg.wasm "$ROOT/wimg-web/static/libwimg.wasm"
echo "=== Copied to wimg-web/static/libwimg.wasm ==="
ls -lh "$ROOT/wimg-web/static/libwimg.wasm"

echo "=== Building libwimg.wasm (compact/MCP) ==="
zig build --release=small -Dcompact=true
cp zig-out/bin/libwimg.wasm "$ROOT/wimg-sync/libwimg-compact.wasm"
echo "=== Copied to wimg-sync/libwimg-compact.wasm ==="
ls -lh "$ROOT/wimg-sync/libwimg-compact.wasm"
