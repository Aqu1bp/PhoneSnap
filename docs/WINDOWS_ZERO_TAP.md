# Windows + iPhone with no interaction

Status: research, nothing implemented.

## The bar

PhoneSnap's product promise is that you take a screenshot and drag it into your
agent. Nothing else. The Mac wired path meets this exactly: ImageCaptureCore
pushes new camera-roll items from a trusted USB iPhone, so pressing the
screenshot buttons is the only action.

Any Windows design is measured against that, not against "better than nothing".
The closed Safari uploader ([#16](https://github.com/Aqu1bp/PhoneSnap/pull/16))
cost six or seven interactions per batch, which is why it was rejected.

A candidate qualifies only if, with the iPhone connected or configured once:

1. Taking a screenshot requires no further phone interaction.
2. The image reaches the PC in seconds, not minutes.
3. It arrives as a draggable image, decoded, without user intervention.

## Candidates

### 1. WPD events over USB — unresolved, and possibly unnecessary

The existing plan. `IPortableDevice::Advise` registers for
`WPD_EVENT_OBJECT_ADDED`, the app pulls the new object through
`IPortableDeviceResources::GetStream`.

Microsoft is explicit that event notification is **optional per driver** and
that applications must query `IPortableDeviceCapabilities::GetSupportedEvents`
rather than assume ([Retrieving the Events Supported by a
Device](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/retrieving-the-events-supported-by-a-device)).
Nothing public establishes that Apple's Windows driver advertises the event,
fires it for screenshots, or exposes the bytes promptly. Searching for evidence
turns up only unrelated iPhone-import breakage, not a confirmed working
event subscription.

`tools/windows/WpdProbe` on the closed branch was written to answer exactly
this. It still should be run — but see the next candidate, because the answer
may not be on the critical path.

### 2. AFC over USB via libimobiledevice — strongest candidate

Apple's own `AppleMobileDeviceService` (installed with the Apple Devices app or
iTunes) exposes AFC, the file-conduit service that gives access to the media
partition including `DCIM`.
[libimobiledevice](https://libimobiledevice.org/) speaks these protocols
natively without jailbreaking, and Windows binaries exist
([jrjr/libimobiledevice-windows](https://github.com/jrjr/libimobiledevice-windows)).
AFC exposes the DCIM folder directly and is the approach photo tooling
generally relies on.

**Why this is the strongest option: it does not need the WPD event.** Instead of
waiting to be told, PhoneSnap lists `DCIM` on a short interval and notices new
files itself. Driver event support becomes irrelevant. Polling a directory
listing over USB is cheap, and the Mac path already proves that a poll-free
push isn't required for the experience to feel instant — what matters is that
the user does nothing.

This is also the closest structural match to the Mac: cable, trusted device,
camera roll, no phone interaction, no cloud.

Open questions before committing:

- Latency: how quickly does a new screenshot appear in an AFC directory listing
  after capture, and does it appear at all while the phone is locked? The Mac
  path requires unlock + trust; parity is acceptable, worse is not.
- Dependency: does this require the user to install Apple Devices or iTunes for
  the driver and `AppleMobileDeviceService`? A dependency is tolerable; a
  fragile or undocumented one is not.
- Licensing: libimobiledevice is LGPL. The exact version and whether dynamic
  linking is compatible with this repository's licence needs checking before a
  line of code is written.
- Stability: an unofficial protocol implementation can break on an iOS update.
  What is the historical breakage rate?

### 3. iCloud for Windows folder watch — works, but off-brand and slow

With iCloud Photos enabled, new photos download automatically to
`C:\Users\<name>\Pictures\iCloud Photos\Downloads`
([Apple](https://support.apple.com/en-us/guide/icloud-windows/icw864162159/icloud)).
A `FileSystemWatcher` on that folder is trivial and needs no phone interaction,
so it clears bar #1 without any reverse engineering.

It fails on the other two:

- **Speed.** Users widely report iCloud for Windows pacing downloads at roughly
  one photo per 30 seconds, and Explorer taking minutes to populate
  ([Apple Support Communities](https://discussions.apple.com/thread/254956433)).
  A screenshot that shows up half a minute later does not feel like the Mac.
- **Positioning.** The README sells the wired path as working "without iCloud",
  and the app is local-first with no telemetry. Routing every screenshot
  through Apple's cloud, and requiring iCloud storage, contradicts that.

Worth keeping as a documented fallback for users who already run iCloud Photos.
Not the primary design.

### 4. Microsoft Phone Link — not a foundation

As of 2026, Phone Link does sync recent iPhone photos including the screenshots
folder ([Microsoft](https://support.microsoft.com/en-us/windows/apps/phonelink/setting-up-photos-in-the-phone-link)),
limited to recent items after pairing.

There is no public API or supported hook for another app to observe that
stream. Reading Phone Link's internal storage would be undocumented, unstable,
and outside anything Microsoft supports. Rejected as a base to build on.

### 5. iPhone-side automation — cannot reach zero

There is **no "screenshot taken" trigger** in Shortcuts personal automations
([Apple](https://support.apple.com/guide/shortcuts/create-a-new-personal-automation-apdfbdbd7123/ios)),
and its absence is deliberate — a background automation that fires on every
screenshot is an obvious exfiltration path. The supported model is that the
user takes a screenshot and then runs something against the most recent one.

Back Tap can launch a Shortcut, which reduces the Safari uploader's six or
seven interactions to one. Better, still not zero, and it puts the phone back
in the user's hand. A sideloaded app watching the photo library cannot run
reliably in the background either.

Any phone-side design tops out at one deliberate action, so this direction
cannot meet the bar by construction.

## Recommendation

1. **Prototype AFC polling.** It is the only candidate that plausibly matches
   the Mac experience, and it sidesteps the unanswered WPD event question
   entirely. Answer the four open questions above before writing a receiver.
2. **Still run `WpdProbe`.** It is already written and costs one session with a
   Windows PC. If Apple's driver does fire `WPD_EVENT_OBJECT_ADDED`, a push
   design is cleaner than polling and uses only public Microsoft API.
3. **Document iCloud folder watching as a fallback**, clearly labelled as
   cloud-dependent and slower, for users who already have it on.
4. **Do not revive the Safari uploader.** It cannot meet the bar.

## What has to be true before any implementation

- A new screenshot is observable on the PC within a few seconds of capture,
  with the phone untouched after the initial cable connection and trust.
- The mechanism is either public Microsoft API (WPD) or a licence-compatible
  library whose breakage risk is understood (AFC).
- HDR screenshots are handled or the limitation is explicit: on iOS 26, HDR
  screenshots are HEIC, and Windows' HEIF codec is an optional extension whose
  HEVC dependency is not present on every PC. See
  [`WINDOWS_RESEARCH.md`](WINDOWS_RESEARCH.md).

Until the first of these is demonstrated on real hardware, Windows support has
no defensible design.
