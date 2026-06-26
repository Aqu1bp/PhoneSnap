# PhoneSnap Flutter Sender

Deprecated/experimental: dev senders are not the current PhoneSnap happy path. Prefer wired USB automatic mode or the generated Wireless Shortcut Batch fallback unless you are explicitly experimenting with foreground-app debug capture.

Intended API for a future Flutter package:

```dart
PhoneSnapSender.start(uploadUrl: uploadUrl, token: token);
PhoneSnapSender.stop();
```

The sender should be debug-only, capture the active app widget tree with a `RepaintBoundary` or equivalent, avoid Photos permission, and upload to the existing Mac receiver:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png
```

Do not commit tokens. `NSLocalNetworkUsageDescription` and `NSAppTransportSecurity.NSAllowsLocalNetworking` are required for local HTTP on iOS. `NSBonjourServices` is only needed if discovery is added later.
