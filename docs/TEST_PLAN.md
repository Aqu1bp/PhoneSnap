# TEST_PLAN

## Build Checks

```bash
swift build
swift build -c release
swift test
./scripts/build-app.sh
```

Windows receiver checks from `receivers/windows`:

```powershell
dotnet restore PhoneSnap.Windows.slnx --locked-mode
dotnet test tests/PhoneSnap.Core.Tests/PhoneSnap.Core.Tests.csproj `
  --configuration Release --no-restore
dotnet build src/PhoneSnap.Windows/PhoneSnap.Windows.csproj `
  --configuration Release --runtime win-x64 --no-restore
dotnet build src/PhoneSnap.Windows/PhoneSnap.Windows.csproj `
  --configuration Release --runtime win-arm64 --no-restore
```

The `PhoneSnap.Core` tests are portable and run on macOS, Linux, or Windows.
The two WinForms builds prove both target graphs compile; running DPAPI, the
Windows decoder, clipboard, QR dialog, firewall flow, and drag UI requires
Windows.

From a clean checkout, the locked restore must leave every
`packages.lock.json` unchanged on Windows, macOS, and Linux. The Windows host
lock must contain `win-x64` and `win-arm64`, with no RID inherited from the
machine performing the restore.

## Wired End-to-End

1. Launch the app.
2. Plug in an iPhone.
3. Unlock the iPhone and accept **Trust This Computer** if prompted.
4. Take a screenshot.
5. Confirm a thumbnail appears on the Mac.
6. Confirm the file is saved under `~/Pictures/PhoneSnap` or `PHONESNAP_DIR`.
7. Confirm clipboard paste inserts the image.
8. Confirm thumbnail controls:
   - copy
   - save to Downloads
   - open in Preview
   - drag into a file drop target
   - ESC or close button dismisses
   - auto-dismiss after 8 seconds

## Device Detection

Run the ImageCaptureCore probe:

```bash
swift run ICProbe
```

Expected: a trusted plugged-in iPhone appears as a camera-class device.

## Android ADB End-to-End

1. Install Android SDK Platform Tools.
2. Connect an Android phone with USB debugging enabled and authorize the Mac.
3. Confirm `adb devices -l` reports the device in `device` state.
4. Launch PhoneSnap and confirm its Android status shows the model as ready.
5. Choose **Capture Android Screen**.
6. Confirm a single thumbnail appears, a PNG is saved, and paste works.
7. Confirm drag, copy, save, open, delete, ESC, and timeout behavior.
8. With two ready devices, confirm PhoneSnap presents a device submenu and
   captures the selected display.
9. Revoke USB debugging authorization and confirm the menu gives actionable
   authorization status without affecting iPhone or wireless operation.

The parser, executable resolver, bounded process runner, timeout, output limit,
PNG validation, and bridge state transitions are covered by `swift test`.

## Wireless Receiver Smoke Test

Run PhoneSnap from source on a temporary port and save folder:

```bash
PHONESNAP_WIRELESS_PORT=18472 PHONESNAP_DIR=/tmp/phonesnap-test swift run PhoneSnap
```

In another terminal:

```bash
curl -i http://127.0.0.1:18472/pair/<pairId>
curl -i http://127.0.0.1:18472/pair/<pairId>/PhoneSnap.shortcut
curl -i -X POST \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: image/png" \
  --data-binary @sample.png \
  http://127.0.0.1:18472/api/v1/upload/<pairId>

for i in 1 2 3; do
  curl -i -X POST \
    -H "Authorization: Bearer <token>" \
    -H "Content-Type: image/png" \
    --data-binary @sample.png \
    http://127.0.0.1:18472/api/v1/upload/<pairId>
done

for i in $(seq 1 10); do
  curl -i -X POST \
    -H "Authorization: Bearer <token>" \
    -H "Content-Type: image/png" \
    --data-binary @sample.png \
    http://127.0.0.1:18472/api/v1/upload/<pairId>
