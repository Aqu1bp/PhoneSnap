# TEST_PLAN

## Build Checks

```bash
swift build
swift build -c release
./scripts/build-app.sh
```

## Wired End-to-End

1. Launch the app. In Settings, select latest-only thumbnails for the controls below, then repeat capture in the default recent-strip mode.
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
- fresh preferences use the recent strip; selecting latest-only in Settings applies to USB, automatic Wi-Fi, and Shortcut uploads
- the Mac opens **Recent Screenshots** immediately and updates it as uploads arrive
- missing/incorrect token returns `401 Unauthorized`

## Wireless iPhone End-to-End

1. Launch PhoneSnap.
2. Choose **Set Up Wireless Shortcut...**.
3. Scan the QR code with the iPhone.
4. Open/add `PhoneSnap.shortcut`.
5. Take one or more screenshots.
6. Run the PhoneSnap Shortcut.
7. Confirm the Mac opens **Recent Screenshots**, each thumbnail drags into a file drop target, the files are saved, and the pasteboard contains the latest uploaded image.
8. Confirm screenshots are ordered by capture time, newest on the left and oldest on the right, including screenshots taken within the same second.
9. Re-run the Shortcut with the panel open, then after closing it. Confirm repeated screenshots keep their positions, even if the run is interrupted.
10. Take another screenshot and repeat. Confirm it appears ahead of older screenshots. Re-add an older Shortcut before checking chronology if its uploads lack embedded capture dates.

First run may require iOS Photos and local-network permission. Existing installed Shortcuts should be reinstalled to get batch behavior.

## Shortcut Generation

1. Download `GET /pair/<pairId>/PhoneSnap.shortcut`.
2. Convert or inspect the signed Shortcut with local plist tools.
3. Confirm `WFGetLatestPhotoCount` is `10` by default, or the value from `PHONESNAP_BATCH_COUNT` when that environment variable is set.
4. Confirm the workflow contains `is.workflow.actions.repeat.each` around the upload action.
5. Confirm the upload action still uses `POST`, the original upload URL, and `Authorization: Bearer <token>`.
6. Confirm `X-PhoneSnap-Captured-At` uses the Repeat Item's **Date Taken**, formatted as `yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX` (including milliseconds and timezone).

## Automatic Wi-Fi preview

- Fresh preferences: automatic capture off; legacy receiver remains independently off.
- Verified read-only hardware test: system Network address, no USB, existing pairing only; require pinned lockdown/AFC TLS and selected device identity.
- Bonjour-only discovery: launch the preview executable with `PHONESNAP_DIRECT_WIFI_ONLY=1`, no cable, and existing pairing. Confirm logs identify direct photo access, record time to actual Ready, and take two screenshots. Restart with the same preferences, confirm the old catalog is skipped and a new capture arrives. Remove the override afterward. No unpairing or system service restart is needed.
- Direct transport automated checks: full simulated lockdown/AFC handshake with both peers pinned, wrong device ID, plaintext session/service rejection, wrong AFC certificate, fragmented reads with and without TLS, wrong certificate rejection, early stream closure, stalled-operation cancellation, aggregate plist deadline, AFC frame bounds/sequence, and modern advertisement identity without legacy downgrade.
- One-time setup: selected USB phone, existing Trust, set/read back wireless enablement, unplug and wait for Ready.
- Fresh pairing: use a phone/Mac without prior pairing or an explicitly approved scoped reset, plus empty app preferences. Verify Enable rejects missing Trust; complete Finder/phone Trust; verify USB Enable survives its full cleanup and reads back enabled. Require an unplugged authenticated app connection and two captures before marking setup passed. A changed phone flag or direct diagnostic connection alone is insufficient. Record setup delay and recovery actions separately; see `AUTOMATIC_WIRELESS.md`.
- Live: two or more screenshots arrive as PNG files, clipboard updates, recent panel latest first.
- Rapid captures sharing an EXIF second: original DCIM sequence determines latest first even when received in reverse.
- Lock/unlock and fresh connection: no baseline replay; new pending files survive.
- USB handoff: confirm actual device identity fingerprints match between transports and no duplicate PNG is saved.
- Disable during a read: no late presentation; re-enable begins a new baseline.
- Corrupt images: unchanged size/modification time receives at most three downloads, including a structurally valid HEIC with undecodable pixels; later captures stay due. A repaired revision resumes delivery. Changing/incomplete files and transient disk failures remain retryable.
- Duplicate device names: every device has its own row, disambiguated label, and ID-bound selection after refresh/reordering.
- Native setup errors: missing/denied/pending Trust gives Trust guidance; password-protected or prohibited photo access gives unlock guidance.
- Packaging: launch an app copy outside the checkout, verify signatures and no Homebrew dylib paths, confirm Info.plist minimum >= every bundled binary’s minimum.
