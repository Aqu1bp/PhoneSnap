# ARCHITECTURE - PhoneSnap

PhoneSnap is a single-process macOS menu bar app. Its primary path watches a trusted USB-connected iPhone through ImageCaptureCore, downloads new screenshot-like camera-roll items, saves them as PNG files, copies them to the pasteboard, and presents the chosen thumbnail style. It also supports an opt-in automatic Wi-Fi watcher for one selected trusted phone and runs a separately enabled local HTTP receiver for the generated wireless Shortcut batch fallback.

## Process Model

```text
NSApplication
├── AppDelegate
├── StatusItemController
├── CameraBridge
│   └── ImageCaptureCore device/session callbacks
├── WirelessReceiver
│   └── local HTTP setup, Shortcut download, and upload routes
├── WirelessSetupWindowController
│   └── setup URL, QR code, copy/open actions
├── ImageStore
├── ThumbnailPresenter
│   └── ThumbnailWindowController
│       └── ThumbnailView
└── RecentScreenshotsPresenter
    └── RecentScreenshotsPanelController
        └── RecentScreenshotThumbnailView
```

## CameraBridge

`CameraBridge` owns an `ICDeviceBrowser`, filters for local camera-class iPhone/iPad devices, opens an ImageCaptureCore session, and receives `cameraDevice(_:didAdd:)` callbacks.

To avoid importing the existing camera roll, it records a startup threshold and only considers files whose `creationDate` is newer than that threshold. It then applies a screenshot heuristic:

- long edge below camera-photo size
- long edge large enough to be a screen capture
- portrait-ish or landscape phone-screen aspect ratio

Matching files are downloaded to a temporary path, read into memory, removed from temp, and delivered to the app pipeline.

## Automatic Wi-Fi

`AutomaticWirelessWatcher` performs photo I/O on one serial worker. The selected device's USB presence pauses its wireless connection. `PhoneDeviceConnection` is restricted to USB, including device-name lookup; its native network TLS does not verify the peer. It reads the saved pairing HostID via usbmuxd and calls StartSession, never Pair or Unpair. Only an explicit setup action on a selected USB phone sets and reads back `EnableWifiConnections`. Trust and locked-device errors produce specific recovery instructions. Picker items carry device IDs instead of array positions, and duplicate names display distinct ID suffixes.

`DirectPhoneDiscovery` browses `_apple-mobdev2._tcp` on main and publishes locked endpoint snapshots. Modern advertisement tags are matched against the selected pairing's HostID-derived key; legacy names use its saved Wi-Fi MAC. `PhoneWiFiRoute` combines addresses from Apple's device list and matched Bonjour advertisements. All candidates use `DirectPhoneConnection`, which opens lockdown TCP port 62078 with the saved pairing. OpenSSL authenticates the host and pins the saved device certificate's public key; the selected device ID is checked inside TLS. AFC uses the returned service port and requires the same pinned TLS identity. Neither connection permits plaintext or a native network fallback. `PhonePairingRecord` keeps certificate material in memory. No Wi-Fi operation pairs, writes settings, or changes phone files.

`PhonePhotoConnection` shares catalog/image validation between connection implementations. `PhoneTCP` provides nonblocking, cancellable socket/TLS I/O with monotonic deadlines; each plist or AFC frame shares one deadline across its fragments. Failed streams are discarded. Discovery changes wake the worker immediately; current device ID and generation are captured atomically, and late service callbacks are ignored after stop.

The first complete DCIM listing becomes the baseline before Ready is shown. Later scans enqueue new paths. Catalog and pending files survive reconnects and Mac wake during the same enabled session, without device-clock comparisons. Disable resets the baseline. Transient read/save failures use per-file backoff so one file cannot prevent later captures; transport failures reopen the connection. Three container-validation or PNG-normalization failures for an unchanged size/modification time suspend downloads of that revision. Metadata-only checks every minute allow a changed file to be retried. Disk errors and cancellation do not consume this rejection budget. Generation checks suppress obsolete reads and queued presentations after stop or switching phones.

AFC reads only regular files up to 32 MB. File sizes/modification times must remain stable across reads, actual lengths must match, and PNG/HEIF container checks run before ImageIO normalization. A phone-screen geometry heuristic excludes camera optics metadata. Capture dates come from the original image, with AFC birth time as fallback; the source DCIM sequence breaks ties for equal-second timestamps.

