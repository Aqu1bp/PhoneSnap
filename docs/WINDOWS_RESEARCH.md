# Windows + iPhone research decision

Status: implementation boundary for `feature/windows-iphone-capture`, researched
2026-07-11.

## Decision

The next supported configuration is a **Windows protocol-v1 receiver with a
manual iPhone Safari batch uploader**. It is a local-LAN workflow:

1. PhoneSnap for Windows starts a receiver that implements
   [`PROTOCOL.md`](PROTOCOL.md).
2. The Windows app displays the capability-bearing local setup URL.
3. The user opens that page in Safari on an iPhone on the same trusted LAN.
4. The page uses a file picker to let the user explicitly select one or more
   screenshots from Photos.
5. The page sends one selected image per authenticated protocol-v1 request.
6. The Windows receiver validates and normalizes the image, saves it with a
   generated name, writes it to the Windows clipboard, and surfaces it in the
   recent-image UI.

This is intentionally a manual batch path. It does not claim that pressing the
iPhone screenshot buttons automatically notifies Windows.

Automatic USB capture through Windows Portable Devices (WPD) remains a
separate experiment. It must not appear as supported product behavior until it
passes the real-hardware gate below.

## Evidence behind the decision

### A browser uploader has a documented public surface

Apple documents that Safari on iOS supports HTML file uploads through
`<input type="file">` ([Safari Web Content Guide](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/CreatingContentforSafarioniPhone/CreatingContentforSafarioniPhone.html)).
The HTML standard defines both the file-upload state and the `multiple`
attribute ([HTML Living Standard](https://html.spec.whatwg.org/multipage/input.html#file-upload-state-(type=file))).
This gives the supported milestone a public, vendor-neutral way to request an
explicit batch selection without phone-side code or an undocumented API.

The page is a platform-specific setup extension, not a change to protocol v1.
It must upload each selected file independently with `Content-Length` and the
bearer token in `Authorization`, and it must display success or failure for
each file. It must not put the token in a URL, log, filename, analytics event,
or browser storage.

### The existing Shortcut cannot simply be generated on Windows

Apple documents `shortcuts sign` as a command run from Terminal on a Mac. Apple
also states that signing sends a copy of the Shortcut to Apple for validation
([Shortcuts User Guide for Mac](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)).
No official Windows signing interface was found. That absence is not proof that
no future interface can exist, but it is enough to exclude a Windows-generated
or generic PhoneSnap Shortcut from this milestone.

The Safari uploader therefore does not masquerade as automatic Shortcut
support. Shortcut provisioning can be reconsidered only if Apple documents a
portable signing/install flow and it is verified on a real iPhone.

### USB photo access is supported, but automatic WPD delivery is not promised

Apple's supported Windows flow requires the Apple Devices app, a USB cable, an
unlocked iPhone, and user approval of **Trust This Computer**. Apple then sends
the user to Microsoft Photos for an explicit import
([Apple: transfer photos to a Windows PC](https://support.apple.com/en-ie/120267),
[Microsoft: import photos from a phone](https://support.microsoft.com/en-au/windows/import-photos-and-videos-from-phone-to-pc-198f2301-e9a7-c734-5f39-a8946a5ebc99)).
Those instructions establish that Windows can import camera-roll objects. They
do not establish that Apple's Windows device stack emits a timely event for
every newly saved screenshot.

Microsoft's public WPD API is technically capable of the desired shape:

- `IPortableDeviceManager::GetDevices` enumerates connected portable devices
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevicemanager-getdevices)).
- `IPortableDevice::Advise` registers an application callback for device events
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevice-advise)).
- `WPD_EVENT_OBJECT_ADDED` means that a new object is available
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/event-constants)).
- Object resources can be read as an `IStream` through
  `IPortableDeviceResources::GetStream`
  ([Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/portable/opening-a-resource-and-retrieving-an-istream-object)).

The limiting fact is driver capability. Microsoft's own guidance says that
**some** WPD drivers support event notification and requires applications to
query `IPortableDeviceCapabilities::GetSupportedEvents` rather than assume an
event exists
([Microsoft: retrieving supported events](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/retrieving-the-events-supported-by-a-device)).
The existence of `WPD_EVENT_OBJECT_ADDED` in the Windows SDK therefore does not
prove that the Apple driver advertises it, fires it for screenshots, or makes
the new resource immediately readable.

That driver-dependent behavior is why WPD USB is experimental rather than the
supported Windows+iPhone milestone.

## Supported receiver milestone

The Windows milestone may claim support only for the following explicit flow:

- Windows 11 desktop receiver for the stable local upload protocol.
- Random persisted pair ID and high-entropy bearer token.
- A local setup page gated by the pair ID.
- A Safari file input restricted to images and allowing a batch selection.
- One authenticated upload request per selected image, with bounded sequential
  processing and visible per-file progress.
- The same 32 MiB request limit, decoded-pixel limit, generated filenames, and
  fail-closed image validation as the macOS receiver.
- Normalized PNG output in the user's PhoneSnap pictures folder.
- Windows clipboard image/file data and a recent batch UI suitable for paste or
  drag into an agent.
- Clear errors for unreachable LAN service, bad credentials, unsupported
  formats, oversized input, and storage failure.

The claim explicitly excludes:

- automatic iPhone USB capture;
- a generated or signed iOS Shortcut;
- background upload without an explicit Safari file selection;
- Bonjour or LAN scanning that advertises pairing material;
- TLS or safety on an untrusted LAN (protocol v1 remains plain HTTP).

## HEIC and HDR screenshot caveat

