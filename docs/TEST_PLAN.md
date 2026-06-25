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

## Out of Scope

There is no HTTP probe anymore because the LAN receiver was removed. Wireless Shortcut and QR flows are not part of the supported test matrix.

Wireless research is tracked in `docs/WIRELESS.md`; do not add it to the supported test matrix until a prototype passes real-device testing.
