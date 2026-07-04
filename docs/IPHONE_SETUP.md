# iPhone setup

PhoneSnap supports wired USB capture as the primary path and an optional wireless Shortcut batch fallback.

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
4. Scan the QR code with the iPhone Camera, or use the setup URL shown in the window. If the `.local` URL will not load on the iPhone, switch the QR to **IP address** in the setup window.
5. On the iPhone setup page, open `PhoneSnap.shortcut`.
6. Tap Add Shortcut in Shortcuts.
7. Take a screenshot and run the PhoneSnap Shortcut.

The Shortcut fetches the latest screenshot batch (10 by default, configurable with `PHONESNAP_BATCH_COUNT`) and posts them one by one to the Mac. PhoneSnap groups the uploads and opens the **Recent from iPhone** panel with draggable thumbnails instead of the wired single thumbnail.

iOS may ask for Photos and local-network permission the first time the Shortcut runs. The Mac app must stay running and reachable on the same LAN. Existing installed PhoneSnap Shortcuts should be removed and reinstalled from the setup page to get batch behavior.

## If Nothing Appears

- Keep the iPhone unlocked for the first test.
- Unplug and reconnect the cable.
- Open Image Capture.app and confirm the iPhone appears there.
- If the iPhone prompts for trust again, accept it.
- Run `swift run PhoneSnap` from the repo root and watch the logs while taking a screenshot or running the Shortcut.

For wireless specifically:

- If macOS asked about incoming connections, allow PhoneSnap in System Settings → Network → Firewall — the menu can say "ready" while the firewall silently blocks the iPhone.
- Confirm Shortcuts has local-network permission on the iPhone (Settings → Privacy & Security → Local Network).
- If the Shortcut was installed from the IP address URL and the Mac's IP changed, rerun setup and re-add the Shortcut.
- Confirm there are screenshots in Photos - the Shortcut sends the latest configured batch and does nothing when there are none.

## Removed Wireless Pieces

PhoneSnap no longer uses GitHub/Gist rendezvous or a direct `shortcuts://import-shortcut` QR code. The current setup QR points to a normal local HTTP setup page served by the Mac app.
