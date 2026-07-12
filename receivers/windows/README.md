# PhoneSnap for Windows

PhoneSnap for Windows is a hardware-unverified Windows 11 beta receiver for the
stable local upload protocol in [`docs/PROTOCOL.md`](../../docs/PROTOCOL.md).
The implemented iPhone workflow in this milestone is explicit and local:

1. Start `PhoneSnap.Windows.exe`.
2. Allow it through Windows Firewall on **Private networks only** if prompted.
3. Open **Open iPhone Upload Page...** from the PhoneSnap tray icon.
4. If the setup dialog lists several network addresses, choose the Wi-Fi or
   Ethernet network shared with the iPhone.
5. Scan the locally generated QR code with the iPhone Camera.
6. In Safari, select one or more screenshots and upload them.

Safari converts browser-decodable input to PNG, checks the converted PNG
against the 32 MiB limit, and uploads it as a raw `image/png` request. Each
accepted image is decoded and normalized in a short-lived worker process,
saved under `Pictures\PhoneSnap`, placed on the Windows clipboard as both an
image and a file, and added to a topmost draggable recent-images panel.

The portable tests and both RID cross-builds pass on the macOS development
host, but the physical Windows+iPhone checklist has not run yet, so this is not
a supported release claim. It is also not automatic USB capture and it does
not install an iOS Shortcut.
See [`WINDOWS_RESEARCH.md`](../../docs/WINDOWS_RESEARCH.md) and the
[`WpdProbe`](../../tools/windows/WpdProbe/README.md) for the hardware gate that
must pass before Windows+iPhone USB can be advertised.

## Requirements

- Windows 11 x64 or Arm64 (both cross-build; each remains beta until physically
  verified on that architecture)
- .NET 10 SDK only when building from source; published builds are
  self-contained
- An iPhone and PC on the same trusted local network

The receiver uses plain HTTP because the iPhone cannot pin a locally generated
certificate. It binds all IPv4 interfaces and relies on Windows Firewall for
profile scope. Allow it on Private networks only, preferably limited to the
local subnet, and do not use it on public or otherwise untrusted Wi-Fi.

## Build and test

From `receivers/windows`:

```powershell
dotnet restore PhoneSnap.Windows.slnx --locked-mode
dotnet test tests/PhoneSnap.Core.Tests/PhoneSnap.Core.Tests.csproj `
  --configuration Release --no-restore
dotnet build src/PhoneSnap.Windows/PhoneSnap.Windows.csproj `
  --configuration Release --runtime win-x64 --no-restore
dotnet build src/PhoneSnap.Windows/PhoneSnap.Windows.csproj `
  --configuration Release --runtime win-arm64 --no-restore
```

The committed lock graph contains only `win-x64` and `win-arm64`; restoring it
on macOS or Linux does not add the build host's RID. The portable core tests
also run on those hosts with .NET 10. The WinForms, DPAPI, Windows image
decoder, clipboard, QR dialog, and drag UI still require a Windows run.

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

## Network and processing behavior

PhoneSnap ranks active IPv4 candidates by physical/private LAN suitability,
gateway availability, and the Windows effective default-route metric (route
plus interface cost). Likely VPN and virtual adapters rank behind suitable
Wi-Fi and Ethernet interfaces. When more than one candidate remains, the setup
dialog provides an explicit selector and regenerates the setup URL and QR code
for the selected address.

PNG normalization runs by relaunching `PhoneSnap.Windows.exe` in a dedicated
worker mode for each image. Request cancellation, the 30-second deadline, or
receiver shutdown terminates that worker process tree, so a synchronous
Windows decoder cannot keep the receiver or shutdown blocked indefinitely.
Worker input, output, and diagnostics are bounded, and no destination file is
committed until the returned PNG passes validation.

**Copy address** uses the same bounded clipboard retry policy as received
images. If another process keeps the clipboard busy, PhoneSnap reports that
the address was not copied instead of failing through the UI event loop.

## Current limitations

- Safari selection is manual; taking a screenshot does not notify Windows.
- Protocol-v1 portable input is PNG. The setup page converts browser-decodable
  non-PNG selections before upload and rejects a converted PNG over 32 MiB. If
  an HDR HEIC cannot be decoded by Safari, switch iPhone screen capture to SDR
  and retry.
- Windows-specific UI and physical iPhone behavior still require manual
  hardware verification; CI cannot validate the firewall or phone picker.
