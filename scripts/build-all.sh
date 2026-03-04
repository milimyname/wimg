#!/bin/bash
set -euo pipefail

# Full rebuild: WASM + iOS XCFramework + regenerate Xcode project
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==============================="
echo "  Step 1: Build WASM"
echo "==============================="
"$ROOT/scripts/build-wasm.sh"

echo ""
echo "==============================="
echo "  Step 2: Build iOS XCFramework"
echo "==============================="
"$ROOT/scripts/build-ios.sh"

echo ""
echo "==============================="
echo "  Step 3: Regenerate Xcode project"
echo "==============================="
"$ROOT/scripts/gen-xcodeproj.sh"

echo ""
echo "=== All done ==="
