# ARCHITECTURE - PhoneSnap

PhoneSnap is a single-process macOS menu bar app. Its primary path watches a trusted USB-connected iPhone through ImageCaptureCore. An optional Android adapter discovers authorized ADB devices and captures their current displays on explicit menu actions. Both paths save PNG files, copy them to the pasteboard, and present a floating single thumbnail. The app also runs a local HTTP receiver for the generated wireless Shortcut batch fallback.

## Process Model

```text
NSApplication
├── AppDelegate
├── StatusItemController
├── CameraBridge
│   └── ImageCaptureCore device/session callbacks
├── AndroidADBBridge
│   ├── adb device polling
│   └── user-triggered screencap
├── WirelessReceiver
│   └── local HTTP setup, Shortcut download, and upload routes
├── WirelessSetupWindowController
│   └── setup URL, QR code, copy/open actions
├── ImageStore
├── ThumbnailPresenter
│   └── ThumbnailWindowController
│       └── ThumbnailView
└── WirelessBatchPresenter
    └── RecentFromIPhonePanelController
        └── RecentFromIPhoneThumbnailView
```

## CameraBridge

`CameraBridge` owns an `ICDeviceBrowser`, filters for local camera-class iPhone/iPad devices, opens an ImageCaptureCore session, and receives `cameraDevice(_:didAdd:)` callbacks.

To avoid importing the existing camera roll, it records a startup threshold and only considers files whose `creationDate` is newer than that threshold. It then applies a screenshot heuristic:

- long edge below camera-photo size
- long edge large enough to be a screen capture
- portrait-ish or landscape phone-screen aspect ratio

Matching files are downloaded to a temporary path, read into memory, removed from temp, and delivered to the app pipeline.

## AndroidADBBridge

`AndroidADBBridge` is an optional capture source. It locates `adb` through an
explicit override, Android SDK environment variables, the default Android
Studio SDK, the process path, and common Homebrew locations. Every three
seconds it runs `adb devices -l` on a serial queue and publishes ready,
unauthorized, offline, unavailable, or failed state to the menu.

The user selects **Capture Android Screen** for one ready device, or chooses a
device from a submenu when several are ready. The bridge invokes `adb` directly
with `-s <serial> exec-out screencap -p`; it never interpolates a command into a
shell. Standard output and error are drained concurrently with byte limits,
commands time out, and output must have a PNG signature before delivery.

ADB absence and failure are nonfatal and cannot stop the iPhone or wireless
paths. Polling invokes `adb devices -l`, which may implicitly start ADB's
shared loopback server and use the daemon's own mDNS discovery for wireless
debugging. PhoneSnap does not bundle ADB, explicitly configure or stop that
daemon, or attempt nonportable automatic Android camera-roll monitoring.

## WirelessReceiver

`WirelessReceiver` starts a local Network.framework TCP listener on `PHONESNAP_WIRELESS_PORT` or port `8472`. Bind failures are logged and shown in the menu/setup window, but wired mode still starts.

Supported routes:

- `GET /pair/<pairId>`: HTML setup page for the iPhone.
- `GET /pair/<pairId>/PhoneSnap.shortcut`: generated signed Shortcut file.
- `POST /api/v1/upload/<pairId>`: screenshot upload endpoint.

The receiver caps request bodies at 32 MB, accepts raw image bodies and multipart image/file bodies, and requires `Authorization: Bearer <token>` for uploads. Query-string tokens are rejected so bearer tokens do not leak through URLs, logs, or browser history.

`WirelessPairing` persists a short random pair ID and high-entropy bearer token in `UserDefaults`, so installed Shortcuts keep working across app restarts.

The portable sender/receiver boundary is specified in
[`PROTOCOL.md`](PROTOCOL.md). The setup page and signed Shortcut download are
macOS-specific extensions; cross-platform senders depend only on the upload
route.

`WirelessShortcutGenerator` builds the Shortcut plist with the upload URL/token baked in and signs it with `/usr/bin/shortcuts sign --mode anyone`. The generated Shortcut asks Photos for the latest screenshot batch, repeats over it, and posts one image per request. Signing errors are served as clear HTTP `500` responses.

## Image Pipeline

iPhone USB and Android ADB use the single-thumbnail behavior:

1. `AppDelegate.deliver(data:source:)`
2. `ImageStore.save(data:)`
3. `ImageStore` decodes the incoming bytes with `NSImage`, normalizes to PNG, and writes to `~/Pictures/PhoneSnap` unless `PHONESNAP_DIR` overrides it.
4. Main queue presents the thumbnail and writes pasteboard data.

Wireless Shortcut uploads use a separate batch presentation path:

1. `WirelessReceiver` accepts `POST /api/v1/upload/<pairId>`.
2. `AppDelegate.deliverWireless(data:)` saves each image through `ImageStore`.
3. Main queue writes the latest upload to pasteboard and enqueues the saved URL with `WirelessBatchPresenter`.
4. `WirelessBatchPresenter` debounces arrivals for a short quiet window and presents `RecentFromIPhonePanelController`.
5. `RecentFromIPhoneThumbnailView` supports file URL drag-out for each saved image.

## UI

`StatusItemController` creates the menu bar item. The menu exposes:

- current mode
- Android/ADB status and capture action
- wireless receiver status
- set up wireless Shortcut
- show last screenshot
- reveal save folder
- quit

`ThumbnailWindowController` owns a borderless non-activating `NSPanel`. It anchors to the bottom-right of the screen containing the pointer, clamps inside the visible frame, fades in, and auto-dismisses after 8 seconds unless hovered.

`ThumbnailView` handles the image, action buttons, ESC/command shortcuts, and file drag-out.

`RecentFromIPhonePanelController` owns a titled floating panel named **Recent from iPhone**. It shows the current wireless batch in a horizontal strip and each thumbnail can be dragged to an agent app or file drop target. Wireless uploads do not show `ThumbnailPresenter` by default.

## Configuration

- `PHONESNAP_DIR`: override the save folder.
- `PHONESNAP_WIRELESS_PORT`: override the wireless receiver port.
- `PHONESNAP_ADB_PATH`: explicit path to the ADB executable.

## Wireless Scope

The old GitHub/Gist rendezvous and direct `shortcuts://import-shortcut` QR flow are not part of the runtime. The current wireless setup uses a normal local HTTP setup page that serves a signed `PhoneSnap.shortcut`.

Dev senders are deprecated/experimental and are not exposed in the main menu. The sender package folders remain as references. Current product paths are iPhone USB automatic capture, Android ADB explicit capture, and the iOS wireless Shortcut batch fallback.
