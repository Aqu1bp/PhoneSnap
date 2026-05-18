# ScreenshotCatch

Mirror the iOS Simulator screenshot thumbnail experience for screenshots you take on a **real iPhone**.

Take a screenshot on iPhone → a floating thumbnail pops in the bottom-right corner of your Mac. Drag it directly into Claude Code / Cursor / Slack / Notes, or hit **Copy** and ⌘V anywhere.

Two delivery paths, both built in, run in parallel, dedupe automatically:

| Path | When | Setup | Latency |
|------|------|-------|---------|
| **Cable** | iPhone plugged into Mac | Zero. Just plug in. | ~1s |
| **Wireless** | iPhone unplugged, same Wi-Fi | Scan a QR code once | ~1s after a single trigger gesture |

- 100% Apple-supported APIs, no third-party services, no paid developer account, no iCloud requirement
- Mac side is a ~300 KB SwiftPM binary; runs as a menu bar app

## Why this exists

When you take a screenshot in the iOS Simulator on Mac, a thumbnail appears bottom-right that you can drag into any app. There is no equivalent for real iPhones. ScreenshotCatch builds that bridge so you can hand screenshots to AI coding agents without losing the context switch.

## Requirements

- macOS 13+ (built on 26 Tahoe)
- Swift 5.9+ / Xcode 15+ (only needed to build; no Apple Developer Program account required)
- An iPhone on iOS 14+

## Quick start

```bash
git clone <this repo>
cd ScreenshotCatch
./scripts/build-app.sh
open ./ScreenshotCatch.app
```

A small camera icon appears in the menu bar. The app is running.

### Cable path (zero iPhone setup)

Plug your iPhone into the Mac with a Lightning / USB-C cable. The first time, tap **"Trust this computer"** on the iPhone. That's it — take a screenshot, and a thumbnail appears bottom-right on the Mac within ~1 second. No Shortcut, no Back Tap, no settings to configure on iPhone.

This works because macOS treats a plugged-in iPhone as a camera-class device, and `ImageCaptureCore` delivers a real-time notification for every new asset added to the camera roll. ScreenshotCatch filters those down to screenshots (by aspect ratio + dimensions) and shows the thumbnail.

### Wireless path (scan a QR once)

For when the iPhone isn't plugged in:

1. Click the menu bar icon → **"Pair iPhone…"** (or hit ⌘P with the menu open).
2. A window opens with a QR code.
3. Open Camera on iPhone, point at the QR, tap the Safari notification.
4. Tap **Add Shortcut**. (No "Allow Untrusted Shortcuts" prompt — the Shortcut is properly signed via `shortcuts sign --mode anyone`, the same trust scope Apple uses for iCloud-shared Shortcuts.)
5. The imported Shortcut already has your Mac's URL baked in. Test it: tap it once in Shortcuts.app. A screenshot should arrive on your Mac.
6. **Bind it to a trigger** so you don't have to open Shortcuts each time — pick whichever fits your hardware: AssistiveTouch single-tap (any iPhone, most reliable), Action Button (15 Pro/16, hardware-reliable), Back Tap (any iPhone but accelerometer-flaky), or Share Sheet. See [`docs/IPHONE_SETUP.md`](docs/IPHONE_SETUP.md) for one-line settings paths.

Total wireless setup time: ~30 seconds. Zero typing.

### Local probe (no iPhone needed)

```bash
./scripts/probe.sh    # POSTs sample PNGs via curl; thumbnails pop bottom-right
```

## Thumbnail behavior (matches the iOS Simulator)

- Appears bottom-right of the screen containing the cursor, with a fade-in.
- **Auto-copied** to the clipboard on arrival — paste with ⌘V immediately if you don't even want to touch the thumbnail.
- **Hover** to reveal the action bar: **Copy**, **Save…**, **Open**.
- **Click** the image to open in Preview.
- **Drag** the image directly into Claude Code / Cursor / Slack / Mail / any drop target.
- **ESC** or click the **✕** (top-right) to dismiss immediately.
- Auto-fades after 8 s; hovering resets the timer.
- ⌘C inside the thumbnail copies; ⌘S opens a save panel.

## Where screenshots are saved

By default: `~/Pictures/ScreenshotCatch/Screenshot YYYY-MM-DD at HH.MM.SS.png`

Override with an env var when launching:
```bash
SCREENSHOTCATCH_DIR=~/Desktop/screenshots open ./ScreenshotCatch.app
```

## Run commands

| Goal | Command |
|------|---------|
| Build + launch (recommended) | `./scripts/build-app.sh && open ./ScreenshotCatch.app` |
| Run from source with logs to terminal | `swift run ScreenshotCatch` |
| Run the prebuilt debug binary | `.build/debug/ScreenshotCatch` |
| Stop the server | Menu bar item → Quit, or `pkill -f ScreenshotCatch` |
| Run all local probes | `./scripts/probe.sh` (with server running) |
| Change port | `SCREENSHOTCATCH_PORT=9090 open ./ScreenshotCatch.app` |
| Change save folder | `SCREENSHOTCATCH_DIR=~/wherever open ./ScreenshotCatch.app` |

## How it works

```
┌─────────────────────┐                     ┌───────────────────────────────┐
│  iPhone             │   HTTP POST         │  Mac (ScreenshotCatch.app)    │
│                     │   multipart/        │                               │
│  Shortcut:          │   form-data         │  NWListener :8472             │
│  Get Latest         │  ────────────────►  │  parses request               │
│  Screenshots → POST │                     │  saves PNG → ~/Pictures/...   │
│                     │                     │  writes PNG to NSPasteboard   │
│  Trigger:           │                     │  shows borderless NSPanel     │
│  Back Tap /         │                     │  bottom-right, drag/copy/etc │
│  Action Button /    │                     │                               │
│  Share Sheet        │                     │                               │
└─────────────────────┘                     └───────────────────────────────┘
```

