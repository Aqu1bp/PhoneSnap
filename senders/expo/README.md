# PhoneSnap Expo Sender

Minimal debug sender prototype for Expo apps.

Deprecated/experimental: dev senders are not the current PhoneSnap happy path. Prefer wired USB automatic mode or the generated Wireless Shortcut Batch fallback unless you are explicitly experimenting with foreground-app debug capture.

It listens for screenshots with `expo-screen-capture`, snapshots your app root view with `react-native-view-shot`, and uploads a multipart PNG file to the existing PhoneSnap Mac receiver.

## Install

Install the peer dependencies in your app:

```bash
npx expo install expo-screen-capture
npx expo install react-native-view-shot
```

Then import this package from `senders/expo` or copy it into your app while it is still a prototype.

## Use

Attach a ref to your root view:

```tsx
import { useEffect, useRef } from 'react';
import { View } from 'react-native';
import { startPhoneSnap, stopPhoneSnap } from './senders/expo/src';

export function App() {
  const rootRef = useRef<View>(null);

  useEffect(() => {
    startPhoneSnap({
      uploadUrl: 'http://MacBook.local:8472/api/v1/upload/<pairId>',
      token: '<debug token>',
      rootRef
    });

    return stopPhoneSnap;
  }, []);

  return <View ref={rootRef} style={{ flex: 1 }}>{/* app */}</View>;
}
```

`startPhoneSnap` is guarded by `__DEV__`. Pass the URL and token from local debug configuration and do not commit real tokens.

## iOS Config

This package includes `app.plugin.js` for Expo config plugins:

```json
{
  "expo": {
    "plugins": ["./senders/expo/app.plugin.js"]
  }
}
```

The plugin sets:

- `NSLocalNetworkUsageDescription`
- `NSAppTransportSecurity.NSAllowsLocalNetworking`

`NSBonjourServices` is intentionally not set because this prototype does not perform Bonjour discovery.
