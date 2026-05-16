# RESEARCH — Mirror iOS Simulator screenshot thumbnail for a real iPhone

Goal: when a screenshot is taken on a real iPhone, surface it on Mac as a floating thumbnail in the bottom-right corner (matching the iOS Simulator experience), with copy / drag / save / dismiss. Optimized for low latency so the user can immediately drag the screenshot into an AI coding agent on Mac.

Target hardware: iPhone (any modern model, iOS 17+) + Mac (macOS 26 Tahoe, this machine).

---

## Approach A — iOS Shortcuts personal automation, "when screenshot is taken"

1. **How it would work**: a Personal Automation in Shortcuts that triggers automatically when iOS detects a screenshot, runs a Shortcut that grabs the latest screenshot and POSTs it to a Mac server.
2. **iPhone setup**: create automation, action POSTs image to Mac.
3. **Mac setup**: HTTP server (covered in transport section).
4. **Speed**: would be ~1–2s end-to-end on LAN.
5. **Reliability**: N/A — see (11).
6. **Offline/LAN**: yes if LAN transport.
7. **Automatic?**: would be 100% automatic.
8. **Permissions**: Photos access, local network.
9. **Complexity**: low if it existed.
10. **Risks**: requires trigger to exist.
11. **Why rejected**: **iOS Shortcuts does NOT expose a "screenshot taken" trigger.** Verified via Apple's documented trigger list (Time, App Open/Close, NFC, Focus, Charger, Airplane Mode, Email, Message, CarPlay, Wallet, Sleep, Workout) and multiple community sources. No screenshot detection trigger exists in any iOS version through iOS 26. **REJECTED — not technically possible.**

---

## Approach B — iOS Shortcuts Share Sheet, invoked from screenshot preview / Photos

1. **How it would work**: the user takes a screenshot, then taps the bottom-left preview that appears, taps Share, and picks the "Send Screenshot to Mac" shortcut. The shortcut POSTs the image bytes to a Mac HTTP server.
2. **iPhone setup**: one shortcut configured with "Show in Share Sheet" enabled, accepting image input.
3. **Mac setup**: LAN HTTP listener; Mac IP/hostname captured in shortcut.
4. **Speed**: ~0.6–1.5s after final tap on LAN.
5. **Reliability**: high; well-supported, no flaky personal automation behavior.
6. **Offline/LAN**: yes (no cloud required).
7. **Automatic?**: no — requires 2–3 taps after screenshot (thumbnail → share → shortcut).
8. **Permissions**: local network (iOS prompts once), Photos read access if reading from library.
9. **Complexity**: low. Shortcut uses one action ("Get Contents of URL") with `File` body.
10. **Risks**: friction from taps; share sheet has a learning curve; if the screenshot preview is dismissed the user must open Photos and share from there.
11. **Why considered**: Apple-supported, no entitlement needed for the iOS side, fast, reliable. **KEEP as a fallback path.**

---

## Approach C — Back Tap → Shortcut → POST latest screenshot

1. **How it would work**: user maps Back Tap (double-tap or triple-tap the back of iPhone) to a Shortcut named "Send Latest Screenshot to Mac". The shortcut uses the "Get Latest Screenshots" action (count 1), then "Get Contents of URL" to POST it to the Mac HTTP server.
2. **iPhone setup**:
   - Settings → Accessibility → Touch → Back Tap → Double Tap → choose the shortcut.
   - Shortcut: `Get Latest Screenshots` (count 1) → `Get Contents of URL` (POST, multipart File body).
   - Grant Photos and Local Network permissions on first run.
3. **Mac setup**: HTTP listener on a chosen port; user's Mac IP entered into the shortcut once.
4. **Speed**: ~0.6–1.2s after the back-tap on LAN (Shortcuts cold-start latency + image upload).
5. **Reliability**: high once permissions granted; Back Tap itself can have occasional misses on cases.
6. **Offline/LAN**: yes.
7. **Automatic?**: one gesture after screenshot (double-tap back). Not fully automatic but the closest practical approximation of the simulator UX.
8. **Permissions**: Photos read, Local Network (iOS will prompt once), Accessibility (for Back Tap, system-level).
9. **Complexity**: low. Same shortcut as approach B, plus a Settings toggle.
10. **Risks**: Back Tap occasionally misfires in cases / through covers; some users find it inconsistent. Mitigation: also expose the same shortcut in the Share Sheet (B) and from Spotlight.
11. **Why considered**: **Best UX** given Apple's API constraints — one tap after screenshot. **KEEP as primary trigger.**

