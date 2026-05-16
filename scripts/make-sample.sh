#!/usr/bin/env bash
# Generates a sample PNG using the system's `sips` tool.
# Usage: ./scripts/make-sample.sh [out.png]
set -euo pipefail
OUT="${1:-scripts/sample.png}"
SRC="/System/Library/Desktop Pictures/Hello Metallic Blue.heic"
if [ ! -f "$SRC" ]; then
  # Pick any default wallpaper available.
  SRC="$(/bin/ls /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -n 1)"
fi
if [ -z "${SRC:-}" ] || [ ! -f "$SRC" ]; then
  echo "No source HEIC found; please supply your own PNG."
  exit 1
fi
sips -s format png "$SRC" --out "$OUT" --resampleHeightWidthMax 800 >/dev/null
echo "Wrote $OUT ($(stat -f%z "$OUT") bytes)"
