# PhoneSnap for Windows

PhoneSnap for Windows is a Windows 11 tray receiver for the stable local
upload protocol in [`docs/PROTOCOL.md`](../../docs/PROTOCOL.md). The supported
iPhone workflow in this milestone is explicit and local:

1. Start `PhoneSnap.Windows.exe`.
2. Allow it through Windows Firewall on **Private networks only** if prompted.
3. Open **Open iPhone Upload Page...** from the PhoneSnap tray icon.
4. Scan the locally generated QR code with the iPhone Camera.
5. In Safari, select one or more screenshots and upload them.

Each accepted image is decoded and normalized to PNG, saved under
`Pictures\PhoneSnap`, placed on the Windows clipboard as both an image and a
file, and added to a topmost draggable recent-images panel.

This is not automatic USB capture and it does not install an iOS Shortcut.
See [`WINDOWS_RESEARCH.md`](../../docs/WINDOWS_RESEARCH.md) and the
[`WpdProbe`](../../tools/windows/WpdProbe/README.md) for the hardware gate that
must pass before Windows+iPhone USB can be advertised.

## Requirements

- Windows 11 x64 or Arm64
- .NET 10 SDK only when building from source; published builds are
  self-contained
- An iPhone and PC on the same trusted local network

The receiver uses plain HTTP because the iPhone cannot pin a locally generated
certificate. Do not use this workflow on public or otherwise untrusted Wi-Fi.

## Build and test

From `receivers/windows`:

```powershell
dotnet restore PhoneSnap.Windows.slnx --locked-mode
dotnet test tests/PhoneSnap.Core.Tests/PhoneSnap.Core.Tests.csproj `
  --configuration Release --no-restore
dotnet build src/PhoneSnap.Windows/PhoneSnap.Windows.csproj `
  --configuration Release --runtime win-x64 --no-restore
```

The portable core tests also run on macOS or Linux with .NET 10. The WinForms,
DPAPI, Windows image decoder, clipboard, QR dialog, and drag UI require a
Windows run.

## Publish portable ZIPs

```powershell
./scripts/publish.ps1
```

The script runs the locked restore and tests, then creates self-contained x64
and Arm64 ZIPs under `artifacts/windows`. These first artifacts are unsigned
portable builds; Authenticode/MSIX signing is a separate release task.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `PHONESNAP_WIRELESS_PORT` | `8472` | LAN receiver port |
| `PHONESNAP_DIR` | `%USERPROFILE%\Pictures\PhoneSnap` | PNG save folder |

Pairing state is stored under `%LOCALAPPDATA%\PhoneSnap`. The bearer token is
encrypted for the current Windows user with DPAPI. Pair IDs and tokens are not
advertised over Bonjour, DNS-SD, or analytics.

## Current limitations

- Safari selection is manual; taking a screenshot does not notify Windows.
- The setup dialog chooses the preferred active LAN IPv4 address. On a PC with
  several active adapters, temporarily disable an unreachable VPN/virtual
  adapter if the iPhone cannot open the page.
- Protocol-v1 portable input is PNG. The setup page converts browser-decodable
  non-PNG selections to PNG before upload. If an HDR HEIC cannot be decoded by
  Safari, switch iPhone screen capture to SDR and retry.
- Windows-specific UI and physical iPhone behavior still require manual
  hardware verification; CI cannot validate the firewall or phone picker.
