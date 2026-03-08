#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting wimg local dev..."
echo "  Sync API: http://localhost:8787"
echo "  Web app:  http://localhost:5173"
echo ""

# Start sync worker in background (--ip 0.0.0.0 for LAN access from phone)
(cd "$ROOT/wimg-sync" && bunx wrangler dev --ip 0.0.0.0) &
SYNC_PID=$!

# Start web dev server in background
(cd "$ROOT/wimg-web" && bun run dev --host) &
WEB_PID=$!

# Cleanup both on exit
trap "kill $SYNC_PID $WEB_PID 2>/dev/null" EXIT

wait