done
```

Expected:

- setup page returns `200 OK` HTML
- Shortcut download returns `200 OK` with `PhoneSnap.shortcut`, or a clear signing error if `/usr/bin/shortcuts sign` fails
- upload returns `{"ok":true,...}`
- a PNG is saved to `PHONESNAP_DIR`
- wireless uploads do not show the wired bottom-right thumbnail
- after the debounce window, the Mac opens the **Recent from iPhone** panel for the received batch
- missing/incorrect token returns `401 Unauthorized`

The automated `./scripts/smoke-test.sh` additionally covers raw and multipart
PNG, bearer-scheme casing, `Expect: 100-continue`, query-token rejection,
malformed and oversized framing, normalized output, session deduplication, and
credential-redacted logs.

## Wireless iPhone End-to-End

1. Launch PhoneSnap.
2. Choose **Set Up Wireless Shortcut...**.
3. Scan the QR code with the iPhone.
4. Open/add `PhoneSnap.shortcut`.
5. Take one or more screenshots.
6. Run the PhoneSnap Shortcut.
7. Confirm the Mac opens **Recent from iPhone**, each thumbnail drags into a file drop target, the files are saved, and the pasteboard contains the latest uploaded image.

First run may require iOS Photos and local-network permission. Existing installed Shortcuts should be reinstalled to get batch behavior.

## Windows + iPhone Safari End-to-End

This is the implemented Windows beta, not yet a supported release
configuration. It requires physical hardware because CI cannot operate
Safari's Photos picker or Windows desktop integration. Passing the full list
on x64 promotes only x64; Arm64 remains unverified until repeated on an Arm64
PC.

1. On a Windows 11 x64 or Arm64 PC, start `PhoneSnap.Windows.exe`.
2. Start a second copy and confirm it reports that PhoneSnap is already
   running without changing the first instance's pairing credentials.
3. If Windows Firewall prompts, allow the app on **Private networks only** and
   confirm its inbound rule does not allow the Public profile.
4. With Wi-Fi or Ethernet plus a VPN/virtual adapter active, open the tray menu
   and setup dialog. Confirm the recommended address favors the suitable
   private physical interface and lower effective default-route metric (route
   plus interface cost). If several addresses remain, select the network shared
   with the iPhone and confirm the displayed URL and QR update immediately.
5. Choose **Open iPhone Upload Page...** and scan the QR with an iPhone on the
   same trusted LAN.
6. Confirm Safari opens `/pair/<pairId>` without displaying the bearer token in
   the address bar.
7. Choose several SDR screenshots from Photos or Files and upload them.
8. Include one browser-decodable non-PNG image; confirm the page converts it,
   checks the converted PNG size, sends it as a raw `image/png` request, and
   the receiver stores a normalized PNG.
9. Select a source smaller than 32 MiB whose converted PNG is larger than 32
   MiB; confirm the page rejects it before making an upload request. Confirm a
   valid near-limit PNG is sent without multipart framing.
10. Confirm every file gets an independent success/failure result and one failed
   item does not stop the remaining batch.
11. Confirm generated filenames appear under
   `%USERPROFILE%\Pictures\PhoneSnap` or `PHONESNAP_DIR`, with no sender
   filename reuse or overwrite.
12. Confirm the latest screenshot pastes as an image and file, and each card in
    **Recent PhoneSnap Screenshots** drags into Explorer and at least one target
    agent application.
13. Upload at least 20 large valid screenshots and confirm Task Manager does
    not show unbounded growth from retained full-resolution previews.
14. Hold the Windows clipboard open from another process during one upload and
    confirm PhoneSnap reports that the file was saved but the clipboard is
    busy.
15. While the clipboard is still held, choose **Copy address**. Confirm
    PhoneSnap performs a bounded retry, reports that the address was not
    copied, and remains responsive; release the clipboard and confirm retrying
    the action succeeds.
16. Change Wi-Fi/DHCP address while PhoneSnap runs; confirm the setup QR updates
    and a newly opened page reaches the receiver without restarting the app.
17. Start once with no usable LAN adapter; confirm PhoneSnap does not present a
    loopback QR and enables setup after the private LAN becomes available.
18. Close and reopen the setup dialog; confirm the current QR and page work.
19. Repeat with Windows Firewall access removed and confirm the failure is
    understandable without affecting saved files or app shutdown.
20. Quit while a large upload is decoding and confirm both the receiver and
    its `--phonesnap-png-worker` child exit promptly, with no partial PNG saved.

The automated .NET suite covers pairing persistence/rotation/corruption,
pre-decode PNG dimension limits, collision-safe concurrent storage, setup-page
CSP, converted-PNG size enforcement, raw `image/png` uploader shape, address
ranking, exact lowercase protocol JSON, raw and multipart protocol input,
authentication-before-decode, query-token rejection, framing errors, corrupt
PNG rejection, unsupported transfer encoding, `Expect: 100-continue`, and
worker termination/reaping on both the request deadline and receiver shutdown.
It does not replace the physical steps above or exercise WinForms clipboard
contention.

HDR screenshots can be HEIC on current iOS releases. Test both an SDR PNG and
an HDR selection. If Safari cannot decode the HDR image, the page should mark
only that item failed; do not claim HEIC support from a filename extension.

## Experimental Windows WPD Probe

The native probe under `tools/windows/WpdProbe` is research-only. Its build or
successful device enumeration is not a Windows USB product test. Automatic
Windows+iPhone USB may be promoted only after the complete multi-phone,
format, reconnect, event, and failure matrix in
[`WINDOWS_RESEARCH.md`](WINDOWS_RESEARCH.md) passes. Until then:

- do not list WPD as a supported capture result;
- do not substitute catalog polling when Apple's driver omits reliable
  object-added events;
- do not use Apple-private APIs or UI automation as a fallback.

## Shortcut Generation

1. Download `GET /pair/<pairId>/PhoneSnap.shortcut`.
2. Convert or inspect the signed Shortcut with local plist tools.
3. Confirm `WFGetLatestPhotoCount` is `10` by default, or the value from `PHONESNAP_BATCH_COUNT` when that environment variable is set.
4. Confirm the workflow contains `is.workflow.actions.repeat.each` around the upload action.
5. Confirm the upload action still uses `POST`, the original upload URL, and `Authorization: Bearer <token>`.
