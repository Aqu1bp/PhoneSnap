# PhoneSnap

Mirror the iOS Simulator screenshot thumbnail experience for screenshots you take on a **real iPhone connected by cable**.

Take a screenshot on iPhone -> a floating thumbnail pops in the bottom-right corner of your Mac. Drag it directly into Claude Code, Cursor, Slack, Notes, or hit **Copy** and paste anywhere.

## Current Scope

PhoneSnap is now intentionally **wired-only**.

- Supported: iPhone connected to the Mac over USB, trusted by the Mac.
- Removed/deprecated: QR pairing, iOS Shortcuts, GitHub Gist rendezvous, and LAN HTTP upload.
- No third-party services, no paid developer account, no iCloud requirement.

The wireless path was removed because it was not reliable enough to present as a supported feature.

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+ to build
- iPhone or iPad that appears to macOS through ImageCaptureCore
- USB or USB-C cable

## Quick Start

```bash
git clone <this repo>
cd PhoneSnap
./scripts/build-app.sh
open ./PhoneSnap.app
```

A small iPhone icon appears in the menu bar. The app is running.

## Use It

1. Plug your iPhone into the Mac.
2. Unlock the iPhone.
3. If prompted, tap **Trust This Computer**.
4. Take a screenshot on the iPhone.
5. The Mac shows a floating thumbnail near the bottom-right of the current screen.

The app uses Apple's ImageCaptureCore framework. macOS exposes a trusted, plugged-in iPhone as a camera-class device; PhoneSnap watches for new camera-roll items after startup, filters likely screenshots, downloads them, saves them, copies them to the clipboard, and shows the thumbnail.

## Thumbnail Behavior

- Appears bottom-right of the screen containing the cursor, with a fade-in.
- Auto-copies the screenshot to the clipboard on arrival.
- Shows action buttons for copy, save, and open.
- Click the image to open it in Preview.
- Drag the image directly into Claude Code, Cursor, Slack, Mail, or any file drop target.
- Press ESC or click the close button to dismiss.
- Auto-fades after 8 seconds; hovering resets the timer.

## Where Screenshots Are Saved

By default:

```text
~/Pictures/PhoneSnap/Screenshot YYYY-MM-DD at HH.MM.SS.SSS.png
```

Override the folder when launching:

```bash
PHONESNAP_DIR=~/Desktop/screenshots open ./PhoneSnap.app
```

## Run Commands

| Goal | Command |
|------|---------|
| Build + launch | `./scripts/build-app.sh && open ./PhoneSnap.app` |
| Run from source with logs | `swift run PhoneSnap` |
| Run the debug binary | `.build/debug/PhoneSnap` |
| Stop the app | Menu bar item -> Quit, or `pkill -f PhoneSnap` |
| Change save folder | `PHONESNAP_DIR=~/wherever open ./PhoneSnap.app` |

## How It Works

```text
iPhone over USB
  screenshot saved to camera roll
    -> ImageCaptureCore didAdd callback
    -> PhoneSnap downloads the new item
    -> saves PNG to ~/Pictures/PhoneSnap
    -> writes PNG/TIFF/file URL to NSPasteboard
    -> shows a floating NSPanel thumbnail
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing appears after taking a screenshot | Unlock the iPhone, reconnect the cable, and accept **Trust This Computer** if prompted. |
| Old photos appear | Quit and reopen the app, then take a fresh screenshot. |
| Clipboard paste fails | Use the thumbnail copy button; if it still fails, run from terminal with `swift run PhoneSnap` and check logs. |
| App does not launch | Rebuild with `./scripts/build-app.sh`. |
| Thumbnail appears on the wrong display | Move the mouse to the target display before taking the screenshot. |

## Known Limitations

- Wired only. Wireless Shortcut/QR pairing was removed because it was unreliable.
- One thumbnail at a time. A new screenshot dismisses the old thumbnail.
- Screenshot detection uses dimensions/aspect-ratio heuristics to avoid importing normal camera photos.
- No app sandbox and no notarization. First launch may require right-click -> Open or removing quarantine metadata.
- No automated iPhone end-to-end test; the useful verification path requires a real trusted iPhone.

## Project Layout

```text
PhoneSnap/
├── docs/                          architecture, research notes, test plan
├── Sources/PhoneSnap/       macOS menu bar app
│   ├── AppDelegate.swift          app lifecycle and delivery pipeline
│   ├── CameraBridge.swift         ImageCaptureCore USB watcher
│   ├── ImageStore.swift           save received bytes as PNG
│   ├── Pasteboard.swift           multi-type clipboard write
│   ├── StatusItemController.swift menu bar item
│   ├── ThumbnailPresenter.swift   wires saved image to thumbnail window
│   ├── ThumbnailWindowController  borderless floating NSPanel
│   ├── ThumbnailView.swift        image view, actions, drag-out
│   └── Log.swift                  stderr logging
├── Sources/ICProbe/               ImageCaptureCore probe utility
├── Sources/UsbmuxdProbe/          usbmuxd probe utility
├── scripts/build-app.sh           wraps the SwiftPM binary into PhoneSnap.app
├── Package.swift
└── README.md
```

## License

Personal project, no license declared.
