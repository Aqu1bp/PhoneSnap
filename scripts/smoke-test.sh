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
READY=0
for _ in $(seq 1 30); do
  sleep 0.5
  PAIR=$(HOME="$HOME" defaults read PhoneSnap PhoneSnapWirelessPairID 2>/dev/null || true)
  if [ -n "$PAIR" ] && curl -s -m 5 -o /dev/null "http://127.0.0.1:$PORT/pair/$PAIR"; then
    READY=1
    break
  fi
done
if [ "$READY" != "1" ]; then
  echo "receiver never came up; app log:"
  cat "$DIR/app.log"
  exit 1
fi
TOKEN=$(HOME="$HOME" defaults read PhoneSnap PhoneSnapWirelessToken)
BASE="http://127.0.0.1:$PORT"

# 1x1 transparent PNG for upload checks.
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' \
  | base64 -d > "$DIR/px.png"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl+XgAAAABJRU5ErkJggg==' \
  | base64 -d > "$DIR/red.png"

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

check_raw() {
  local desc="$1" want="$2" request="$3"
  local got
  got=$(printf '%b' "$request" | nc -w 3 127.0.0.1 "$PORT" | head -n 1 | awk '{print $2}')
  if [ "$got" = "$want" ]; then
    echo "ok   $want $desc"
  else
    echo "FAIL want $want got ${got:-<none>} — $desc"
    fail=1
  fi
}

check_header() {
  local desc="$1" want="$2"; shift 2
  local headers
  headers=$(curl -s -m 10 -D - -o /dev/null "$@" | tr -d '\r')
  if printf '%s\n' "$headers" | grep -Fqi "$want"; then
    echo "ok   header $desc"
  else
    echo "FAIL missing response header '$want' — $desc"
    fail=1
  fi
}

check "setup page"                200 "$BASE/pair/$PAIR"
check "unknown pair ID"           404 "$BASE/pair/not-a-real-pair-id"
check "upload without token"      401 -X POST --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "upload with wrong token"   401 -X POST -H "Authorization: Bearer wrong-token" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "upload with valid token"   200 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "lowercase bearer scheme"    200 -X POST -H "Authorization: bearer $TOKEN" -H "Content-Type: image/png" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "multipart image upload"    200 -X POST -H "Authorization: Bearer $TOKEN" -F "file=@$DIR/px.png;type=image/png" "$BASE/api/v1/upload/$PAIR"
check "Expect 100-continue"        200 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" -H "Expect: 100-continue" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "chunked rejected"          501 -X POST -H "Authorization: Bearer $TOKEN" -H "Transfer-Encoding: chunked" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "non-image rejected after decode" 415 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" --data-binary "definitely not an image" "$BASE/api/v1/upload/$PAIR"
check "authenticated empty body"  400 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" -H "Content-Length: 0" "$BASE/api/v1/upload/$PAIR"
check "query token rejected"      401 -X POST -H "Content-Type: image/png" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR?token=$TOKEN"
check "malformed multipart"       415 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: multipart/form-data" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check "GET on upload route"       405 "$BASE/api/v1/upload/$PAIR"
check "unsupported Expect"        417 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: image/png" -H "Expect: something-else" --data-binary @"$DIR/px.png" "$BASE/api/v1/upload/$PAIR"
check_header "upload method advertises POST" "Allow: POST" "$BASE/api/v1/upload/$PAIR"
check_header "setup page disables caching" "Cache-Control: no-store" "$BASE/pair/$PAIR"
check_header "setup page disables referrers" "Referrer-Policy: no-referrer" "$BASE/pair/$PAIR"

AUTH_HEADER="Authorization: Bearer $TOKEN"
UPLOAD_PATH="/api/v1/upload/$PAIR"
check_raw "missing Content-Length" 411 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\n$AUTH_HEADER\r\nContent-Type: image/png\r\nConnection: close\r\n\r\n"
check_raw "invalid Content-Length" 400 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\n$AUTH_HEADER\r\nContent-Type: image/png\r\nContent-Length: abc\r\nConnection: close\r\n\r\n"
check_raw "negative Content-Length" 400 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\n$AUTH_HEADER\r\nContent-Type: image/png\r\nContent-Length: -1\r\nConnection: close\r\n\r\n"
check_raw "duplicate Content-Length" 400 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\n$AUTH_HEADER\r\nContent-Type: image/png\r\nContent-Length: 1\r\nContent-Length: 1\r\nConnection: close\r\n\r\nX"
check_raw "declared body above limit" 413 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\n$AUTH_HEADER\r\nContent-Type: image/png\r\nContent-Length: 33554433\r\nConnection: close\r\n\r\n"
check_raw "unauthorized body rejected before buffering" 401 "POST $UPLOAD_PATH HTTP/1.1\r\nHost: 127.0.0.1:$PORT\r\nContent-Type: image/png\r\nContent-Length: 33554432\r\nConnection: close\r\n\r\n"