Format support cannot be inferred from an `.HEIC`, `.PNG`, or `.JPG` suffix.
Input must be decoded and dimension-checked before it is accepted.

This matters more on current iPhones than it did for the original Mac path.
Apple documents that on iOS 26:

- **SDR** screenshots are PNG;
- **HDR** screenshots are HEIC.

See [Apple's iPhone screen-capture format settings](https://support.apple.com/en-lamr/guide/iphone/iph2d2500abc/26/ios/26).
Apple also documents that USB import may convert HEIF media to JPEG unless the
user selects **Keep Originals**
([Apple: using HEIF or HEVC media](https://support.apple.com/en-us/116944)).
Consequently, a WPD filename, media type, and byte representation may vary with
both screenshot and transfer settings.

Windows Imaging Component has built-in PNG and JPEG codecs, while HEIF support
is an extension codec and its underlying HEVC support may not exist on every PC
([WIC overview](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec),
[WIC HEIF extension](https://learn.microsoft.com/en-us/windows/win32/wic/heif-codec)).

The guaranteed browser-upload path for the first milestone is therefore an SDR
PNG screenshot. If the receiver cannot decode a selected HDR HEIC screenshot,
the setup page must keep the batch intact, mark that file as failed, and explain
how to choose **Settings > General > Screen Capture > SDR** on the iPhone. HEIC
may be advertised only after its decoder dependency and HDR-to-SDR
normalization have been tested; it is not implicit protocol-v1 conformance.

## Rejected private and fragile approaches

The Windows implementation must use documented public operating-system and web
interfaces. In particular, it must not:

- dynamically bind to undocumented Apple Mobile Device/CoreDevice DLL entry
  points;
- reverse engineer AFC, lockdown, or another Apple-private transport;
- enumerate `IPortableDeviceManager::GetPrivateDevices` and treat vendor-private
  devices as a generic integration surface (Microsoft describes those devices
  as accessible only to applications designed for them in the
  [`IPortableDeviceManager` documentation](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nn-portabledeviceapi-iportabledevicemanager));
- scrape or automate the Apple Devices or Microsoft Photos user interface;
- read an iCloud/Photos database or poll a third-party cloud service;
- install, replace, configure, or redistribute Apple's Windows drivers.

These paths have no stable public contract for PhoneSnap, make trust and update
failures difficult to diagnose, and would turn a small local utility into a
vendor-version compatibility project. Public WPD APIs are acceptable for the
probe; Apple-private APIs are not an escape hatch if WPD fails.

## Exact promotion gate for automatic WPD USB

WPD USB stays labelled **research-only** until one probe build passes every
item below. A partial pass is a failure of the gate, not permission to ship a
best-effort automatic mode.

### Required hardware and software matrix

- One fully updated Windows 11 PC with the current production Apple Devices app
  and Apple device driver installed through supported channels.
- Two physical, currently supported iPhones: one Lightning model and one USB-C
  model, running two different supported iOS major versions.
- A data-capable cable for each phone.
- Each phone tested after a fresh trust reset and again as an already trusted
  device.
- Each phone tested in all four combinations of Screen Capture **SDR/HDR** and
  Photos transfer **Automatic/Keep Originals**.

### Required observations

For each phone and each of the four format/transfer combinations:

1. The public WPD device enumerator sees the unlocked and trusted iPhone and
   reports a stable device identity for the connection.
2. `GetSupportedEvents` explicitly includes `WPD_EVENT_OBJECT_ADDED`.
3. Starting the probe records a catalog baseline and imports zero existing
   camera-roll objects.
4. Take five new screenshots: three portrait and two landscape. All five must
   produce an object-added callback within 5 seconds.
5. Every callback must lead, using public WPD content/resource interfaces only,
   to a complete readable image within 10 seconds, allowing bounded retry when
   the event precedes resource readiness.
6. Every image must pass signature-based decoding and the pixel limit, then
   normalize to a viewable PNG with the expected orientation.
7. The result must contain exactly five new files: no missed screenshots, no
   duplicate delivery, and no historical photo import.

This is 40 successful screenshot deliveries in total: 2 phones x 4 settings x
5 screenshots.

Then, for each phone:

1. Unplug and reconnect it three times, including one reconnect while locked.
2. Confirm the probe releases the old WPD connection, explains the locked/trust
   state, resubscribes after unlock, and captures the next screenshot without a
   process restart.
3. Restart the probe while the phone remains connected; confirm the new catalog
   baseline imports nothing old and the next screenshot is delivered once.
4. Unplug during one resource read; confirm the read fails safely, no partial
   file is surfaced, and the next reconnect recovers.

The latency and correctness logs must redact device serials and contain no
image bytes or pairing credentials. The HEIF extension must be tested both
present and absent: with it present, HDR HEIC must decode; without it, the probe
must fail that item safely with an actionable codec/SDR explanation.

If either tested phone/driver combination does not advertise or reliably emit
object-added events, the gate fails. Catalog polling is not silently
substituted and automatic USB support is not claimed. The supported Safari
uploader remains the Windows path.

## Stacked branch dependency

`feature/windows-iphone-capture` is intentionally stacked on
`feature/cross-platform-capture` at commit `46b56af`, not on the current `main`.
The parent branch contributes the stable protocol contract, bounded receiver
behavior, fail-closed image normalization, and cross-platform capture
documentation on which this milestone depends.

Until the parent branch merges, the Windows branch must remain a stacked change
and must not be merged independently into `main`. After the parent branch
lands, rebase the Windows branch onto the updated `main`, confirm that its diff
contains only Windows-milestone work, and rerun both the existing macOS suite
and the new Windows suite.