Mac side is one Swift target, ~1000 LOC, no dependencies.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the internals.

## Why this approach (and not iCloud, AirDrop, …)

Long version in [docs/RESEARCH.md](docs/RESEARCH.md). The short version:

- **iOS has no "screenshot taken" automation trigger** — fully-automatic shortcuts can't watch for screenshots. The closest thing is *one tap* via Back Tap, Action Button, or Share Sheet.
- **iCloud Photos sync** is 5–60s latency, often more. Kills the "instant" feel.
- **AirDrop** is manual and not automatable.
- **Universal Clipboard** clobbers your existing clipboard.
- A small **LAN HTTP server + Shortcut** is the only path that's fast (<1s typical), reliable, free, and doesn't require sideloading a custom iOS app.

## Debugging

| Symptom | Where to look |
|---------|--------------|
| Nothing happens when I trigger the shortcut | Open Shortcuts → run it manually. If that fails too, see iOS-side issues in [docs/IPHONE_SETUP.md](docs/IPHONE_SETUP.md) |
| Shortcut runs, no thumbnail on Mac | `swift run ScreenshotCatch` in a terminal — every received request prints `Saved … N bytes`. If nothing prints, the request never reached Mac (check URL, same Wi-Fi, AP isolation, port conflicts) |
| App doesn't launch | `./scripts/build-app.sh` to rebuild; check `lsof -i :8472` to see if another process holds the port |
| Pasteboard paste produces only text or fails | The new version writes `public.png` + `public.tiff` + `public.file-url` — verify with `swift /tmp/pbtypes.swift` (see the in-repo helper) |
| Wrong Mac IP in shortcut after switching networks | Click menu bar item to see the current URL; edit the Shortcut |
| Multiple devices on LAN need access | Each iPhone needs its own Shortcut with the Mac's URL; the Mac accepts from anyone on the LAN (port 8472, no auth — see "Limitations" below) |

Live tail of the running server's stderr:
```bash
# If running from terminal: log is on stderr already.
# If running .app: redirect on launch:
./ScreenshotCatch.app/Contents/MacOS/ScreenshotCatch 2>&1 | tee /tmp/scrcatch.log
```

## Known limitations

- **One gesture, not zero.** iOS does not expose a "screenshot taken" automation trigger, so a 100% automatic flow is technically impossible without a sideloaded custom iOS app — which itself only fires while it's the foreground app, which defeats the purpose. Back Tap is the closest practical solution (one gesture after the screenshot).
- **LAN only.** Both devices must be on the same network with peer-to-peer reachability. AP isolation on guest Wi-Fi will block it.
- **No authentication on the server.** Anyone on your LAN who knows the port can POST a screenshot. Acceptable on home/personal networks; future work to add a shared-secret header.
- **Manual IP entry.** The Shortcut hardcodes the Mac's IP or `.local` name. Bonjour autodiscovery + an iOS helper app is a follow-up.
- **One thumbnail at a time.** A new screenshot dismisses the old thumbnail rather than stacking.
- **HEIC vs PNG.** iOS screenshots are PNG, so this is a non-issue today, but other image formats are normalized to PNG on the Mac via `NSBitmapImageRep`.
- **No app sandbox / no notarization.** First launch via `open` may show Gatekeeper warning; right-click → Open the first time, or `xattr -d com.apple.quarantine ScreenshotCatch.app`.

## What remains for future polish

- Bonjour auto-advertising and an iOS helper to autoconfigure the Shortcut URL.
- Shared-secret token (or Touch ID prompt for first-time pairing).
- Stacked thumbnails for multiple in-flight screenshots.
- Animated bounce-in matching the simulator exactly.
- Receive screen-recording videos and not just screenshots.
- Login Item registration so the app starts on boot.
- Touch up the bottom action bar with hover-highlight state on each pill.

## Project layout

```
ScreenshotCatch/
├── docs/                          research, options, architecture, tests, iPhone setup
│   ├── RESEARCH.md
│   ├── OPTIONS_COMPARISON.md
│   ├── CHOSEN_APPROACH.md
│   ├── ARCHITECTURE.md
│   ├── TEST_PLAN.md
│   └── IPHONE_SETUP.md
├── Sources/ScreenshotCatch/       Swift sources (~10 files, ~1000 LOC)
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── HTTPListener.swift         NWListener + minimal HTTP/1.1 server
│   ├── ImageStore.swift           save received bytes as PNG
│   ├── Pasteboard.swift           multi-type clipboard write
│   ├── LANAddress.swift           getifaddrs() for current LAN IP
│   ├── StatusItemController.swift menu bar item
│   ├── ThumbnailPresenter.swift   wires received image → window
│   ├── ThumbnailWindowController  borderless floating NSPanel
│   ├── ThumbnailView.swift        rounded image + hover actions
│   └── Log.swift                  stderr logging
├── scripts/
│   ├── build-app.sh               wraps the SwiftPM binary into ScreenshotCatch.app
│   ├── probe.sh                   curl-based local tests
│   └── make-sample.sh             generate a sample PNG from a system wallpaper
├── Package.swift
└── README.md
```

## License

Personal project, no license declared. Treat as MIT-equivalent for your own use.
