# iPhone setup

PhoneSnap supports wired USB, automatic Wi-Fi capture with an existing trusted pairing, and an optional wireless Shortcut batch fallback.

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

The screenshot should appear in the **Recent Screenshots** strip. Settings can switch all capture paths to a single latest thumbnail.

## Automatic Wi-Fi Setup

Choose **Set Up Automatic Wi-Fi…** in the Mac menu. Connect a new phone by cable once, unlock it, and approve Trust in Finder and on the phone. Select it and click **Enable Wireless**, then unplug and keep both devices on the same Wi-Fi. Wait for **Ready** before taking screenshots normally. An already paired phone visible over Wi-Fi can be selected without the cable. See [automatic Wi-Fi details and tested limits](AUTOMATIC_WIRELESS.md).

## Wireless Shortcut Setup

1. Build and launch the Mac app.
2. Open the PhoneSnap menu bar item.
3. Choose **Shortcut & Developer Uploads** → **Set Up Wireless Shortcut...**.
4. Scan the QR code with the iPhone Camera, or use the setup URL shown in the window. If the `.local` URL will not load on the iPhone, switch the QR to **IP address** in the setup window.
5. On the iPhone setup page, open `PhoneSnap.shortcut`.
6. Tap Add Shortcut in Shortcuts.
7. Take a screenshot and run the PhoneSnap Shortcut.

The Shortcut fetches the latest screenshot batch (10 by default, configurable with `PHONESNAP_BATCH_COUNT`) and posts them one by one to the Mac. PhoneSnap shows uploads using the same display setting as USB and automatic Wi-Fi: the **Recent Screenshots** strip by default, or a single latest thumbnail.

iOS may ask for Photos and local-network permission the first time the Shortcut runs. The Mac app must stay running and reachable on the same LAN. Existing installed PhoneSnap Shortcuts should be removed and reinstalled from the setup page to get batch behavior.

## If Nothing Appears

- Keep the iPhone unlocked for the first test.
- Unplug and reconnect the cable.
- Open Image Capture.app and confirm the iPhone appears there.
- If the iPhone prompts for trust again, accept it.
- Run `swift run PhoneSnap` from the repo root and watch the logs while taking a screenshot or running the Shortcut.

For the Shortcut fallback specifically:

- If macOS asked about incoming connections, allow PhoneSnap in System Settings → Network → Firewall — the menu can say "ready" while the firewall silently blocks the iPhone.
- Confirm Shortcuts has local-network permission on the iPhone (Settings → Privacy & Security → Local Network).
- If the Shortcut was installed from the IP address URL and the Mac's IP changed, rerun setup and re-add the Shortcut.
- Confirm there are screenshots in Photos - the Shortcut sends the latest configured batch and does nothing when there are none.

## Removed Wireless Pieces

PhoneSnap no longer uses GitHub/Gist rendezvous or a direct `shortcuts://import-shortcut` QR code. The current setup QR points to a normal local HTTP setup page served by the Mac app.