---

## Approach D — Action Button → Shortcut (iPhone 15 Pro+ / 16+)

1. **How it would work**: Settings → Action Button → assign to Shortcut → "Send Latest Screenshot to Mac".
2. **iPhone setup**: requires iPhone 15 Pro, 15 Pro Max, or any iPhone 16. Configure Action Button to run the same shortcut as C.
3. **Mac setup**: same as B/C.
4. **Speed**: identical to C (~0.6–1.2s).
5. **Reliability**: very high (physical button, no accelerometer guesswork).
6. **Offline/LAN**: yes.
7. **Automatic?**: one press after screenshot.
8. **Permissions**: same as C, no extra Accessibility flag.
9. **Complexity**: identical to C.
10. **Risks**: only available on Action Button-equipped iPhones; user may have Action Button reserved for camera/silent.
11. **Why considered**: equivalent to C but hardware-dependent. **DOCUMENT as alternative for capable iPhones.**

---

## Approach E — Custom iOS app using `UIApplication.userDidTakeScreenshotNotification`

1. **How it would work**: build a native iOS app that observes the system notification when the user takes a screenshot. While the app is in the foreground, it loads the latest screenshot from Photos and uploads it to Mac.
2. **iPhone setup**: install the custom app via Xcode + free Apple ID provisioning (7-day signing) OR paid developer cert.
3. **Mac setup**: LAN HTTP listener.
4. **Speed**: ~0.3–1.0s — fastest of all options if reliable.
5. **Reliability**: only fires **while the app is foregrounded**. Cannot run reliably in background. Per Apple docs, `userDidTakeScreenshotNotification` posts to the running app only.
6. **Offline/LAN**: yes.
7. **Automatic?**: yes, but only when the custom app is the foreground app.
8. **Permissions**: Photos read, Local Network, code-signing for sideloading.
9. **Complexity**: medium-high. Requires an Xcode iOS project, code signing, weekly resign for free Apple ID, Apple Developer Program ($99/yr) for permanent installs, and TestFlight if shared.
10. **Risks**:
    - Doesn't help when user is screenshotting their own dev app (custom app is not foregrounded).
    - Doesn't help when screenshotting other apps (Slack, Safari, etc.) — custom app is not foregrounded.
    - **Effectively only works if the user is inside the helper app, which defeats the purpose.**
    - Background refresh / silent push are unreliable and don't fire on screenshot.
11. **Why rejected**: the screenshot notification is foreground-only, so this approach cannot satisfy the use case (taking screenshots in any app during dev work). **REJECTED.**

---

## Approach F — iCloud Photos sync, Mac watches Photos library

1. **How it would work**: iPhone screenshots upload to iCloud Photos. A Mac app uses `Photos.framework` (PhotoKit on macOS) or `FSEventStream` on `~/Pictures/Photos Library.photoslibrary` to detect new screenshots and display them.
2. **iPhone setup**: enable iCloud Photos (most users already have).
3. **Mac setup**: PhotoKit observer or FSEvents on Photos library; needs Photos library access permission.
4. **Speed**: **5–60s typical, often longer**. Apple optimistically syncs but real-world latency on Wi-Fi is highly variable; cellular adds more delay; Low Power Mode pauses sync.
5. **Reliability**: low-to-moderate for *timely* delivery. Eventually-consistent.
6. **Offline/LAN**: no — requires both devices online with iCloud auth.
7. **Automatic?**: yes, fully automatic.
8. **Permissions**: Photos Library access on Mac, iCloud signed in on both devices.
9. **Complexity**: medium. PhotoKit on macOS or library file watching, plus Photos thumbnail extraction.
10. **Risks**: latency kills the "instant" feel; Apple throttles when on battery; battery + cellular sync delays; the user explicitly said "avoid slow or unreliable cloud-only workflows".
11. **Why rejected**: too slow and too variable for a dev workflow. **REJECTED as primary**; could be a passive fallback but adds complexity without enough payoff.

