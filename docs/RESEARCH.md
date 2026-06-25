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

Only the wired ImageCaptureCore path is supported.

The Shortcut/LAN/QR variants were removed because they were too fragile in practice. They depended on LAN reachability, iOS Shortcut import/runtime behavior, local network permissions, changing Mac addresses, and user setup steps. The result was not dependable enough to present as a supported feature.

The product framing is not generic photo transfer. PhoneSnap is for the AI-assisted UI development loop: take a real-device screenshot and drag it into an agent.

## Chosen Path

Use ImageCaptureCore with a trusted iPhone connected by USB:

1. macOS sees the iPhone as a camera-class device.
2. PhoneSnap opens an ImageCaptureCore session.
3. New camera-roll items arrive through delegate callbacks.
4. The app filters likely screenshots, downloads them, saves them, copies them to the clipboard, and presents the floating thumbnail.

## Notes

The probe targets remain useful for local investigation:

- `ICProbe` checks whether ImageCaptureCore can see the plugged-in iPhone.
- `UsbmuxdProbe` inspects Apple's usbmuxd device list. It is research-only and does not enable a supported wireless path.
- `WIRELESS.md` records the next viable wireless direction: a small iOS companion app, not the removed QR/Gist shortcut flow.
