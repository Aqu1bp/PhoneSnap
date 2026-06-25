# iPhone setup - wired mode

PhoneSnap is currently wired-only. There is no QR pairing flow, Shortcut setup, or wireless receiver in the app.

## Setup

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

## If Nothing Appears

- Keep the iPhone unlocked for the first test.
- Unplug and reconnect the cable.
- Open Image Capture.app and confirm the iPhone appears there.
- If the iPhone prompts for trust again, accept it.
- Run `swift run PhoneSnap` from the repo root and watch the logs while taking a screenshot.

## Removed Wireless Flow

The old wireless path used iOS Shortcuts, QR install pages, and later a GitHub Gist rendezvous file. That path was removed because it was unreliable enough to mislead users. The app no longer starts a LAN HTTP server and no longer exposes pairing UI.
