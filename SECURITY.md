# Security

PhoneSnap is a local developer tool. This document describes its threat model
so users can decide whether the wireless mode is appropriate for their network.

## Wired mode

The wired USB path uses Apple's ImageCaptureCore framework and opens no
network listeners of its own. Screenshots never leave the machine.

## Wireless mode threat model

While the app runs, it listens for plain HTTP on the LAN (port `8472` by
default). Protections and their limits:

- **Pair ID as capability.** The setup page and Shortcut download routes are
  gated only by knowledge of the random pair ID in the URL. The pair ID is
  distributed exclusively through the QR code / setup URL shown on the Mac —
  the listener is intentionally **not** advertised over Bonjour, because the
  generated Shortcut embeds the bearer token and anyone who can fetch it can
  authorize uploads.
- **Bearer token.** Uploads require `Authorization: Bearer <token>` with a
  32-byte random token, compared in constant time. Query-string tokens are not
  accepted.
- **No TLS.** Traffic is plain HTTP on the local network. Anyone who can
  observe your LAN traffic (open Wi-Fi, hostile router) can capture the token.
  Do not use wireless mode on untrusted networks; wired mode is unaffected.
- **Impact of token compromise.** An attacker with the token can push images
  to your Mac. Uploaded images are written to the save folder and copied to
  the clipboard, so treat a compromised token as a clipboard-injection risk
  and quit/relaunch guidance below applies.
- **Body limits.** Uploads are capped at 32 MB and must decode as an image
  before being saved.
- **Signing route resource use.** The Shortcut download route spawns a
  `/usr/bin/shortcuts sign` subprocess and is gated only by the pair ID.
  Signing is serialized on one queue, capped by a 30-second timeout, and the
  signed bytes are cached per upload URL, so repeated requests cannot pile up
  subprocesses or stall the receiver.
- **Credential storage.** The pair ID and token persist in `UserDefaults`
  (not the Keychain). They are readable by any process running as your user —
  the same trust level as the screenshots folder itself.

## Rotating credentials

Delete the stored pairing values and relaunch to generate fresh ones
(existing installed Shortcuts stop working and must be reinstalled):

```bash
defaults delete dev.phonesnap.PhoneSnap PhoneSnapWirelessPairID 2>/dev/null
defaults delete dev.phonesnap.PhoneSnap PhoneSnapWirelessToken 2>/dev/null
```

When running the unbundled binary (`swift run PhoneSnap`), the defaults domain
is the executable name instead — remove the matching
`PhoneSnapWirelessPairID` / `PhoneSnapWirelessToken` keys from `PhoneSnap`.

## Reporting a vulnerability

Please do not open a public issue for security-sensitive reports.

Use GitHub private vulnerability reporting:

<https://github.com/Aqu1bp/PhoneSnap/security/advisories/new>

Expected response:

- Acknowledgement within 7 days.
- Status update within 30 days, even if the fix is still in progress.
- Public disclosure after a fix is available, unless the reporter and
  maintainer agree that a different timeline is safer.

If GitHub's private reporting flow is unavailable, contact the maintainer
through their GitHub profile and include only enough detail to establish a
private channel.
