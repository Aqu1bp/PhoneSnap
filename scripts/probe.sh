#!/usr/bin/env bash
# Probe ScreenshotCatch with a series of curl tests.
# Requires: app already running (`swift run` in another terminal).
# Usage: ./scripts/probe.sh [host:port]
set -euo pipefail

HOSTPORT="${1:-127.0.0.1:8472}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLE="$DIR/sample.png"

if [ ! -f "$SAMPLE" ]; then
  echo "Generating sample.png…"
  "$DIR/make-sample.sh" "$SAMPLE"
fi

echo
echo "── P1: raw PNG body ─────────────────────────────────────"
curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  -X POST -H "Content-Type: image/png" \
  --data-binary "@$SAMPLE" \
  "http://$HOSTPORT/screenshot"

sleep 1.5

echo
echo "── P2: multipart/form-data (matches iOS Shortcut) ───────"
curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  -X POST -F "file=@$SAMPLE;type=image/png" \
  "http://$HOSTPORT/screenshot"

sleep 1.5

echo
echo "── P4: bad payload (not an image) ───────────────────────"
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST --data "definitely not an image" \
  "http://$HOSTPORT/screenshot"

echo
echo "── P5: wrong path ───────────────────────────────────────"
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST "http://$HOSTPORT/nope"

echo
echo "── P6: GET on /screenshot ───────────────────────────────"
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "http://$HOSTPORT/screenshot"

echo
echo "Done. Check ~/Desktop/ScreenshotCatch/ for saved files."
ls -lt "$HOME/Desktop/ScreenshotCatch/" 2>/dev/null | head -5 || true
