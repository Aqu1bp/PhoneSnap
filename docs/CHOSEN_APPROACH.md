# CHOSEN_APPROACH — Back Tap (or Share/Action Button) → iOS Shortcut → LAN HTTP POST → Mac floating thumbnail

## TL;DR
1. **iPhone**: a Shortcut named `Send Screenshot to Mac`. Two actions:
   - `Get Latest Screenshots` (count = 1)
   - `Get Contents of URL` → POST → `http://<mac-lan-ip>:8472/screenshot` → Request Body = `Form` with one file field carrying the screenshot variable.
2. **iPhone trigger** (any of):
   - **Back Tap** (Settings → Accessibility → Touch → Back Tap → Double Tap → choose the shortcut). Primary.
   - **Share Sheet** (shortcut has "Show in Share Sheet" on, accepts Image input). Fallback.
   - **Action Button** (Settings → Action Button → Shortcut → pick this shortcut). iPhone 15 Pro+ only.
3. **Mac**: a SwiftPM-built executable, `ScreenshotCatch`, bundled into an `.app`. Runs as a menu bar item (LSUIElement). Listens on `0.0.0.0:8472`. On a valid POST it shows a borderless floating NSPanel in the bottom-right of the active screen with the screenshot. The panel supports drag-out, copy, save, open in Preview, and dismiss.

## Why this is the right choice

- **Apple-supported, no entitlement gymnastics** — every piece uses public, documented APIs.
- **Sub-1.5s latency** on LAN: the only meaningful work is the Shortcuts cold-start and a few-MB upload.
- **No cloud** — no iCloud throttling, no offline failure mode.
- **Free** — no paid Apple Developer account required, no third-party services.
- **Works during the dev workflow** — the developer is in their own app or any app; the Back Tap or Share gesture doesn't require a helper app to be open.
- **Drag-out for AI agents** — once the thumbnail is shown, the developer drags it directly into Claude Code, Cursor, ChatGPT, etc. This is the core dev-workflow win the user asked for.

## MVP scope

In scope:
- macOS executable (SwiftPM) that:
  - Runs as a background menu bar app (`LSUIElement`).
  - Listens on a TCP port (default `8472`) for HTTP POST requests.
  - Parses raw-body or multipart-body PNG/JPEG.
  - Persists the file to `~/Desktop/ScreenshotCatch/` with timestamped name.
  - Shows a borderless floating NSPanel anchored to the bottom-right of the active screen with the screenshot scaled to ≤220pt tall, rounded corners, drop-shadow, hover affordance.
  - Auto-copies the new screenshot to `NSPasteboard.general` (clipboard ready for ⌘V).
  - Supports drag-out from the thumbnail into any other app.
  - Supports click to open the file in Preview.
  - Supports close button + ESC to dismiss.
  - Auto-fades after 8 seconds (configurable).
- A status bar menu item with: app name, port + IP info, copy URL, quit.
- A Bash test script that POSTs a sample PNG with `curl`.
- An iOS Shortcut import description (because `.shortcut` files cannot be authored on Mac without Xcode; we provide step-by-step screenshot instructions).
- Documentation (RESEARCH, OPTIONS, CHOSEN, ARCHITECTURE, TEST_PLAN, README).

Out of scope for MVP (documented for future):
- Bonjour autodiscovery (manual IP is fine for one-time setup).
- TLS / authentication (LAN-only, trusted home network; can add token in v2).
- Watch Downloads / Photos library as fallback.
- A native iOS companion app.
- Multiple screenshots stacked in a tray.
- Custom save folder picker.

## Assumptions

1. iPhone and Mac are on the same Wi-Fi LAN, with peer-to-peer reachability (no AP isolation).
2. Mac's local IP is stable enough for one-time configuration in the Shortcut (or hostname.local works via mDNS).
3. The user is willing to grant Photos and Local Network permissions to Shortcuts on first invocation.
4. The user is willing to copy/paste the Mac's IP address into the Shortcut once.
5. The Mac is unsandboxed (we run as a SwiftPM-built CLI bundled into a `.app`), so no entitlement files are needed.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Mac's LAN IP changes (DHCP) | Status bar item shows current IP; also surface `${hostname}.local` |
| Wi-Fi AP isolation (some routers, public Wi-Fi) | Document; suggest hotspot from phone or different network |
| Shortcuts cold-start latency | Use minimal shortcut (2 actions); rely on Shortcuts to cache it |
| iOS Local Network privacy prompt | Document the one-time accept |
| Multipart parsing edge cases | Fallback to magic-byte scan if multipart parse fails |
| Window appearing on wrong screen | Anchor to the screen containing the mouse pointer |
| Panel stealing focus | Use `.nonactivatingPanel` + `.canJoinAllSpaces` |
| Large screenshots (Pro Max ≈ 4-8MB PNG) | Stream body read; chunked socket recv with size cap of 32 MB |
| Crash inside server kills app | Keep panel work on main thread; route socket work via async queue; wrap parsing in do/catch |

## Open follow-ups (post-MVP)

- Bonjour `_screenshotcatch._tcp` advertising and a tiny iOS helper to autoconfigure the Shortcut.
- Optional shared-secret token in `Authorization` header.
- Stack of recent thumbnails (≥1 simultaneous).
- Animated bounce-in matching simulator.
- Receive iPhone screen-recording videos too.
