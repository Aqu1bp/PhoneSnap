# ARCHITECTURE — ScreenshotCatch (Mac side)

## Process model
Single Swift process. Runs as a menu bar app (`LSUIElement = true`), no Dock icon, no main window on launch.

```
NSApplication (main thread)
├── AppDelegate           — app lifecycle
├── StatusItemController  — menu bar icon + menu
├── HTTPListener          — Network.framework NWListener on port 8472
│   └── HTTPConnection*   — one per inbound TCP, parses HTTP, emits ReceivedImage
├── ImageStore            — saves received PNGs to ~/Desktop/ScreenshotCatch/
└── ThumbnailPresenter    — shows/hides bottom-right NSPanel
    └── ThumbnailWindowController × N (typically 1)
```

## Networking
- Listener: `NWListener(using: .tcp, on: .init(rawValue: 8472)!)`.
- For each accepted `NWConnection`, spawn `HTTPConnection` which:
  1. Reads from socket until headers complete (`\r\n\r\n`).
  2. Parses request line + headers. Rejects anything not `POST /screenshot` (responds 404 to other paths, 405 to other methods on `/screenshot`).
  3. Reads `Content-Length` bytes (cap 32 MB; reject larger with 413).
  4. Decodes the body to a `Data` containing PNG/JPEG bytes:
     - If `Content-Type` starts with `image/`, body is the image directly.
     - If `Content-Type` is `multipart/form-data`, parse the boundary, find the first part with `Content-Type: image/*`, return its body.
     - Else fallback: scan body for `89 50 4E 47 0D 0A 1A 0A` (PNG signature) and slice from there to the `IEND` chunk; if not PNG, scan for `FF D8 FF` (JPEG SOI) and slice to `FF D9` (JPEG EOI).
  5. Posts `ReceivedImage(data:Data, suggestedName:String)` on the main queue.
  6. Writes a small `200 OK` JSON response with the saved filename, then closes.

## Image handling
- `ImageStore.save(_ data: Data) -> URL`:
  - Folder = `~/Desktop/ScreenshotCatch/` (created lazily, with `~/Pictures/ScreenshotCatch/` as a future option).
  - Filename = `Screenshot YYYY-MM-DD at HH.MM.SS.png` (matches macOS native naming).
  - Returns the file URL.
- Copy to pasteboard immediately:
  ```swift
  NSPasteboard.general.clearContents()
  NSPasteboard.general.writeObjects([NSImage(data: data) ?? NSImage()])
  // also write the file URL for paste-as-file in Finder/Notes
  ```
- Drag provider: in the thumbnail view, override `mouseDown` to begin a dragging session with `NSDraggingItem(pasteboardWriter: fileURL as NSURL)`.

## UI
### ThumbnailWindowController
- Window type: `NSPanel`.
- Style mask: `.borderless, .nonactivatingPanel, .utilityWindow`.
- Backing: `.buffered`.
- Level: `.floating` (`NSWindow.Level.floating`).
- `collectionBehavior`: `[.canJoinAllSpaces, .stationary, .ignoresCycle]`.
- `isMovableByWindowBackground = true`.
- Size: image scaled to `maxHeight = 220pt`, with 12pt padding around. Capped width = 320pt.
- Position: bottom-right of the screen containing the mouse pointer (or main screen if no mouse), 20pt inset from the bottom and right edges.
- Visual: rounded 12pt corner radius; white background in light mode, `NSVisualEffectView` chrome-style underlay; subtle drop shadow.
- Content:
  - Top-right tiny close (✕) button (revealed on hover).
  - Image view (centered).
  - Bottom strip on hover: "Copy", "Save to Desktop", "Open" — shown via tracking area.
- Auto-fade: timer 8.0s, fade-out 0.2s. Hovering resets the timer.
- Keyboard: ESC closes; ⌘C copies; ⌘S re-saves with a save panel.

### StatusItemController
- `NSStatusItem` with template image (a small camera icon).
- Menu:
  - "Listening on http://&lt;ip&gt;:8472" (disabled, info)
  - Separator
  - "Show Last Screenshot" — re-presents last thumbnail
  - "Reveal Save Folder in Finder"
  - "Copy Server URL"
  - Separator
  - "Quit ScreenshotCatch"

## Concurrency
- Network I/O on a dedicated `DispatchQueue(label: "screenshotcatch.net")`.
- UI presentation strictly on `MainActor`.
- ImageStore disk writes on a dedicated `DispatchQueue(label: "screenshotcatch.io", qos: .utility)`.
- Crossing back to main with `DispatchQueue.main.async { ... }` after disk write.

## Bundling
SwiftPM builds an executable; we generate a minimal `.app` wrapper at the project root (`ScreenshotCatch.app/Contents/MacOS/ScreenshotCatch` + `Info.plist` with `LSUIElement=YES`). A `scripts/build.sh` produces it. For MVP testing the raw binary works too — `swift run` will also launch.

## Configuration
- Port read from env `SCREENSHOTCATCH_PORT`, default 8472.
- Save folder read from env `SCREENSHOTCATCH_DIR`, default `~/Desktop/ScreenshotCatch/`.

## Failure modes & telemetry
- Logs to stderr with a `[ScreenshotCatch]` prefix.
- On port-in-use: print clear error and exit non-zero.
- On parse failure: log first 256 bytes of body in hex; return 400.
- On image decode failure: log + 415 to client; no panel shown.

## iOS Shortcut spec (for parity)
- Name: `Send Screenshot to Mac`
- Accepts input: `Images` (so it shows in the screenshot Share Sheet).
- Actions:
  1. `Get Latest Screenshots` (Count = 1). Used when run via Back Tap / Action Button / Spotlight. When run from share sheet, Shortcut Input is already an image, so this action is skipped in that branch via an `If` conditional checking for Shortcut Input.
  2. `Get Contents of URL`:
     - URL: `http://<mac-ip>:8472/screenshot`
     - Method: POST
     - Request Body: Form
     - Field: `file` (type: File) = the screenshot variable
3. Optional: `Show Notification "Sent to Mac"` on success.

We will provide a copy-pasteable description and a step-by-step setup; we cannot generate `.shortcut` files programmatically from a Mac script.
