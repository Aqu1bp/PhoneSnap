# PhoneSnap

Drag real iPhone screenshots into your coding agent.

PhoneSnap is a tiny Mac menu bar app for AI-assisted iOS development. Plug in your iPhone, or run the generated iOS Shortcut fallback over Wi-Fi, and draggable iPhone screenshots appear on your Mac so you can drop real-device UI context into Codex, Cursor, Claude, ChatGPT, Slack, or an issue.

The point is the feedback loop: screenshot real hardware, drag it into the agent, keep building.

## Current Scope

PhoneSnap's primary universal path is still wired USB because it is the most reliable workflow.

- Supported: iPhone connected to the Mac over USB, trusted by the Mac.
- Supported: fallback/manual wireless batch setup using a locally generated, signed PhoneSnap Shortcut.
- Deprecated/experimental: automatic wireless from debug senders embedded in the foreground app being built.
- Not used: GitHub Gist rendezvous, third-party services, iCloud, or manual Shortcut URL/header/body entry.

The generated Shortcut fetches the recent screenshot batch from Photos and posts each image to the Mac receiver. Existing installed PhoneSnap Shortcuts should be reinstalled to get batch behavior. Dev senders remain in the repo as deprecated/experimental references. See [docs/DEV_SENDERS.md](docs/DEV_SENDERS.md) and [docs/WIRELESS.md](docs/WIRELESS.md).

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+ to build
- iPhone or iPad that appears to macOS through ImageCaptureCore
- USB or USB-C cable for wired mode
- Same Wi-Fi/LAN for wireless Shortcut mode

## Quick Start

```bash
git clone <this repo>
cd <repo folder>
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

### Wireless Shortcut Batch Fallback

1. Open the PhoneSnap menu bar item.
2. Choose **Set Up Wireless Shortcut...**.
3. Scan the setup QR code with the iPhone Camera, or copy/open the setup URL. If the `.local` hostname will not load on your network, switch the QR to **IP address** in the setup window.
4. On the iPhone, open `PhoneSnap.shortcut` and add it in Shortcuts.
5. Take a screenshot, then run the PhoneSnap Shortcut from Shortcuts, Action Button, Back Tap, Control Center, or the Home Screen.

The Shortcut is generated locally by the Mac app. It asks Photos for the latest screenshot batch (10 by default, configurable with `PHONESNAP_BATCH_COUNT`) and posts each image to `POST /api/v1/upload/<pairId>` with a persisted bearer token, so the user does not type the URL, method, headers, or body. The Mac groups arrivals from the Shortcut and opens a floating **Recent from iPhone** panel with draggable thumbnails. This remains useful when USB is unavailable.

Existing installed PhoneSnap Shortcuts should be removed and reinstalled from the setup page to get batch behavior.

### Experimental Dev Senders

The `senders/` packages are deprecated as a main product path for now. They are kept as experimental references for foreground-app debug builds that post directly to the Mac upload endpoint. The menu no longer exposes a happy-path dev sender config action.

## Agent Workflow

- Test the app on a real device.
- Take a screenshot of the broken or awkward UI.
- Drag PhoneSnap's thumbnail into the agent chat.
- Ask for a fix with real visual context instead of describing layout by hand.

## Wired Thumbnail Behavior

- Appears bottom-right of the screen containing the cursor.
- Auto-copies the screenshot to the clipboard on arrival.
- Shows action buttons for copy (⌘C), save to Downloads (⌘S), and delete to Trash (⌘⌫). Click the image to open it in Preview.
- Click the image to open it in Preview.
- Drag the image directly into agent apps, chat apps, issue trackers, or any file drop target.
- Press ESC or click the close button to dismiss.
- Auto-fades after 8 seconds; hovering resets the timer.

## Wireless Batch Behavior

- Wireless Shortcut uploads do not show the wired single thumbnail by default.
- The Mac groups wireless images received within a short quiet window and opens a floating **Recent from iPhone** panel.
- Each panel thumbnail can be dragged into agent apps and file drop targets.
- The latest wireless upload is also written to the pasteboard for paste workflows.

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
| Change Shortcut batch size (1-50, default 10) | `PHONESNAP_BATCH_COUNT=20 open ./PhoneSnap.app`, then re-download and re-add the Shortcut |

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
  user runs generated PhoneSnap Shortcut
    -> Shortcut reads the latest screenshot batch from Photos
    -> repeats over the screenshots
    -> POSTs each image to the Mac receiver with Authorization: Bearer <token>
    -> Mac saves each PNG, updates pasteboard to the latest upload
    -> Mac shows the Recent from iPhone batch panel

iPhone over Wi-Fi experimental
  foreground app includes deprecated debug PhoneSnap sender
    -> sender snapshots its active app UI
    -> POSTs raw PNG to the Mac receiver with Authorization: Bearer <token>
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
| Wireless setup page does not load | Keep the Mac app running and put both devices on the same LAN. If macOS asked about incoming connections, allow PhoneSnap in System Settings → Network → Firewall. If the `.local` name will not resolve, switch the setup window QR to **IP address**. |
| Wireless receiver is unavailable | Another process may be using the port. Quit the other process or relaunch with `PHONESNAP_WIRELESS_PORT=<port>`. Wired mode should still work. |
| Shortcut used to work but now fails silently | If it was installed from the IP address URL, the Mac's IP likely changed. Rerun setup and re-add the Shortcut; prefer the `.local` hostname URL when it loads. |
| Shortcut runs but nothing appears on the Mac | Confirm screenshots exist in Photos, both devices are on the same LAN, and Shortcuts has local-network permission (iPhone Settings → Privacy & Security → Local Network). |
| Shortcut download fails | Run from terminal with `swift run PhoneSnap`; the setup route reports `/usr/bin/shortcuts sign` errors instead of crashing. If signing fails or times out on a fresh Mac, open the Shortcuts app once and retry. |

## Known Limitations

- Wired USB remains the primary supported path.
- Shortcut wireless is manual-triggered and remains a fallback.
- Existing installed Shortcuts need reinstall to get the latest batch upload behavior.
- Dev senders are deprecated/experimental and no longer exposed in the main menu.
- Wireless requires the Mac app to be running and reachable from the iPhone on the local network.
- Shortcut signing depends on `/usr/bin/shortcuts sign --mode anyone`.
- Wired mode shows one thumbnail at a time. A new wired screenshot dismisses the old wired thumbnail.
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
│   ├── WirelessBatchPresenter...   Recent from iPhone batch panel
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

## Security

Wireless mode runs a plain-HTTP receiver on your LAN, protected by a random pair ID and bearer token. Read [SECURITY.md](SECURITY.md) for the threat model before using it on shared networks. Wired mode opens no network listeners.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
