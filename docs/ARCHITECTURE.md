# ARCHITECTURE - PhoneSnap

PhoneSnap has two desktop receivers. The single-process macOS menu bar app
watches a trusted USB iPhone through ImageCaptureCore, captures Android through
ADB on explicit actions, and accepts a generated Shortcut batch. The Windows
11 beta tray app implements the same stable upload protocol and serves a manual
iPhone Safari batch page. Platform-specific capture and UI stay outside the
portable protocol boundary.

## macOS Process Model

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

## Windows Process Model

```text
WinForms Application
├── PhoneSnapApplicationContext
│   ├── NotifyIcon tray menu
│   ├── SetupForm
│   │   ├── locally rendered setup QR
│   │   └── ranked network-address chooser
│   ├── RecentImagesForm
│   │   └── draggable FileDrop image cards
│   ├── ClipboardWriter
│   └── LanAddressProvider
│       └── Windows effective route metrics
├── ReceiverServer (PhoneSnap.Core)
│   ├── Kestrel HTTP/1.1 listener
│   ├── Safari batch setup page
│   └── protocol-v1 upload route
├── PairingStore (PhoneSnap.Core)
│   └── DpapiSecretProtector (Windows host)
└── ImageStore (PhoneSnap.Core)
    └── WorkerProcessPngNormalizer (PhoneSnap.Core)
        └── PhoneSnap.Windows.exe --phonesnap-png-worker
            └── WindowsPngNormalizer (GDI+)
```

`PhoneSnap.Core` targets plain .NET 10 so pairing, PNG header limits, atomic
storage, request handling, and protocol conformance can be tested on macOS,
Linux, or Windows. The `net10.0-windows` host supplies DPAPI, Windows image
decoding, clipboard formats, QR rendering, and WinForms UI.

The Windows project declares only `win-x64` and `win-arm64` runtime graphs.
Self-contained and single-file settings activate when a build or publish
supplies an explicit `RuntimeIdentifier`; a host-independent locked restore
therefore cannot add the SDK host's RID to the committed lockfile.

The Windows beta listens with Kestrel on all IPv4 interfaces on port `8472` by
default; Windows Firewall is the interface/profile enforcement boundary. It
serves:

- `GET /pair/<pairId>`: nonce-CSP Safari batch uploader.
- `POST /api/v1/upload/<pairId>`: the stable protocol-v1 upload endpoint.

The tray setup dialog encodes the capability-bearing setup URL in a QR code.
`LanAddressProvider` ranks usable addresses using likely physical/private LAN
suitability, gateway presence, and the Windows effective default-route metric
(route plus interface cost); likely VPN and virtual interfaces rank later.
`SetupForm` exposes all candidates when there is a choice, and selecting one
immediately regenerates the URL and QR.

Safari requires an explicit file selection, converts browser-decodable
non-PNG images to PNG on a canvas, rejects the converted PNG if it exceeds 32
MiB, and sends each selection independently as a raw `image/png` body. The
bearer token exists in the returned page's JavaScript and request header,
never in the URL or browser storage. The receiver authenticates and bounds the
request before decode, validates declared dimensions, and claims generated
filenames without overwriting an existing file. GDI+ runs in a short-lived
worker mode of the same executable over bounded standard-input/output pipes.
Request, deadline, and receiver-shutdown cancellation force-terminate and
reap that process rather than relying on cooperative cancellation inside
native image decoding; the parent revalidates the worker output before commit.

Windows USB/WPD is deliberately not connected to this process. The separate
native probe under `tools/windows/WpdProbe` measures public WPD device and event
behavior only. See [`WINDOWS_RESEARCH.md`](WINDOWS_RESEARCH.md) for its hardware
promotion gate.

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
[`PROTOCOL.md`](PROTOCOL.md). The macOS signed-Shortcut routes and Windows
Safari setup page are platform-specific extensions; cross-platform senders
depend only on the upload route.

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

Windows Safari uploads use the portable receiver pipeline:

1. The setup page converts when needed, checks the final PNG size, and posts
   one raw `image/png` body to `ReceiverServer` per selected file.
2. `ReceiverServer` authenticates and extracts the bounded body, then
   serializes decode/storage work under the linked request deadline.
3. `ImageStore` validates PNG dimensions, then
   `WorkerProcessPngNormalizer` sends the bounded input to the executable's
   isolated GDI+ worker. Deadline or shutdown cancellation kills and reaps the
   worker before releasing serialized processing.
4. The parent validates the bounded result again and atomically places a
   generated filename under `%USERPROFILE%\Pictures\PhoneSnap` unless
   `PHONESNAP_DIR` overrides it.
5. `UploadDelivered` marshals the saved path to the WinForms thread.
6. `ClipboardWriter` publishes image and file data, while `RecentImagesForm`
   adds a topmost card that drags with the standard Windows `FileDrop` format.

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

On Windows, `NotifyIcon` exposes receiver status, Safari setup, the most recent
screenshot, the save folder, and quit. `SetupForm` renders the setup QR locally
and shows an address selector when several LAN candidates exist.
`ClipboardWriter` applies a bounded retry to both delivered images and **Copy
address**; the latter shows an explicit warning if contention persists.
`RecentImagesForm` keeps up to 20 draggable images in a topmost horizontal
strip. These WinForms surfaces require a real Windows desktop session; the
portable core tests do not exercise clipboard, firewall, QR scanning, or drag
targets.

## Configuration

- `PHONESNAP_DIR`: override the macOS or Windows save folder.
- `PHONESNAP_WIRELESS_PORT`: override the macOS or Windows receiver port.
- `PHONESNAP_ADB_PATH`: explicit path to ADB for the macOS Android adapter.

## Wireless Scope

The old GitHub/Gist rendezvous and direct `shortcuts://import-shortcut` QR flow
are not part of the runtime. On macOS, the local HTTP setup page serves a
signed `PhoneSnap.shortcut`; on Windows, it serves the explicit Safari batch
uploader instead.

Dev senders are deprecated/experimental and are not exposed in the main menu.
The sender package folders remain as references. Current product paths are
macOS+iPhone USB automatic capture, macOS+Android ADB explicit capture, and the
macOS iOS Shortcut fallback, plus a hardware-unverified Windows+iPhone manual
Safari beta. WPD USB is a research probe, not a fifth product path.
