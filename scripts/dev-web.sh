#!/bin/bash
set -euo pipefail

# Start wimg-web dev server
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/wimg-web"
bun run dev
