#!/bin/bash
set -euo pipefail

# Build libwimg for WASM and copy to wimg-web/static
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Building libwimg.wasm ==="
cd "$ROOT/libwimg"
zig build --release=small

cp zig-out/bin/libwimg.wasm "$ROOT/wimg-web/static/libwimg.wasm"
echo "=== Copied to wimg-web/static/libwimg.wasm ==="
ls -lh "$ROOT/wimg-web/static/libwimg.wasm"
