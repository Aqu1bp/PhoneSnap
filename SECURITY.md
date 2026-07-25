# Security

PhoneSnap is a local developer tool. This document describes its threat model
so users can decide whether the wireless mode is appropriate for their network.

## The listener is always on

PhoneSnap starts its wireless receiver when the app launches, regardless of
which capture mode you use. Cable-only users are running it too.

It binds every interface on port `8472` (override with
`PHONESNAP_WIRELESS_PORT`), so any device on the same LAN can reach it. A
typical home router does not forward that port, so it is not reachable from
the internet unless you have explicitly port-forwarded it.

There is currently no setting to disable the listener. Quitting PhoneSnap
stops it.

## Wired mode

The wired USB path uses Apple's ImageCaptureCore framework. It does not open
a network listener of its own and screenshots never leave the machine — but
the wireless listener described above is still running, so the wireless
threat model applies to you even if you only ever use the cable.

## Wireless mode threat model

Protections and their limits:

- **Pair ID as capability.** The setup page and Shortcut download routes are
  gated only by knowledge of the random pair ID in the URL (9 random bytes,
  12 base64url characters). The pair ID is distributed exclusively through the
  QR code / setup URL shown on the Mac — the listener is intentionally **not**
  advertised over Bonjour, because the generated Shortcut embeds the bearer
  token and anyone who can fetch it can authorize uploads.
- **Bearer token.** Uploads require `Authorization: Bearer <token>` with a
  32-byte random token, compared in constant time. Query-string tokens are not
  accepted.
- **Host binding.** The setup page and the generated Shortcut point at the
  host the request arrived through, but only after that host is checked
  against an allowlist: the Mac's Bonjour hostname, its current IPv4 address,
  `localhost`, `127.0.0.1`, and `::1`, each on the receiver's own port. Any
  other `Host` header falls back to the Bonjour hostname. Without this check,
  a request carrying an attacker-chosen `Host` would yield a signed Shortcut
  that delivered the bearer token and every future screenshot to that address
  — a DNS-rebinding path to credential exfiltration that does not require the
  attacker to be on your network at all.
- **Authentication before buffering.** Upload requests are authenticated
  while headers are parsed, before any request body is read into memory. An
  unauthenticated peer cannot make the receiver buffer a body.
- **Connection limits.** At most 4 concurrent sessions; a new connection may
  evict one that is still waiting for its headers, so idle unauthenticated
  peers cannot starve a real upload. Headers must arrive within 5 seconds and
  the complete request within 30 seconds, after which the receiver responds
  `408` and closes. The header block is capped at 64 KiB (`431` beyond that).
- **Body limits.** Uploads are capped at 32 MiB (33,554,432 bytes), require a
  well-formed `Content-Length` (missing, duplicate, negative, or non-decimal
  values are rejected before a body is read), and must decode as an image
  before being saved. `Transfer-Encoding` other than `identity` is refused
  with `501`.
- **Decoding limits.** Image dimensions are read from the file header and
  rejected above 50,000,000 pixels before any decode is attempted. This bounds
  decompression bombs, where a small compressed file expands to many gigabytes
  in memory. Vector and PDF content is refused rather than rasterized, and
  decoding is serialized so concurrent uploads cannot multiply decoder memory.
- **File writes.** Saved filenames are generated locally from a timestamp and
  never taken from the sender. Each destination is claimed with an exclusive
  rename, so simultaneous saves cannot silently overwrite one another and a
  partially written PNG is never visible at the final path.
- **Logging.** Pair IDs and tokens are redacted from application logs. Request
  paths are logged in a fixed redacted form and unrecognized methods are not
  echoed.
- **No TLS.** Traffic is plain HTTP on the local network. Anyone who can
  observe your LAN traffic (open Wi-Fi, hostile router) can capture the token.
  Do not use wireless mode on untrusted networks; the wired capture path is
  unaffected, though the listener still runs.
- **Impact of token compromise.** An attacker with the token can push images
  to your Mac. Uploaded images are written to the save folder and copied to
  the clipboard, so treat a compromised token as a clipboard-injection risk
  and rotate the credentials as described below.
- **Signing route resource use.** The Shortcut download route spawns a
  `/usr/bin/shortcuts sign` subprocess and is gated only by the pair ID. Only
  one signing run is permitted at a time — concurrent requests receive `503`
  with `Retry-After` — and each run is capped by a 30-second timeout with a
  40-second deadline on the surrounding request. Signed bytes are cached per
  upload URL, token, and batch size, so repeated downloads do not respawn
  subprocesses.
- **Credential storage.** The pair ID and token persist in `UserDefaults`
  (not the Keychain). They are readable by any process running as your user —
  the same trust level as the screenshots folder itself.

## What PhoneSnap does not defend against

- An attacker who can read your LAN traffic. There is no TLS; see above.
- An attacker who obtains the pair ID. It is the only gate on the setup and
  Shortcut download routes. Rotate if you believe it has leaked.
- Any process running as your user. It can read the credentials out of
  `UserDefaults` and the screenshots out of the save folder.
- Malicious image content itself. PhoneSnap bounds decode size, but decoding
  is still performed by the system image frameworks.

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