---

## Approach G — iCloud Drive folder, "Save to Files" share

1. **How it would work**: after screenshot, user shares → Save to Files → an iCloud Drive folder. Mac app watches that folder via FSEvents and displays new files.
2. **iPhone setup**: more taps than approach B — Share → Save to Files → pick folder → Save.
3. **Mac setup**: FSEvents watcher on `~/Library/Mobile Documents/com~apple~CloudDocs/Screenshots/`.
4. **Speed**: 3–15s typical (iCloud Drive sync). Faster than Photos but slower than LAN.
5. **Reliability**: moderate. iCloud Drive sync sometimes stalls.
6. **Offline/LAN**: no — needs iCloud.
7. **Automatic?**: no — manual save.
8. **Permissions**: iCloud sign-in, FSEvents access (none required on Mac for own home dir).
9. **Complexity**: low on Mac side, but UX worse than approach B with more taps.
10. **Risks**: slow sync; ambiguous if multiple devices are uploading.
11. **Why rejected**: strictly worse than B (slower and more taps). **REJECTED.**

---

## Approach H — AirDrop

1. **How it would work**: user shares the screenshot → AirDrop → Mac. The Mac receives it into Downloads.
2. **iPhone setup**: per-screenshot manual share.
3. **Mac setup**: AirDrop on, Mac discoverable.
4. **Speed**: 2–5s after picking destination.
5. **Reliability**: moderate. Discovery can be flaky after sleep/lock.
6. **Offline/LAN**: works via peer-to-peer Wi-Fi + Bluetooth; doesn't need router.
7. **Automatic?**: no — multiple manual taps each time.
8. **Permissions**: no special permissions.
9. **Complexity**: very low — works today, no code.
10. **Risks**: not automatable. Mac side has no public API to "watch for AirDropped files" beyond filesystem monitoring of Downloads.
11. **Why partially considered**: useful as a manual fallback, but the project goal is faster than this. Could combine with FSEvents on Downloads folder to auto-pop the thumbnail when an AirDropped image arrives. **DOCUMENT as a future enhancement; not the MVP path.**

---

## Approach I — Continuity Camera / Universal Clipboard

1. **How it would work**: copy screenshot on iPhone → paste on Mac via Universal Clipboard.
2. **iPhone setup**: requires `Copy` from share sheet.
3. **Mac setup**: same Apple ID + Bluetooth + Wi-Fi; observe clipboard for image content.
4. **Speed**: 1–3s.
5. **Reliability**: moderate; clipboard handoff occasionally fails.
6. **Offline/LAN**: P2P, no internet needed.
7. **Automatic?**: no — manual copy.
8. **Permissions**: none specific.
9. **Complexity**: medium — Mac app polls `NSPasteboard.changeCount`; image then displayed.
10. **Risks**: clobbers user's clipboard; pasteboard polling is OS-supported but heavy; doesn't carry filename/metadata.
11. **Why rejected as primary**: clobbers clipboard (bad UX during coding when developer has other things copied). Could be a polite secondary feature but not core. **REJECTED.**

---

## Approach J — SMB / SSHFS network share, "Save to Files" to a Mac-hosted location

1. **How it would work**: Mac runs SMB; iPhone's Files app mounts it; "Save to Files" writes directly to Mac filesystem; Mac app watches the share folder.
2. **iPhone setup**: connect to SMB server in Files app (one-time).
3. **Mac setup**: enable File Sharing (System Settings); pick a folder; Mac app FSEvents.
4. **Speed**: 1–2s on LAN.
5. **Reliability**: moderate — SMB connections drop after sleep.
6. **Offline/LAN**: LAN only.
7. **Automatic?**: no — manual save each time.
8. **Permissions**: File Sharing user permissions, Mac admin.
9. **Complexity**: medium — relies on the user keeping Mac SMB share online.
10. **Risks**: SMB sessions are stateful and finicky on iOS Files app.
11. **Why rejected**: extra taps than approach B with no speed advantage. **REJECTED.**

