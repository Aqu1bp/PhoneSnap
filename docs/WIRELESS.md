# WIRELESS

PhoneSnap now includes an optional wireless Shortcut path. Wired USB remains the primary workflow because it is still the most reliable way to react to a normal iPhone screenshot without any phone-side setup.

The wireless path is local-only:

- The Mac app starts a small HTTP receiver while PhoneSnap is running.
- The menu item **Set Up Wireless Shortcut...** opens a setup window with a normal HTTP setup URL and QR code.
- The setup page serves a generated, signed `PhoneSnap.shortcut` file for iOS to open in Shortcuts.
- The Shortcut sends the latest screenshot from Photos to the Mac receiver.
- The upload uses the same `ImageStore`, pasteboard, and thumbnail delivery path as wired mode.

No GitHub/Gist rendezvous, iCloud sync, third-party service, or manual Shortcut configuration is used.

## Setup Flow

1. Launch PhoneSnap on the Mac.
2. Open the PhoneSnap menu bar item.
3. Choose **Set Up Wireless Shortcut...**.
4. Scan the QR code with the iPhone Camera, or copy/open the setup URL.
5. On the iPhone setup page, open `PhoneSnap.shortcut`.
6. Tap Add Shortcut in Shortcuts.
7. Take a screenshot, then run the PhoneSnap Shortcut from Shortcuts, Action Button, Back Tap, Control Center, Home Screen, or another Shortcut trigger.

iOS will still ask the user to add the Shortcut. The first run may also ask for Photos or local-network permission.

## Routes

PhoneSnap listens on `PHONESNAP_WIRELESS_PORT` when set, or port `8472` by default.

```text
GET  /pair/<pairId>
GET  /pair/<pairId>/PhoneSnap.shortcut
POST /api/v1/upload/<pairId>
```

`GET /pair/<pairId>` returns a small HTML setup page with a normal link to `PhoneSnap.shortcut`. The QR code points to this HTTP page, not to an undocumented `shortcuts://import-shortcut` deep link.

`GET /pair/<pairId>/PhoneSnap.shortcut` generates the Shortcut bytes with the current upload URL and persisted token baked in, then signs them with:

```bash
/usr/bin/shortcuts sign --mode anyone
```

If signing fails, the route returns a clear `500` response and logs the error instead of crashing the app.

`POST /api/v1/upload/<pairId>` accepts either a raw image body or `multipart/form-data` with an image/file part. The request body limit is 32 MB.

Uploads should authenticate with:

```text
Authorization: Bearer <token>
```

The receiver also accepts `?token=<token>` as a fallback for sender compatibility, but the generated Shortcut uses the Authorization header.

## Pairing Data

PhoneSnap stores two values in `UserDefaults`:

- `pairId`: short stable random ID used in setup/upload paths.
- `token`: high-entropy bearer token used to authorize uploads.

The pair ID is not treated as the only secret. Existing installed Shortcuts keep working across Mac app restarts because both values persist.

## Network Addresses

The setup window shows:

- A primary `.local` hostname setup URL for QR setup.
- A current LAN IPv4 fallback URL when one is available.

The user should not need to type the route, method, headers, or body. If `.local` name resolution is blocked on the network, the fallback URL can be copied manually.

## Limitations

- Wireless is not passive. The user must run the PhoneSnap Shortcut after taking a screenshot.
- The iPhone and Mac must be on a network where the iPhone can reach the Mac.
- macOS firewall or another process on the configured port can block the receiver.
- The signed Shortcut generation depends on `/usr/bin/shortcuts`.
- Full end-to-end confidence still requires a real iPhone because Shortcut import, Photos permission, and local-network permission are iOS behaviors.

## Verification

Local receiver checks:

```bash
swift build
PHONESNAP_WIRELESS_PORT=18472 PHONESNAP_DIR=/tmp/phonesnap-test swift run PhoneSnap
curl -i http://127.0.0.1:18472/pair/<pairId>
curl -i -H "Authorization: Bearer <token>" \
  -H "Content-Type: image/png" \
  --data-binary @sample.png \
  http://127.0.0.1:18472/api/v1/upload/<pairId>
```

Expected upload result:

```json
{"ok":true,"bytes":12345}
```
