# TEST_PLAN

## Build Checks

```bash
swift build
swift build -c release
./scripts/build-app.sh
```

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
```

Expected:

- setup page returns `200 OK` HTML
- Shortcut download returns `200 OK` with `PhoneSnap.shortcut`, or a clear signing error if `/usr/bin/shortcuts sign` fails
- upload returns `{"ok":true,...}`
- a PNG is saved to `PHONESNAP_DIR`
- missing/incorrect token returns `401 Unauthorized`

## Wireless iPhone End-to-End

1. Launch PhoneSnap.
2. Choose **Set Up Wireless Shortcut...**.
3. Scan the QR code with the iPhone.
4. Open/add `PhoneSnap.shortcut`.
5. Take a screenshot.
6. Run the PhoneSnap Shortcut.
7. Confirm the Mac thumbnail appears, the file is saved, and the pasteboard is updated.

First run may require iOS Photos and local-network permission.