USB and automatic Wi-Fi share a serialized capture-identity/save decision. Identity includes normalized device identifier, original filename, and capture second, so transport conversions can match while separate identical captures remain distinct. The legacy Shortcut’s intentional replay/re-show semantics stay separate.

`scripts/bundle-native-libs.py` copies the complete native dependency graph, rewrites install names, includes license notices, computes the bundle’s actual minimum macOS, and signs/verifies the bundle. No runtime Python or Homebrew installation is required.

## WirelessReceiver

`WirelessReceiver` starts a local Network.framework TCP listener on `PHONESNAP_WIRELESS_PORT` or port `8472`. Bind failures are logged and shown in the menu/setup window, but wired mode still starts.

Supported routes:

- `GET /pair/<pairId>`: HTML setup page for the iPhone.
- `GET /pair/<pairId>/PhoneSnap.shortcut`: generated signed Shortcut file.
- `POST /api/v1/upload/<pairId>`: screenshot upload endpoint.

The receiver caps request bodies at 32 MB, accepts raw image bodies and multipart image/file bodies, and requires `Authorization: Bearer <token>` for uploads. Query-string tokens are rejected so bearer tokens do not leak through URLs, logs, or browser history.

`WirelessPairing` persists a short random pair ID and high-entropy bearer token in `UserDefaults`, so installed Shortcuts keep working across app restarts.

`WirelessShortcutGenerator` builds the Shortcut plist with the upload URL/token baked in and signs it with `/usr/bin/shortcuts sign --mode anyone`. The generated Shortcut asks Photos for the latest screenshot batch, repeats over it, and posts one image per request. Signing errors are served as clear HTTP `500` responses.

## Image Pipeline

USB and automatic Wi-Fi share the automatic delivery path:

1. `AppDelegate.deliverAutomatic(...)`
2. `ImageStore.save(data:)`
3. `ImageStore` decodes the incoming bytes with ImageIO, normalizes to PNG, and writes to `~/Pictures/PhoneSnap` unless `PHONESNAP_DIR` overrides it.
4. Main queue writes pasteboard data and calls `surface`, which follows `ThumbnailSettings`: Recent Screenshots strip by default, or the latest-only floating thumbnail. Capture date and source sequence are passed to the strip.

Wireless Shortcut uploads retain batch deduplication and use the same presentation setting:

1. `WirelessReceiver` accepts `POST /api/v1/upload/<pairId>`.
2. `AppDelegate.deliverWireless(data:)` saves each image through `ImageStore`.
3. Main queue writes the latest upload to pasteboard and calls `surface` with its capture date.
4. In strip mode, `RecentScreenshotsPresenter` updates immediately in capture order and presents `RecentScreenshotsPanelController`.
5. `RecentScreenshotThumbnailView` supports file URL drag-out for each saved image.

## UI

`StatusItemController` creates the menu bar item. The menu exposes:

- automatic Wi-Fi connection status, toggle, and setup
- current wired status
- wireless receiver status
- set up wireless Shortcut
- show last screenshot
- reveal save folder
- settings for thumbnail style and Shortcut uploads
- quit

`ThumbnailWindowController` owns a borderless non-activating `NSPanel`. It anchors to the bottom-right of the screen containing the pointer, clamps inside the visible frame, fades in, and auto-dismisses after 8 seconds unless hovered.

`ThumbnailView` handles the image, action buttons, ESC/command shortcuts, and file drag-out.

`RecentScreenshotsPanelController` owns a titled floating panel named **Recent Screenshots**. It shows recent captures from all sources in a horizontal strip and each thumbnail can be dragged to an agent app or file drop target. Wireless uploads do not show `ThumbnailPresenter` by default.

## Configuration

- `PHONESNAP_DIR`: override the save folder.
- `PHONESNAP_WIRELESS_PORT`: override the wireless receiver port.

## Wireless Scope

The old GitHub/Gist rendezvous and direct `shortcuts://import-shortcut` QR flow are not part of the runtime. The current wireless setup uses a normal local HTTP setup page that serves a signed `PhoneSnap.shortcut`.

Dev senders are deprecated/experimental and are not exposed in the main menu. The sender package folders remain as references, with automatic USB/Wi-Fi capture as the main product paths and Shortcut uploads as a separate fallback.