---

## Approach K — WebDAV / custom mac-side file endpoint via Files app

1. **How it would work**: Mac app exposes a WebDAV endpoint; user adds it as a Files location; saves screenshot to it.
2. **iPhone setup**: configure WebDAV in Files app.
3. **Mac setup**: implement WebDAV (a substantial spec).
4. **Speed**: comparable to LAN HTTP.
5. **Reliability**: depends on WebDAV correctness.
6. **Offline/LAN**: LAN.
7. **Automatic?**: no.
8. **Permissions**: local network.
9. **Complexity**: medium-high. WebDAV is overkill for one operation.
10. **Risks**: protocol surface is large.
11. **Why rejected**: an HTTP POST is simpler and the Shortcut path skips the Files step entirely. **REJECTED.**

---

## Mac receive transport sub-research — winner: NWListener (TCP) with minimal HTTP server

- **NWListener** from `Network.framework` lets us bind a TCP port and accept connections without any external dependency. Apple's recommended modern API.
- **Bonjour advertising** via `NWListener.service` lets the shortcut find us by name on the LAN (we will defer this; manual IP is simpler for MVP).
- **No entitlement** is required on macOS for incoming local-network connections in an unsandboxed CLI/SPM-built app. (iOS local network usage description is on the iPhone side and is automatic for Shortcuts.)
- We parse HTTP manually: read request line, headers, `Content-Length`, body. Minimal parser ~80 LOC; we accept POST with either:
  - `Content-Type: image/png` / `image/jpeg` — body is the raw image
  - `Content-Type: multipart/form-data` — parse the first file part
- Robust fallback: if parsing produces no clean image, scan the raw body for PNG (`89 50 4E 47`) or JPEG (`FF D8 FF`) magic bytes and extract from there.

## Mac UI sub-research — winner: borderless NSPanel anchored bottom-right

- **NSPanel** (with style `.borderless`, `.nonactivatingPanel`) is the standard Apple way to do floating, non-stealing-focus windows. Matches the iOS Simulator's thumbnail behavior (which uses an `NSPanel` internally).
- Window level: `.floating` (above normal windows, below screen-saver).
- Anchor to bottom-right of the screen containing the cursor, with 24pt inset, matching simulator metrics.
- Auto-dismiss after configurable timeout (default 8s) with a fade animation; dismissible via close button or ⎋.
- Drag-out: implement `NSPasteboardItemDataProvider` + `NSDraggingSource` so the user can drag the thumbnail into any app (Claude Code, Cursor, Slack, Mail).
- Click: open the saved file in Preview.
- Copy: place an NSImage on `NSPasteboard.general`.
- Save: drop a timestamped PNG into `~/Desktop/ScreenshotCatch/` (configurable later).

## Mac status bar — winner: `NSStatusBar` item, `LSUIElement = true`

- Bundle the app with `LSUIElement` so no Dock icon / no menu bar app menu — only a status item.
- Menu: Show/Hide, Copy LAN URL, Quit.

## Performance budget

- Total target end-to-end (back-tap → bottom-right thumbnail on Mac): **≤ 1.5s** on LAN, **≤ 800ms** typical.
- Breakdown:
  - Shortcuts boot + "Get Latest Screenshots": 200–400ms
  - PNG bytes over LAN (typical screenshot ≈ 2–5 MB): 50–200ms
  - Server parse + UI present: < 100ms

---

## Summary

The only fully automatic approach (A) doesn't exist in iOS. The only background-capable native approach (E) is foreground-bound. Cloud paths (F, G) are too slow. The fast LAN paths (B, C, D) all converge on the same architecture — a Shortcut that POSTs to a Mac HTTP server. C (Back Tap) gives the best post-screenshot UX with a single gesture; B (Share Sheet) is the fallback / explicit path; D (Action Button) is documented for capable iPhones.
