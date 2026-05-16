# OPTIONS_COMPARISON

| # | Approach | Auto? | Latency | LAN-only | Taps after screenshot | Reliability | Complexity | Verdict |
|---|----------|-------|---------|----------|-----------------------|-------------|------------|---------|
| A | Personal automation "screenshot taken" | — | — | — | — | — | — | **REJECTED — trigger does not exist in iOS** |
| B | Share Sheet shortcut + LAN HTTP | No | ~0.6–1.5s | Yes | 2–3 | High | Low | **KEEP — fallback path** |
| C | **Back Tap → Shortcut → LAN HTTP** | 1 gesture | **~0.6–1.2s** | Yes | 1 (back-tap) | High | Low | **CHOSEN — primary** |
| D | Action Button → Shortcut → LAN HTTP | 1 press | ~0.6–1.2s | Yes | 1 (button) | Very high | Low | **DOCUMENTED — alt for iPhone 15 Pro+** |
| E | Custom iOS app using `userDidTakeScreenshotNotification` | Yes (when foregrounded) | ~0.3–1.0s | Yes | 0 | Low (foreground-only) | High | **REJECTED — foreground-only breaks the use case** |
| F | iCloud Photos sync + Mac PhotoKit/FSEvents | Yes | 5–60s+ | No | 0 | Low for timeliness | Medium | **REJECTED — too slow / variable** |
| G | iCloud Drive "Save to Files" + FSEvents | No | 3–15s | No | 4–5 | Medium | Low | **REJECTED — slower than B with more taps** |
| H | AirDrop + watch Downloads via FSEvents | No | 2–5s | LAN-ish (P2P) | 3–4 | Medium | Very low | **DOCUMENTED — manual fallback only** |
| I | Universal Clipboard + Mac pasteboard polling | No | 1–3s | P2P | 2 | Medium | Medium | **REJECTED — clobbers clipboard** |
| J | SMB share + FSEvents | No | 1–2s | LAN | 4+ | Medium | Medium | **REJECTED — extra taps, no speed win** |
| K | WebDAV endpoint on Mac + Files app | No | 1–2s | LAN | 4+ | Medium | High | **REJECTED — more code, no UX win** |

## Decision

**Primary path = C (Back Tap → Shortcut → LAN HTTP).**
**Secondary path bundled in same shortcut = B (Share Sheet) + D (Action Button).**

These three share *the same Shortcut* and *the same Mac server* — implementing one yields all three triggers at zero extra cost.

## Why the others are rejected (one line each)

- A: Apple does not expose this trigger; verified across iOS 17–26 docs and community sources.
- E: `UIApplication.userDidTakeScreenshotNotification` only fires while the helper app is foregrounded. During dev work the developer is in *their own app*, not the helper, so the notification never fires for the screenshots that matter.
- F / G: iCloud sync latency is highly variable and frequently exceeds 30s; explicitly outside the project's "avoid slow cloud-only workflows" guideline.
- H: AirDrop is manual and not automatable. Worth a future enhancement (watch Downloads folder) but not the MVP.
- I: Universal Clipboard would clobber the developer's clipboard — destructive to active workflow.
- J / K: SMB and WebDAV add taps and infrastructure with no latency advantage over a direct HTTP POST.

## Confirmed assumptions

- Shortcut action `Get Latest Screenshots` (count = 1) exists and returns the most-recent screenshot.
- Shortcut action `Get Contents of URL` supports POST with `File` body type using a photo variable, producing `multipart/form-data` to the server.
- Back Tap on iPhone 8+ / iOS 14+ can run a user-chosen Shortcut.
- `Network.framework`'s `NWListener` accepts incoming TCP connections from any LAN client on macOS without requiring entitlements in an unsandboxed binary.
- macOS NSPanel with `.borderless` + `.nonactivatingPanel` style yields a floating window that doesn't steal focus — matching the simulator UX.