OVERSIZED_HEADER_STATUS=$(
  {
    printf 'GET /pair/%s HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nX-Fill: ' "$PAIR" "$PORT"
    awk 'BEGIN { for (i = 0; i < 65536; i++) printf "a" }'
    printf '\r\n\r\n'
  } | nc -w 3 127.0.0.1 "$PORT" | head -n 1 | awk '{print $2}'
)
if [ "$OVERSIZED_HEADER_STATUS" = "431" ]; then
  echo "ok   431 oversized request headers"
else
  echo "FAIL want 431 got ${OVERSIZED_HEADER_STATUS:-<none>} — oversized request headers"
  fail=1
fi

EXPECT_TRACE=$(curl -sS -m 10 -o /dev/null -v -X POST \
  -H "$AUTH_HEADER" -H "Content-Type: image/png" -H "Expect: 100-continue" \
  --data-binary @"$DIR/px.png" "$BASE$UPLOAD_PATH" 2>&1)
if printf '%s\n' "$EXPECT_TRACE" | grep -Fq '< HTTP/1.1 100 Continue'; then
  echo "ok   interim 100 Continue is sent before the upload body"
else
  echo "FAIL receiver did not emit an interim 100 Continue response"
  fail=1
fi

SLOW_HEADER_STATUS=$(
  {
    printf 'GET /pair/%s HTTP/1.1\r\nHost: 127.0.0.1:%s\r\n' "$PAIR" "$PORT"
    sleep 6
  } | nc -w 8 127.0.0.1 "$PORT" | head -n 1 | awk '{print $2}'
)
if [ "$SLOW_HEADER_STATUS" = "408" ]; then
  echo "ok   408 incomplete headers time out"
else
  echo "FAIL want 408 got ${SLOW_HEADER_STATUS:-<none>} — incomplete headers time out"
  fail=1
fi

HOSTILE_STATUS=$(curl -s -m 10 -o "$DIR/hostile.html" -w '%{http_code}' \
  -H "Host: attacker.example:$PORT" "$BASE/pair/$PAIR")
if [ "$HOSTILE_STATUS" != "200" ]; then
  echo "FAIL want 200 got ${HOSTILE_STATUS:-<none>} — setup page with untrusted Host header"
  fail=1
elif grep -Fq "attacker.example" "$DIR/hostile.html"; then
  echo "FAIL setup page reflected an untrusted Host header"
  fail=1
else
  echo "ok   setup page rejects untrusted Host headers"
fi

check "distinct sequential image" 200 -X POST -H "$AUTH_HEADER" \
  -H "Content-Type: image/png" --data-binary @"$DIR/red.png" "$BASE$UPLOAD_PATH"

JSON=$(curl -s -m 10 -X POST -H "$AUTH_HEADER" -H "Content-Type: image/png" --data-binary @"$DIR/px.png" "$BASE$UPLOAD_PATH")
PNG_BYTES=$(wc -c < "$DIR/px.png" | tr -d ' ')
if [ "$JSON" = "{\"ok\":true,\"bytes\":$PNG_BYTES}" ]; then
  echo "ok   success JSON reports accepted byte count"
else
  echo "FAIL unexpected success JSON: $JSON"
  fail=1
fi

SAVED_COUNT=$(find "$DIR/snaps" -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
if [ "$SAVED_COUNT" = "2" ]; then
  echo "ok   duplicate uploads deduplicated while a distinct image was saved"
else
  echo "FAIL expected two normalized files, found $SAVED_COUNT"
  fail=1
fi

SAVED_FILE=$(find "$DIR/snaps" -type f -name '*.png' -print -quit 2>/dev/null)
SAVED_SIGNATURE=$(od -An -tx1 -N8 "$SAVED_FILE" 2>/dev/null | tr -d ' \n')
if [ "$SAVED_SIGNATURE" = "89504e470d0a1a0a" ]; then
  echo "ok   saved output has a PNG signature"
else
  echo "FAIL saved output is not a PNG"
  fail=1
fi

if grep -Fq "$PAIR" "$DIR/app.log" || grep -Fq "$TOKEN" "$DIR/app.log"; then
  echo "FAIL pairing material appeared in application logs"
  fail=1
else
  echo "ok   application logs redact pairing material"
fi

exit $fail
