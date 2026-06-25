# WIRELESS

PhoneSnap's supported workflow is wired: plug in a trusted iPhone, take a hardware screenshot, drag the Mac thumbnail into a coding agent.

Wireless is still worth exploring, but it needs a different design than the removed QR/Shortcut/Gist path.

Research conclusion: the hard part is not taking the screenshot. iOS already does that, and PhoneSnap's wired mode already proves the screenshot-to-thumbnail workflow. The hard part is getting screenshot bytes from the phone to the Mac over Wi-Fi without adding setup friction.

Apple-supported APIs can give us a good Mac receiver and local-network transfer path. What they do not give us is a zero-install, zero-integration way for a Mac-only app to pull new iPhone screenshots over Wi-Fi. Some process on the phone, or an Apple sync service such as iCloud Photos, has to send the image.

## What We Need

The ideal behavior for PhoneSnap's core audience is:

1. iPhone is not plugged in.
2. Developer runs their own Flutter/RN/native app in debug mode.
3. Developer takes a normal iPhone screenshot while that app is foregrounded.
4. A Mac thumbnail appears quickly.
5. User drags it into Codex, Cursor, Claude, ChatGPT, Slack, or an issue.

The hard part is step 3 -> 4. A Mac app cannot passively receive screenshot bytes over Wi-Fi unless something on the phone sends them. The product question is which sender is acceptable: Shortcut, companion app, debug SDK/plugin, iCloud Photos, or developer tooling. Each one adds a different kind of friction.

## Options

| Option | Viable? | Notes |
|--------|---------|-------|
| Wired USB capture | Current default | Still the lowest-friction and most universal path. Works without installing or integrating anything on the phone. |
| Mac receiver + sender contract | Best infrastructure spike | Build the reusable local receiver first: Bonjour, pairing token, upload endpoint, thumbnail creation. This proves the wireless transport independent of the eventual phone-side sender. |
| Shortcuts + LAN upload | Best no-app-code sender candidate | Lets the user send the latest screenshot without modifying their Flutter/RN app, but setup, local-network permissions, and reliable Mac discovery are the weak points. The old QR/Gist version was too fragile. |
| Dev-only app SDK/plugin + Bonjour | Optional, not primary | Technically strong for teams willing to add debug-only code, but it is too much product friction for the default PhoneSnap story. It also captures or re-reads from the app context, which is not the same as a universal hardware-screenshot pipeline. |
| iOS companion app + Bonjour + App Intent | Wrong primary fit | Adds a separate install and still cannot passively observe screenshots while the developer is using their app under test. |
| iOS companion app with PhotoKit observer/history | Poor primary fit | The companion app can observe Photos only while active and can catch up across launches, but it is not active while the developer is using their app under test. |
| Xcode/CoreDevice wireless capture | Not a product path | Xcode can see paired devices and Device Hub can capture from physical devices, but installed command-line tools do not expose a stable screenshot command for physical devices. This would be "capture current device screen from Mac", not "react to iPhone screenshot". |
| iCloud Photos polling | Poor fit | Too much latency, sync can pause, and it depends on user iCloud settings. |
| AirDrop / Universal Clipboard | Poor fit | Manual and interrupts the agent feedback loop. |

## Recommended Prototype

Build the wireless transport first, not a Flutter/RN plugin first:

- Mac app advertises `_phonesnap._tcp` with Bonjour.
- Mac app shows a short pairing code and creates a temporary pairing token.
- Mac app exposes one upload contract, for example `POST /screenshots`, accepting PNG/JPEG plus token.
- Any sender that can reach the Mac can upload an image and get the same draggable thumbnail behavior as wired mode.
- Validate this with `curl` from another machine or phone browser before building any phone-side product surface.
- Then test the lowest-friction iPhone sender candidate: a manually installed Shortcut that sends the latest screenshot to the paired Mac.

Sender candidates:

- Flutter/RN/native plugin: possible later for teams that accept debug-only code in their app.
- iOS companion app: possible later only if arbitrary-app support becomes important.
- Shortcut: still the best candidate if the goal is no app-code integration, but it needs a better pairing/discovery story than the removed QR/Gist flow.

Expected result:

- Transport layer: likely achievable.
- Zero-friction wireless screenshot capture: not proven.
- Plugin-based sender: technically possible, but not the default product bet.
- Product default remains wired until a low-friction sender is proven.

## Mac-Side Changes Needed

If we prototype this, restore a local receiver, but keep it clean:

- Bonjour service: `_phonesnap._tcp`
- Small HTTP endpoint or Network.framework connection for screenshot upload
- Shared pairing token generated by the Mac app
- Sender includes the token in requests
- Mac only accepts requests from paired senders

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
