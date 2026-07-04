#!/usr/bin/env bash
# End-to-end smoke test for the wireless receiver.
# Expects .build/debug/PhoneSnap to exist (run `swift build` first).
# Used by CI and runnable locally: ./scripts/smoke-test.sh
#
# The Shortcut download route is intentionally not asserted here:
# /usr/bin/shortcuts signing is not reliable on CI runners, and its
# failure path is already a handled 500 in the app.
set -uo pipefail

cd "$(dirname "$0")/.."

PORT="${PHONESNAP_SMOKE_PORT:-18472}"
DIR="$(mktemp -d)"
BIN=".build/debug/PhoneSnap"
[ -x "$BIN" ] || { echo "missing $BIN — run swift build first"; exit 1; }

cleanup() {
  if [ -n "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$DIR"
}
trap cleanup EXIT

export HOME="$DIR/home"
mkdir -p "$HOME"

PHONESNAP_WIRELESS_PORT="$PORT" PHONESNAP_DIR="$DIR/snaps" "$BIN" > "$DIR/app.log" 2>&1 &
APP_PID=$!

# Wait for the receiver to come up and the pairing values to persist.
PAIR=""
for _ in $(seq 1 30); do
  sleep 0.5
  PAIR=$(HOME="$HOME" defaults read PhoneSnap PhoneSnapWirelessPairID 2>/dev/null || true)
  if [ -n "$PAIR" ] && curl -s -m 5 -o /dev/null "http://127.0.0.1:$PORT/pair/$PAIR"; then
    break
  fi
done
if [ -z "$PAIR" ]; then
  echo "receiver never came up; app log:"
  cat "$DIR/app.log"
  exit 1
fi
TOKEN=$(HOME="$HOME" defaults read PhoneSnap PhoneSnapWirelessToken)
BASE="http://127.0.0.1:$PORT"

# 1x1 transparent PNG for upload checks.
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' \
  | base64 -d > "$DIR/px.png"

fail=0
check() {
  local desc="$1" want="$2"; shift 2
  local got
  got=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ]; then
    echo "ok   $want $desc"
  else
    echo "FAIL want $want got $got — $desc"
    fail=1
  fi
}

check "setup page"                200 "$BASE/pair/$PAIR"
check "unknown pair ID"           404 "$BASE/pair/not-a-real-pair-id"
check "upload without token"      401 -X POST --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "upload with wrong token"   401 -X POST -H "Authorization: Bearer wrong-token" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "upload with valid token"   200 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "chunked rejected"          501 -X POST -H "Authorization: Bearer $TOKEN" -H "Transfer-Encoding: chunked" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "non-image rejected"        415 -X POST -H "Authorization: Bearer $TOKEN" --data-binary "definitely not an image" "$BASE/api/v1/upload/$PAIR"
check "GET on upload route"       405 "$BASE/api/v1/upload/$PAIR"

exit $fail
