# RESEARCH

PhoneSnap previously explored several ways to move iPhone screenshots to a Mac quickly:

- iOS Shortcuts automation
- Share Sheet shortcuts
- Back Tap / Action Button shortcuts
- LAN HTTP upload
- QR-installed signed shortcuts
- GitHub Gist rendezvous for changing Mac IPs
- iCloud Photos polling
- AirDrop
- ImageCaptureCore over USB

## Current Conclusion

The wired ImageCaptureCore path remains the primary workflow. PhoneSnap also supports an optional local wireless Shortcut path for users who accept manual Shortcut setup/execution and local-network dependency.

The removed Shortcut/LAN/QR variants were too fragile in practice because they depended on LAN reachability, iOS Shortcut import/runtime behavior, local-network permissions, changing Mac addresses, and user setup steps. The current version narrows the wireless scope: PhoneSnap serves a normal local setup page, generates and signs `PhoneSnap.shortcut` locally, persists the pairing token, and avoids GitHub/Gist rendezvous or manual Shortcut configuration.

The product framing is not generic photo transfer. PhoneSnap is for the AI-assisted UI development loop: take a real-device screenshot and drag it into an agent.

## Chosen Path

Use ImageCaptureCore with a trusted iPhone connected by USB as the primary path:

1. macOS sees the iPhone as a camera-class device.
2. PhoneSnap opens an ImageCaptureCore session.
3. New camera-roll items arrive through delegate callbacks.
4. The app filters likely screenshots, downloads them, saves them, copies them to the clipboard, and presents the floating thumbnail.

Optional wireless batch path:

1. PhoneSnap starts a local HTTP receiver.
2. The setup window shows a normal HTTP setup URL and QR code.
3. The iPhone opens a signed generated Shortcut.
4. Running the Shortcut uploads the latest 10 screenshots to the Mac, one image per request, with a persisted bearer token.
5. PhoneSnap saves each image, updates the pasteboard to the latest upload, and opens the **Recent from iPhone** batch panel.

## Notes

The probe targets remain useful for local investigation:

- `ICProbe` checks whether ImageCaptureCore can see the plugged-in iPhone.
- `UsbmuxdProbe` inspects Apple's usbmuxd device list. It is research-only and does not enable a supported wireless path.
- `WIRELESS.md` records the supported local Shortcut batch flow and its remaining limitations.
