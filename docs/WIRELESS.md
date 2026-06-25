# WIRELESS

PhoneSnap's supported workflow is wired: plug in a trusted iPhone, take a hardware screenshot, drag the Mac thumbnail into a coding agent.

Wireless is still worth exploring, but it needs a different design than the removed QR/Shortcut/Gist path.

Research conclusion: because PhoneSnap is mainly for developers building their own Flutter, React Native, or native mobile apps with coding agents, a separate installable phone companion app is the wrong primary model. The better wireless model is a dev-only sender embedded in the app under test.

Apple-supported APIs can give us a good wireless transfer path. The missing piece is a global trigger for arbitrary apps, but that matters less when the app being screenshotted is the developer's own debug build. That app can detect screenshot events while foregrounded, capture its own UI, and send the image to the Mac.

## What We Need

The ideal behavior for PhoneSnap's core audience is:

1. iPhone is not plugged in.
2. Developer runs their own Flutter/RN/native app in debug mode.
3. Developer takes a normal iPhone screenshot while that app is foregrounded.
4. A Mac thumbnail appears quickly.
5. User drags it into Codex, Cursor, Claude, ChatGPT, Slack, or an issue.

The hard part only applies to arbitrary apps. iOS does not expose a reliable public "screenshot was just taken anywhere on the device" background event to unrelated apps. But the foreground app can receive `UIApplication.userDidTakeScreenshotNotification` after the user takes a screenshot. That gives a debug SDK a clean trigger without needing Photos access or a separate iOS app.

## Options

| Option | Viable? | Notes |
|--------|---------|-------|
| Dev-only app SDK/plugin + Bonjour | Best v1 | Add PhoneSnap to the Flutter/RN/native app being built. In debug builds, detect screenshot events or expose a dev gesture, capture the current UI, and send it to the Mac over LAN. |
| Wired USB capture | Current default | Still the lowest-friction and most universal path. Works without integrating anything into the app under test. |
| iOS companion app + Bonjour + App Intent | Wrong primary fit | Useful only if PhoneSnap needs to support screenshots from arbitrary apps. For app builders, it adds install/setup friction and cannot observe screenshots while the user's app is foregrounded. |
| iOS companion app with PhotoKit observer/history | Poor primary fit | The companion app can observe Photos only while active and can catch up across launches, but it is not active while the developer is using their app under test. |
| Shortcuts + LAN HTTP | Prototype only | Requires user setup, Local Network permission, stable routing, and a trigger gesture. The old QR/Gist version made this feel automatic, but it was too fragile. |
| Xcode/CoreDevice wireless capture | Not a product path | Xcode can see paired devices and Device Hub can capture from physical devices, but installed command-line tools do not expose a stable screenshot command for physical devices. This would be "capture current device screen from Mac", not "react to iPhone screenshot". |
| iCloud Photos polling | Poor fit | Too much latency, sync can pause, and it depends on user iCloud settings. |
| AirDrop / Universal Clipboard | Poor fit | Manual and interrupts the agent feedback loop. |

## Recommended Prototype

Build a small dev-only PhoneSnap sender for the app under test:

- Mac app advertises `_phonesnap._tcp` with Bonjour.
- App under test includes a debug-only PhoneSnap package/plugin.
- Sender discovers the Mac with Network.framework and pairs once with a short code.
- On iOS, sender listens for `UIApplication.userDidTakeScreenshotNotification` while the app is foregrounded.
- Sender captures the current app UI directly, not from Photos.
- Sender uploads the image to the paired Mac, which creates the draggable thumbnail.
- Release builds exclude or disable the sender.

Framework-specific shape:

- Flutter: provide a `PhoneSnapCapture` wrapper using `RepaintBoundary` / `RenderRepaintBoundary.toImage`, plus a small platform channel for screenshot-event detection and Bonjour upload.
- React Native: provide a dev-only package using a native screenshot-event listener and either native view capture or `react-native-view-shot`-style capture.
- Native iOS: provide a small Swift package around screenshot notification, window snapshotting, Bonjour pairing, and upload.

Expected result:

- Automatic for the developer's app while it is foregrounded in debug mode: likely achievable.
- No Photos permission needed for the primary path.
- No separate iOS app install.
- No support for arbitrary third-party apps unless the wired mode or a separate manual flow is used.

## Mac-Side Changes Needed

If we prototype this, restore a local receiver, but keep it clean:

- Bonjour service: `_phonesnap._tcp`
- Local Network usage description and declared Bonjour service type in the app under test
- Small HTTP endpoint or Network.framework connection for screenshot upload
- Shared pairing token generated by the Mac app
- App under test discovers Mac over Bonjour and includes the token in requests
- Mac only accepts requests from paired debug builds

This is different from the removed QR/Gist flow: no GitHub dependency, no hardcoded IP, no generated Shortcut, no unauthenticated LAN upload.

## Research Notes

- Apple's Shortcuts automation docs describe event, travel, communication, and setting triggers, but not a screenshot-created trigger: https://support.apple.com/guide/shortcuts/intro-to-personal-automation-apd690170742/ios
- Shortcuts can run from the Action Button on supported iPhones: https://support.apple.com/guide/shortcuts/run-shortcuts-with-the-action-button-apdfea15680b/ios
- App Intents let app actions appear in Shortcuts, Siri, Spotlight, controls, and other system surfaces: https://developer.apple.com/documentation/appintents
- UIKit posts `UIApplication.userDidTakeScreenshotNotification` when a person takes a screenshot on the device: https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification
- Flutter's `RenderRepaintBoundary.toImage` can capture the current state of a render object and its children: https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html
- Expo documents `react-native-view-shot` as a way to capture a React Native view as an image: https://docs.expo.dev/versions/latest/sdk/captureRef/
- PhotoKit supports observing library changes and change history, useful for a companion app prototype: https://developer.apple.com/documentation/photokit/observing-changes-in-the-photo-library and https://developer.apple.com/videos/play/wwdc2022/10132/
- `PHAssetMediaSubtype.photoScreenshot` identifies screenshot assets: https://developer.apple.com/documentation/photos/phassetmediasubtype/photoscreenshot
- Background execution is opportunistic and not guaranteed for immediate regular work: https://developer.apple.com/videos/play/wwdc2025/227/
- Bonjour discovery/listening is supported through Network.framework: https://developer.apple.com/documentation/network/nwbrowser and https://developer.apple.com/documentation/network/nwlistener
- Xcode Device Hub supports physical-device capture workflows, but that is a developer-device capture model rather than an iPhone-screenshot event model: https://developer.apple.com/documentation/xcode/capturing-screenshots-and-videos-from-devices
