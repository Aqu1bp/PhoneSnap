# WIRELESS

PhoneSnap includes a local wireless receiver. Wired USB remains the primary universal automatic workflow because it is still the most reliable way to react to a normal iPhone screenshot without app-specific code.

Wireless has one main fallback sender:

- The Mac app starts a small HTTP receiver while PhoneSnap is running.
- The generated Shortcut is the fallback/manual sender. The user runs it after taking screenshots, and it sends the latest 10 screenshots from Photos.
- The Shortcut asks for the latest 10 screenshots and posts each image as a separate upload.
- The Mac saves each wireless upload, updates pasteboard to the latest upload, and presents a floating **Recent from iPhone** batch panel instead of the wired single thumbnail.
- Embedded dev senders are deprecated/experimental references, not the main product path.

No GitHub/Gist rendezvous, iCloud sync, third-party service, or manual Shortcut configuration is used.

See [DEV_SENDERS.md](DEV_SENDERS.md) for the deprecated/experimental sender package references.

## Shortcut Fallback Setup

1. Launch PhoneSnap on the Mac.
2. Open the PhoneSnap menu bar item.
3. Choose **Set Up Wireless Shortcut...**.
4. Scan the QR code with the iPhone Camera, or copy/open the setup URL.
5. On the iPhone setup page, open `PhoneSnap.shortcut`.
6. Tap Add Shortcut in Shortcuts.
7. Take a screenshot, then run the PhoneSnap Shortcut from Shortcuts, Action Button, Back Tap, Control Center, Home Screen, or another Shortcut trigger.

iOS will still ask the user to add the Shortcut. The first run may also ask for Photos or local-network permission. Existing installed PhoneSnap Shortcuts should be removed and reinstalled from the setup page to get the latest batch behavior.

The deprecated dev sender config menu item is no longer shown. Dev senders can still use the same upload contract for experiments, but they are not part of the main setup flow.

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

`POST /api/v1/upload/<pairId>` accepts either a raw PNG/JPEG body or `multipart/form-data` with an image/file part. The request body limit is 32 MB.

Uploads should authenticate with:

```text
Authorization: Bearer <token>
```

The `Authorization` header is the only accepted credential. Query-string tokens are rejected so tokens cannot leak into URL logs or browser history. The listener is intentionally not advertised over Bonjour: the pair ID acts as a capability for downloading the token-embedding Shortcut, so it is distributed only through the QR code / setup URL. See [SECURITY.md](../SECURITY.md) for the full threat model.

The upload contract is intentionally unchanged for the generated Shortcut and deprecated dev sender experiments:

```text
POST /api/v1/upload/<pairId>
Authorization: Bearer <token>
Content-Type: image/png
```

## Pairing Data

PhoneSnap stores two values in `UserDefaults`:

- `pairId`: short stable random ID used in setup/upload paths.
- `token`: high-entropy bearer token used to authorize uploads.

The pair ID is not treated as the only secret. Existing installed Shortcuts keep working across Mac app restarts because both values persist, but older installed Shortcuts should be reinstalled to get batch upload behavior. Dev sender experiments should receive these values from local debug configuration and should not commit or persist real tokens.

## Network Addresses

The setup window shows:

- A primary `.local` hostname setup URL for QR setup.
- A current LAN IPv4 fallback URL when one is available.

The user should not need to type the route, method, headers, or body. If `.local` name resolution is blocked on the network, the fallback URL can be copied manually.

## Limitations

- USB remains the only universal automatic sender.
- Shortcut wireless is not automatic. The user must run the PhoneSnap Shortcut after taking screenshots.
- Wireless Shortcut is batch-oriented and opens the **Recent from iPhone** panel instead of the wired single-thumbnail panel.
- Dev senders are deprecated/experimental and no longer exposed in the main menu.
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
