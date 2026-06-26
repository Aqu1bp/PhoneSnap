# PhoneSnap

Drag real iPhone screenshots into your coding agent.

PhoneSnap is a tiny Mac menu bar app for AI-assisted iOS development. Plug in your iPhone, use an embedded debug sender from the app you are building, or run the generated iOS Shortcut fallback over Wi-Fi, and a draggable screenshot thumbnail appears on your Mac so you can drop real-device UI context into Codex, Cursor, Claude, ChatGPT, Slack, or an issue.

The point is the feedback loop: screenshot real hardware, drag it into the agent, keep building.

## Current Scope

PhoneSnap's primary universal path is still wired USB because it is the most reliable workflow.

- Supported: iPhone connected to the Mac over USB, trusted by the Mac.
- Supported: optional automatic wireless from debug senders embedded in the foreground app being built.
- Supported: optional fallback/manual wireless setup using a locally generated, signed PhoneSnap Shortcut.
- Not used: GitHub Gist rendezvous, third-party services, iCloud, or manual Shortcut URL/header/body entry.

Automatic wireless dev senders use the same Mac receiver URL/token contract as the Shortcut path, but snapshot the app UI instead of reading Photos. See [docs/DEV_SENDERS.md](docs/DEV_SENDERS.md) and [docs/WIRELESS.md](docs/WIRELESS.md).

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+ to build
- iPhone or iPad that appears to macOS through ImageCaptureCore
- USB or USB-C cable for wired mode
- Same Wi-Fi/LAN for wireless dev sender or Shortcut mode

## Quick Start

```bash
git clone <this repo>
cd PhoneSnap
./scripts/build-app.sh
open ./PhoneSnap.app
```

A small iPhone icon appears in the menu bar. The app is running.

## Use It

### Wired

1. Plug your iPhone into the Mac.
2. Unlock the iPhone.
3. If prompted, tap **Trust This Computer**.
4. Take a screenshot on the iPhone.
5. Drag the Mac thumbnail into Codex, Cursor, Claude, ChatGPT, Slack, or wherever the agent can see images.

The app uses Apple's ImageCaptureCore framework. macOS exposes a trusted, plugged-in iPhone as a camera-class device; PhoneSnap watches for new camera-roll items after startup, filters likely screenshots, downloads them, saves them, copies them to the clipboard, and shows the thumbnail.

### Automatic Wireless Dev Sender

1. Open the PhoneSnap menu bar item.
2. Choose **Copy Dev Sender Config** to copy the upload URL and token.
3. Add a debug-only sender to the app you are building, such as `senders/apple-ios` or `senders/expo`.
4. Run the app in the foreground on the phone.
5. Take an iOS screenshot. The debug sender snapshots the app UI and posts it to PhoneSnap.

Dev senders are foreground-app-only. They do not read Photos and should not store tokens. See [docs/DEV_SENDERS.md](docs/DEV_SENDERS.md).

### Wireless Shortcut Fallback

1. Open the PhoneSnap menu bar item.
2. Choose **Set Up Wireless Shortcut...**.
3. Scan the setup QR code with the iPhone Camera, or copy/open the setup URL.
4. On the iPhone, open `PhoneSnap.shortcut` and add it in Shortcuts.
5. Take a screenshot, then run the PhoneSnap Shortcut from Shortcuts, Action Button, Back Tap, Control Center, or the Home Screen.

The Shortcut is generated locally by the Mac app. It sends the latest screenshot from Photos to `POST /api/v1/upload/<pairId>` with a persisted bearer token, so the user does not type the URL, method, headers, or body. This remains useful when USB is unavailable and the target app does not have an embedded dev sender.

## Agent Workflow

- Test the app on a real device.
- Take a screenshot of the broken or awkward UI.
- Drag PhoneSnap's thumbnail into the agent chat.
- Ask for a fix with real visual context instead of describing layout by hand.

## Thumbnail Behavior

