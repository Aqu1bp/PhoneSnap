# ARCHITECTURE - PhoneSnap

PhoneSnap is a single-process macOS menu bar app. It watches a trusted USB-connected iPhone through ImageCaptureCore, downloads new screenshot-like camera-roll items, saves them as PNG files, copies them to the pasteboard, and presents a floating thumbnail.

## Process Model

```text
NSApplication
├── AppDelegate
├── StatusItemController
├── CameraBridge
│   └── ImageCaptureCore device/session callbacks
├── ImageStore
└── ThumbnailPresenter
    └── ThumbnailWindowController
        └── ThumbnailView
```

There is no LAN HTTP listener in the supported app path.

## CameraBridge

`CameraBridge` owns an `ICDeviceBrowser`, filters for local camera-class iPhone/iPad devices, opens an ImageCaptureCore session, and receives `cameraDevice(_:didAdd:)` callbacks.

To avoid importing the existing camera roll, it records a startup threshold and only considers files whose `creationDate` is newer than that threshold. It then applies a screenshot heuristic:

- long edge below camera-photo size
- long edge large enough to be a screen capture
- portrait-ish or landscape phone-screen aspect ratio

Matching files are downloaded to a temporary path, read into memory, removed from temp, and delivered to the app pipeline.

## Image Pipeline

1. `AppDelegate.deliver(data:source:)`
2. `ImageStore.save(data:)`
3. `ImageStore` decodes the incoming bytes with `NSImage`, normalizes to PNG, and writes to `~/Pictures/PhoneSnap` unless `PHONESNAP_DIR` overrides it.
4. Main queue presents the thumbnail and writes pasteboard data.

## UI

`StatusItemController` creates the menu bar item. The menu exposes:

- current mode
- show last screenshot
- reveal save folder
- quit

`ThumbnailWindowController` owns a borderless non-activating `NSPanel`. It anchors to the bottom-right of the screen containing the pointer, clamps inside the visible frame, fades in, and auto-dismisses after 8 seconds unless hovered.

`ThumbnailView` handles the image, action buttons, ESC/command shortcuts, and file drag-out.

## Configuration

- `PHONESNAP_DIR`: override the save folder.

## Removed Wireless Components

The previous LAN HTTP/Shortcut/QR/Gist design is intentionally not part of the runtime anymore. It was removed because only the wired path proved reliable enough for the current app.
