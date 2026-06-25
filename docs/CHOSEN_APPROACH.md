# CHOSEN_APPROACH - wired ImageCaptureCore

## Decision

Use Apple's ImageCaptureCore framework to watch a trusted iPhone connected over USB.

## Why

- No iPhone Shortcut setup.
- No QR pairing.
- No LAN reachability assumptions.
- No third-party service.
- No iCloud sync latency.
- Works through Apple-supported macOS APIs.

## User Flow

1. Launch PhoneSnap on Mac.
2. Plug in and trust the iPhone.
3. Take an iPhone screenshot.
4. A floating thumbnail appears on Mac.

## Rejected / Removed

The wireless Shortcut flow and QR pairing flow were removed. They depended on LAN reachability and fragile Shortcut import/runtime behavior, and in practice only the wired path was reliable enough to support.
