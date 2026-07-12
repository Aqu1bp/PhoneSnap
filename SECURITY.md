# Security

PhoneSnap is a local developer tool. This document describes its threat model
so users can decide whether the wireless mode is appropriate for their network.

## Local device modes

The supported macOS wired USB path uses Apple's ImageCaptureCore framework and
opens no network listeners of its own. Screenshots never leave the machine.

Android capture launches the locally installed `adb` executable directly with
an argument array, never through a shell. PhoneSnap does not log complete ADB
serials or manage debugging authorization. Its periodic `adb devices -l`
invocation may cause the ADB client to start ADB's shared loopback server, and
that server may use its own mDNS discovery for wireless-debugging devices.
PhoneSnap does not explicitly configure or stop the ADB daemon. If the user
enables ADB wireless debugging, Android's ADB security and network exposure
apply independently of PhoneSnap's HTTP receiver.

Automatic Windows+iPhone USB capture is not part of the Windows app. The
separate WPD probe uses documented Windows Portable Devices APIs for hardware
research, but its driver-dependent behavior has not passed the promotion gate
in [`docs/WINDOWS_RESEARCH.md`](docs/WINDOWS_RESEARCH.md). Running the Windows
Safari beta does not run that probe or access an iPhone over USB.

## Wireless mode threat model

While the app runs, it listens for plain HTTP on the LAN (port `8472` by
default). Protections and their limits:

- **Pair ID as capability.** The setup page and Shortcut download routes are
  gated only by knowledge of the random pair ID in the URL. The pair ID is
  distributed exclusively through the QR code / setup URL shown by the desktop
  app. The listener is intentionally **not** advertised over Bonjour or
  DNS-SD, because anyone who can fetch a setup response can obtain material
  that authorizes uploads. On macOS that material is embedded in the generated
  Shortcut. On Windows it is embedded only in the returned Safari page's
  in-memory JavaScript.
- **Bearer token.** Uploads require `Authorization: Bearer <token>` with a
  32-byte random token, compared in constant time. Query-string tokens are not
  accepted.
- **No TLS.** Traffic is plain HTTP on the local network. Anyone who can
  observe your LAN traffic (open Wi-Fi, hostile router) can capture the token.
  Do not use wireless mode on untrusted networks; wired mode is unaffected.
- **Impact of token compromise.** An attacker with the token can push images
  to the receiver. Uploaded images are written to the save folder and copied
  to the clipboard, so treat a compromised token as a clipboard-injection risk
  on either desktop platform and rotate it using the guidance below.
- **Resource limits.** Uploads are capped at 32 MB, decoded dimensions are
  capped at 50 million pixels, authentication happens before body buffering,
  only four simultaneous connections are admitted, and incomplete headers time
  out after 5 seconds. Windows applies a linked 30-second deadline across body
  reading, the processing queue, and decode/storage. Windows performs each
  synchronous GDI+ normalization in a short-lived worker mode of the same
  executable; request cancellation, deadline expiry, and receiver shutdown
  terminate the worker process tree. Worker standard input, output, and
  diagnostics are bounded, returned bytes are revalidated, and cancellation is
  checked again before a file is committed. Completed normalization and storage
  run serially, so their memory use is bounded.
  The macOS receiver may evict an older unauthenticated header-waiting session;
  the Windows Kestrel host instead stops admitting connections at its cap.
- **Windows Safari setup page.** The Windows page has a nonce-restricted
  Content Security Policy, permits network requests only to its own origin,
  and does not put the token in a URL, browser storage, filename, analytics, or
  log. The token still appears in the page response and in each plain-HTTP
  `Authorization` header, so a LAN observer can recover it. Files are selected
  explicitly by the user; the page cannot watch Photos in the background. It
  checks the converted PNG against the 32 MiB limit and sends a raw
  `image/png` body, so multipart framing cannot push an otherwise accepted PNG
  beyond the request cap.
- **macOS signing route resource use.** The Shortcut download route spawns a
  `/usr/bin/shortcuts sign` subprocess and is gated only by the pair ID.
  Only one signing job is admitted at a time; concurrent requests receive
  `503`. The subprocess is capped by a 30-second timeout, the HTTP request has
  a 40-second outer deadline, and signed bytes are cached per upload URL.
- **Credential storage.** On macOS, the pair ID and token persist in
  `UserDefaults` (not the Keychain), readable by processes running as that
  user. On Windows, pairing state lives under `%LOCALAPPDATA%\PhoneSnap` and
  the token is encrypted with DPAPI `CurrentUser`; processes running as the
  same Windows user can still ask DPAPI to decrypt it. Neither design protects
  against a process already acting with the user's authority.
- **Windows firewall scope.** Allow the Windows receiver only on **Private**
  network profiles, never public ones. PhoneSnap ranks likely physical,
  private Wi-Fi/Ethernet candidates ahead of VPN and virtual adapters and uses
  the Windows effective default-route metric (route plus interface cost) as a
  tie-breaker, but the setup dialog's explicit address choice does not narrow
  the listener or firewall rule.
- **Windows interface scope.** The beta Kestrel listener binds all IPv4
  interfaces (`0.0.0.0`) so it can survive DHCP and adapter changes; the QR
  advertises only the ranked or user-selected LAN address. PhoneSnap does not
  override an existing Windows Firewall rule. Restrict the inbound rule to the
  Private profile and, where practical, the local subnet; remove any old rule
  that allows PhoneSnap on Public networks or every remote address.

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

For Windows, quit PhoneSnap, delete the pairing state, and relaunch:

```powershell
Remove-Item "$env:LOCALAPPDATA\PhoneSnap\pairing.json"
```

The next launch creates a new pair ID and DPAPI-protected token. Any open setup
page using the old credentials stops authorizing uploads.

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
