# TEST_PLAN

## Unit-ish / local probes (no iPhone needed)

These verify the Mac app end-to-end without depending on the iPhone, per the project's "probe-driven debug" principle.

### P1 — `curl` raw PNG body
```
curl -v -X POST \
  --data-binary @/System/Library/Desktop\ Pictures/Sequoia.heic \
  -H "Content-Type: image/png" \
  http://127.0.0.1:8472/screenshot
```
Expect: HTTP 200 with JSON body. Thumbnail appears bottom-right. File saved in `~/Desktop/ScreenshotCatch/`.

### P2 — `curl` multipart upload (matches iOS Shortcut payload)
```
curl -v -X POST \
  -F "file=@scripts/sample.png;type=image/png" \
  http://127.0.0.1:8472/screenshot
```
Expect: HTTP 200, thumbnail appears, file saved.

### P3 — `curl` from another LAN device
```
curl -X POST -F "file=@some.png" http://<mac-lan-ip>:8472/screenshot
```
Expect: same as P2.

### P4 — Bad payload (not an image)
```
curl -X POST --data "hello" http://127.0.0.1:8472/screenshot
```
Expect: HTTP 415 + log line about decode failure. No panel.

### P5 — Wrong path
```
curl -X POST http://127.0.0.1:8472/whatever
```
Expect: HTTP 404.

### P6 — GET on /screenshot
```
curl http://127.0.0.1:8472/screenshot
```
Expect: HTTP 405.

### P7 — Big body (>32MB)
```
dd if=/dev/zero bs=1m count=40 | curl -X POST --data-binary @- http://127.0.0.1:8472/screenshot
```
Expect: HTTP 413; no crash.

### P8 — Concurrent uploads
```
for i in 1 2 3; do curl -X POST -F "file=@scripts/sample.png" http://127.0.0.1:8472/screenshot & done; wait
```
Expect: 3 panels, or 3 sequential pop-ins; no crash.

### P9 — Thumbnail UI checks
With panel visible:
- Hover → buttons fade in.
- Click image → opens in Preview.
- Drag from image → file transferred to Finder.
- Press ESC → panel closes.
- Wait 8s without hover → panel auto-fades.
- Hover during the 8s window → timer resets.

### P10 — Clipboard
After P1: open TextEdit → ⌘V → image pastes.

### P11 — Status bar
- Menu lists current IP.
- "Reveal Save Folder" opens Finder.
- "Quit" terminates cleanly.

## End-to-end (iPhone → Mac)

### E1 — Manual Shortcut run
1. Build & run Mac app.
2. On iPhone, open the configured Shortcut, tap Play.
3. iPhone prompts for Local Network the first time → Allow.
4. Wait. Thumbnail appears on Mac.

### E2 — Back Tap trigger
1. Take any screenshot.
2. Double-tap back of iPhone.
3. Thumbnail appears on Mac (<2s on LAN).

### E3 — Share Sheet trigger
1. Take screenshot.
2. Tap the bottom-left preview thumbnail.
3. Share → pick "Send Screenshot to Mac".
4. Thumbnail appears on Mac.

### E4 — Action Button (iPhone 15 Pro+)
1. Press Action Button.
2. Thumbnail appears.

### E5 — Drag into Claude Code / Cursor / Slack
1. Trigger E2.
2. While thumbnail visible, drag image into Claude Code's prompt input.
3. The image attaches.

## Build / typecheck / lint

```
cd /path/to/PhoneSnap
swift build -c release
swift build      # debug
```

No external test framework for MVP (no XCTest target — kept lean). Manual probes are the validation surface.

## Definition of done

- All P1–P11 probes pass locally with curl.
- E1 documented; we cannot autotest from iPhone but the docs walk the user through it.
- README has run command, iPhone setup, Mac setup, debug guide.
- Code compiles with `swift build` at warning-clean level for our code (Apple framework deprecations excepted).
