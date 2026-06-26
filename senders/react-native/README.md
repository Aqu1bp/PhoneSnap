# PhoneSnap React Native Sender

Intended API for a future non-Expo React Native package:

```ts
startPhoneSnap({ uploadUrl, token, rootRef });
stopPhoneSnap();
```

The sender should be debug-only, snapshot `rootRef` instead of reading Photos, and upload to the existing Mac receiver:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png
```

Do not commit tokens. `NSLocalNetworkUsageDescription` and `NSAppTransportSecurity.NSAllowsLocalNetworking` are required for local HTTP on iOS. `NSBonjourServices` is only needed if discovery is added later.
