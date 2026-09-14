#!/bin/bash
# Thin wrapper to run td-ax-dump.applescript and save output.
# Usage: ./td-ax-dump.sh [output-file]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="${1:-$SCRIPT_DIR/td-ax-dump.txt}"

osascript "$SCRIPT_DIR/td-ax-dump.applescript" > "$OUT_FILE" 2>&1
echo "Wrote dump to $OUT_FILE"
echo "--- Preview ---"
head -n 40 "$OUT_FILE"