- Appears bottom-right of the screen containing the cursor.
- Auto-copies the screenshot to the clipboard on arrival.
- Shows action buttons for copy, save, and open.
- Click the image to open it in Preview.
- Drag the image directly into agent apps, chat apps, issue trackers, or any file drop target.
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
| Change wireless port | `PHONESNAP_WIRELESS_PORT=18472 open ./PhoneSnap.app` |

## How It Works

```text
iPhone over USB
  screenshot saved to camera roll
    -> ImageCaptureCore didAdd callback
    -> PhoneSnap downloads the new item
    -> saves PNG to ~/Pictures/PhoneSnap
    -> writes PNG/TIFF/file URL to NSPasteboard
    -> shows a floating NSPanel thumbnail

iPhone over Wi-Fi
  foreground app includes debug PhoneSnap sender
    -> user takes an iOS screenshot while app is active
    -> sender snapshots its active app UI
    -> POSTs raw PNG to the Mac receiver with Authorization: Bearer <token>
    -> the same save/pasteboard/thumbnail pipeline runs

iPhone over Wi-Fi fallback
  user runs generated PhoneSnap Shortcut
    -> Shortcut reads latest screenshot from Photos
    -> POSTs it to the Mac receiver with Authorization: Bearer <token>
    -> the same save/pasteboard/thumbnail pipeline runs
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing appears after taking a screenshot | Unlock the iPhone, reconnect the cable, and accept **Trust This Computer** if prompted. |
| Dragging into an agent does not attach the image | Use the copy button or paste with Command-V; PhoneSnap writes PNG, TIFF, and file URL pasteboard types. |
| Old photos appear | Quit and reopen the app, then take a fresh screenshot. |
| Clipboard paste fails | Use the thumbnail copy button; if it still fails, run from terminal with `swift run PhoneSnap` and check logs. |
| App does not launch | Rebuild with `./scripts/build-app.sh`. |
| Thumbnail appears on the wrong display | Move the mouse to the target display before taking the screenshot. |
| Wireless setup page does not load | Keep the Mac app running, put both devices on the same LAN, and try the fallback LAN URL shown in the setup window. |
| Wireless receiver is unavailable | Another process may be using the port. Quit the other process or relaunch with `PHONESNAP_WIRELESS_PORT=<port>`. Wired mode should still work. |
| Shortcut download fails | Run from terminal with `swift run PhoneSnap`; the setup route reports `/usr/bin/shortcuts sign` errors instead of crashing. |

## Known Limitations

- Wired USB remains the primary supported path.
- Automatic wireless requires a debug sender embedded in the foreground app being built.
- Shortcut wireless is manual-triggered and remains a fallback.
- Wireless requires the Mac app to be running and reachable from the iPhone on the local network.
- Shortcut signing depends on `/usr/bin/shortcuts sign --mode anyone`.
- One thumbnail at a time. A new screenshot dismisses the old thumbnail.
- Screenshot detection uses dimensions/aspect-ratio heuristics to avoid importing normal camera photos.
- No app sandbox and no notarization. First launch may require right-click -> Open or removing quarantine metadata.
- No automated iPhone end-to-end test; full wired/wireless verification requires a real trusted iPhone.

## Project Layout

```text
PhoneSnap/
├── docs/                          architecture, research notes, test plan
├── senders/                       debug embedded sender references
│   ├── apple-ios                  native UIKit Swift Package
│   ├── expo                       Expo prototype
│   ├── react-native               intended API stub
│   └── flutter                    intended API stub
├── Sources/PhoneSnap/       macOS menu bar app
│   ├── AppDelegate.swift          app lifecycle and delivery pipeline
│   ├── CameraBridge.swift         ImageCaptureCore USB watcher
│   ├── ImageStore.swift           save received bytes as PNG
│   ├── Pasteboard.swift           multi-type clipboard write
│   ├── StatusItemController.swift menu bar item
│   ├── WirelessReceiver.swift     local HTTP setup/upload receiver
│   ├── WirelessSetupWindow...     setup QR/window UI
│   ├── WirelessShortcut...        signed Shortcut generation
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
