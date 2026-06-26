# CHOSEN_APPROACH - wired ImageCaptureCore first

## Decision

Use Apple's ImageCaptureCore framework to watch a trusted iPhone connected over USB as the primary workflow. Offer the generated wireless Shortcut batch flow as an optional fallback when the user accepts manual Shortcut setup/execution and local-network dependency.

## Why

- No iPhone Shortcut setup required for the primary path.
- No QR pairing required for the primary path.
- No LAN reachability assumptions for the primary path.
- No third-party service.
- No iCloud sync latency.
- Works through Apple-supported macOS APIs.

## User Flow

Primary wired flow:

1. Launch PhoneSnap on Mac.
2. Plug in and trust the iPhone.
3. Take an iPhone screenshot.
4. A floating thumbnail appears on Mac.

Optional wireless flow:

1. Launch PhoneSnap on Mac.
2. Choose **Set Up Wireless Shortcut...**.
3. Add the generated `PhoneSnap.shortcut` on the iPhone.
4. Take one or more iPhone screenshots and run the Shortcut.
5. PhoneSnap opens **Recent from iPhone** with the recent screenshot batch as draggable thumbnails.

## Rejected / Removed

GitHub/Gist rendezvous and direct `shortcuts://import-shortcut` QR setup remain removed. The supported wireless path uses a normal local HTTP setup page and a signed generated Shortcut, with wired USB still treated as the most reliable workflow.
