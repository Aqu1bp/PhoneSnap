# PhoneSnapSender for Apple iOS

Reference debug sender for native UIKit apps.

Deprecated/experimental: dev senders are not the current PhoneSnap happy path. Prefer wired USB automatic mode or the generated Wireless Shortcut Batch fallback unless you are explicitly experimenting with foreground-app debug capture.

It observes `UIApplication.userDidTakeScreenshotNotification` in DEBUG builds, snapshots the foreground active `UIWindow`, PNG-encodes it, and uploads it to the existing PhoneSnap Mac receiver:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png
```

It does not read Photos and does not store the token.

## Install

Add this folder as a local Swift Package in Xcode:

```text
senders/apple-ios
```

Then link the `PhoneSnapSender` product to your app target.

## Use

Call it from debug-only app startup code:

```swift
#if DEBUG
import PhoneSnapSender

PhoneSnapSender.start(
    uploadURL: URL(string: "http://MacBook.local:8472/api/v1/upload/<pairId>")!,
    token: "<debug token>"
)
#endif
```

Stop it when needed:

```swift
#if DEBUG
PhoneSnapSender.stop()
#endif
```

Pass the URL and token from local debug configuration. Do not commit real tokens.

## Required iOS Config

For local HTTP upload to a Mac, add:

- `NSLocalNetworkUsageDescription`
- `NSAppTransportSecurity` with `NSAllowsLocalNetworking` set to `true`

`NSBonjourServices` is only needed if your app implements Bonjour discovery. This package does not.
