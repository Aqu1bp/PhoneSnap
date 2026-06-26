# iPhone setup

PhoneSnap supports wired USB capture as the primary path and an optional wireless Shortcut setup path.

## Wired Setup

1. Build and launch the Mac app:

   ```bash
   ./scripts/build-app.sh
   open ./PhoneSnap.app
   ```

2. Plug the iPhone into the Mac with a USB or USB-C cable.
3. Unlock the iPhone.
4. If iOS asks whether to trust the computer, tap **Trust This Computer** and enter the passcode.
5. Take a screenshot on the iPhone.

The screenshot should appear as a floating thumbnail on the Mac.

## Wireless Shortcut Setup

1. Build and launch the Mac app.
2. Open the PhoneSnap menu bar item.
3. Choose **Set Up Wireless Shortcut...**.
4. Scan the QR code with the iPhone Camera, or use the setup URL shown in the window.
5. On the iPhone setup page, open `PhoneSnap.shortcut`.
6. Tap Add Shortcut in Shortcuts.
7. Take a screenshot and run the PhoneSnap Shortcut.

iOS may ask for Photos and local-network permission the first time the Shortcut runs. The Mac app must stay running and reachable on the same LAN.

## If Nothing Appears

- Keep the iPhone unlocked for the first test.
- Unplug and reconnect the cable.
- Open Image Capture.app and confirm the iPhone appears there.
- If the iPhone prompts for trust again, accept it.
- Run `swift run PhoneSnap` from the repo root and watch the logs while taking a screenshot or running the Shortcut.

## Removed Wireless Pieces

PhoneSnap no longer uses GitHub/Gist rendezvous or a direct `shortcuts://import-shortcut` QR code. The current setup QR points to a normal local HTTP setup page served by the Mac app.
