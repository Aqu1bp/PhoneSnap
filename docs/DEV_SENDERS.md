# Dev Senders

Dev senders are deprecated/experimental for now. The product path is USB automatic first and Wireless Shortcut Batch fallback second. The sender packages remain in the repo as references, but they are not exposed as a main setup flow.

## Direction

- USB remains the universal automatic mode. A trusted iPhone connected to the Mac is still the primary path because it works for any app on the device without phone-side code.
- Shortcut is the fallback/manual wireless mode. It is useful when USB is unavailable, but the user must install and run the generated Shortcut. The current Shortcut sends the latest screenshot batch and the Mac shows **Recent from iPhone**.
- Automatic wireless dev senders are foreground-app-only experiments. They come from debug code embedded in the app being built, so they can react while that app is active.
- All wireless senders use the existing Mac receiver contract:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png or image/jpeg
```

Raw PNG/JPEG bodies and multipart image uploads are accepted by the Mac receiver. Experimental senders should prefer raw PNG unless their platform makes multipart simpler.

## Snapshot Source

Dev senders should snapshot the app UI directly instead of looking up the newest Photos asset.

`UIApplication.userDidTakeScreenshotNotification` is the recommended iOS trigger for native senders, but the payload should be a rendered snapshot of the foreground active app window. Photos lookup is avoided by default because it needs Photos permission and can race against camera-roll writes.

This means automatic wireless captures the UI of the instrumented app, not arbitrary screenshots from other apps.

## Debug Only

Dev senders must be debug-only:

- Do not start in release builds.
- Do not store the PhoneSnap token in the package or app bundle.
- The PhoneSnap menu no longer includes **Copy Dev Sender Config**. If experimenting, obtain the upload URL and token from local development configuration only.
- Do not add Bonjour discovery or network scanning unless a future feature explicitly designs that pairing flow.

## iOS App Configuration

Apps using local HTTP upload to the Mac need these `Info.plist` keys:

- `NSLocalNetworkUsageDescription`: explains why the debug build connects to a local Mac receiver.
- `NSAppTransportSecurity` with `NSAllowsLocalNetworking` set to `true`: allows local HTTP such as `http://MacBook.local:8472/...`.
- `NSBonjourServices`: only required if/when a sender implements Bonjour discovery. It is not required for direct upload URLs.

Example:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Debug builds can send UI snapshots to PhoneSnap on your Mac.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

## Sender Packages

- `senders/apple-ios`: Swift Package reference implementation for native UIKit apps.
- `senders/expo`: minimal Expo/React Native prototype using a root view ref.
- `senders/react-native` and `senders/flutter`: API stubs for future implementations.

These packages are not currently maintained as a happy-path product feature. Prefer the generated Wireless Shortcut Batch fallback unless explicitly experimenting with foreground-app debug capture.
