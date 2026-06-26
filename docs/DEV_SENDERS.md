# Dev Senders

PhoneSnap has three sender paths. They all feed the existing Mac receiver and thumbnail pipeline.

## Direction

- USB remains the universal automatic mode. A trusted iPhone connected to the Mac is still the primary path because it works for any app on the device without phone-side code.
- Shortcut remains the fallback/manual wireless mode. It is useful when USB is unavailable, but the user must install and run the generated Shortcut.
- Automatic wireless is foreground-app-only. It comes from a debug sender embedded in the app being built, so it can react while that app is active.
- All wireless senders use the existing Mac receiver contract:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png or image/jpeg
```

Raw PNG/JPEG bodies and multipart image uploads are accepted by the Mac receiver. New senders should prefer raw PNG unless their platform makes multipart simpler.

## Snapshot Source

Dev senders should snapshot the app UI directly instead of looking up the newest Photos asset.

`UIApplication.userDidTakeScreenshotNotification` is the recommended iOS trigger for native senders, but the payload should be a rendered snapshot of the foreground active app window. Photos lookup is avoided by default because it needs Photos permission and can race against camera-roll writes.

This means automatic wireless captures the UI of the instrumented app, not arbitrary screenshots from other apps.

## Debug Only

Dev senders must be debug-only:

- Do not start in release builds.
- Do not store the PhoneSnap token in the package or app bundle.
- Use **Copy Dev Sender Config** in the PhoneSnap Mac menu, then pass `uploadURL` and `token` from local debug configuration, developer settings, or a temporary launch argument.
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
