# PhoneSnap Windows WPD capability probe

`WpdProbe` is a phase-1, metadata-only, read-only diagnostic for the unanswered Windows + iPhone USB
questions. It uses Microsoft's public Windows Portable Devices (WPD) COM API
to determine what the installed Apple/Windows driver actually exposes on a
specific computer.

This is not a screenshot receiver or a production-promotion gate. It does not download image resources, write
properties, create objects, delete objects, invoke device commands, or talk to
private Apple Mobile Device APIs. The device is opened with
`WPD_CLIENT_DESIRED_ACCESS = GENERIC_READ` before any content API is used.
It therefore cannot validate resource transfer, PNG/HEIC decoding, image safety,
save/clipboard/UI delivery, device reconnect handling, or long-running
locked/unlocked reliability. Those require a later probe and real hardware tests.

The probe answers four separate questions:

1. Does the trusted iPhone appear in normal WPD enumeration?
2. Can a read-only WPD client enumerate DCIM-like/image metadata?
3. Does the driver advertise `WPD_EVENT_OBJECT_ADDED`, and is it broadcast?
4. When a screenshot is saved, does the driver emit an event or expose a new
   object to bounded polling while the connection stays open?

Microsoft documents event notification as optional for WPD drivers. A
successful event subscription by itself is therefore not proof that Apple's
driver will report newly saved screenshots.

## Safety and privacy

- The probe requests read-only access and contains no WPD write or resource
  transfer code.
- Enumeration is bounded to depth 8 and 5,000 objects by default. Hard CLI
  limits are depth 16 and 50,000 objects.
- Device names and all per-object baseline metadata are omitted by default;
  default output is aggregate data plus session-local pseudonyms for new items.
- Raw PnP IDs, WPD object IDs, and persistent IDs are omitted by default.
  Output uses session-local values such as `device-1` and `object-42` instead.
- `--show-ids` intentionally reveals those raw IDs. They may contain stable or
  serial-like identifiers; do not attach that output to a public issue.
- `--show-metadata` adds device names, filenames, path hints, dates, sizes, and
  dimensions. Review such a JSONL capture before sharing it.
- Existing image bytes are never opened or copied. `catalog_object` records are
  metadata from the initial baseline, not imported files.

## Requirements

- Windows 11 on the machine connected to the iPhone.
- Visual Studio 2022/2026 or Build Tools with **Desktop development with C++**,
  CMake, and a current Windows 10/11 SDK.
- The current Apple Devices app installed from Microsoft Store so the supported
  Apple Windows device components are present.
- A data-capable USB cable and a physical iPhone or iPad.

No WDK or third-party library is required. `PortableDeviceGUIDs.lib` and the
WPD headers are part of the Windows SDK.

## Build

From the repository root in a Developer PowerShell for Visual Studio:

```powershell
cmake -S tools/windows/WpdProbe -B out/WpdProbe -A x64
cmake --build out/WpdProbe --config Release
```

The executable is normally:

```text
out\WpdProbe\Release\WpdProbe.exe
```

For an Arm64-native build, use an Arm64 Visual Studio developer environment
and the generator architecture supported by that installation.

## Exact hardware procedure

Use one iPhone at a time for the first run.

1. Update Windows, Apple Devices, and iOS. Restart Windows after installing or
   updating Apple Devices if the phone has not appeared before.
2. Connect the iPhone with a data-capable cable, unlock it, and accept **Trust
   This Computer** / **Allow** on the phone.
3. Confirm Microsoft Photos can list the connected iPhone for import. Then
   close Photos and the Apple Devices window so another application is not
   actively browsing the same device. Do not stop Apple services.
4. Run a discovery/baseline pass:

   ```powershell
   .\out\WpdProbe\Release\WpdProbe.exe --observe-seconds 0 |
     Tee-Object -FilePath wpd-discovery.jsonl
   ```

5. The Apple candidate check uses device metadata and Apple's USB vendor ID,
   but false negatives remain possible. If needed, repeat discovery with
   `--show-metadata`, note the appropriate `device_index`, and select that
   index explicitly. An explicit `--device-index N` overrides the candidate
   heuristic; `--all-devices` is not required.
6. Test events without timer polling:

   ```powershell
   .\out\WpdProbe\Release\WpdProbe.exe `
     --device-index N --observe-seconds 90 --poll-interval 0 |
     Tee-Object -FilePath wpd-event-only.jsonl
   ```

7. Wait for `observation_started`. Take a normal hardware screenshot on the
   iPhone and make sure it is saved to Photos. On iOS 26, finish or dismiss the
   full-screen screenshot editor in a way that saves the screenshot. Keep the
   phone unlocked until the observation finishes.
8. Repeat with a two-second polling fallback:

   ```powershell
   .\out\WpdProbe\Release\WpdProbe.exe `
     --device-index N --observe-seconds 90 --poll-interval 2 |
     Tee-Object -FilePath wpd-with-polling.jsonl
   ```

9. Repeat steps 6-8 after choosing each iPhone screenshot format under
   **Settings > General > Screen Capture**:

   - SDR screenshots are PNG.
   - HDR screenshots are HEIC on iOS 26.

   The probe reports metadata only, so an HDR object may have `format:
   "OTHER"` while still reporting `content_type: "IMAGE"` or a `.HEIC`
   filename. A future receiver must separately prove it can decode that data.
10. Repeat once with the phone allowed to lock during the observation, and
    once after unplug/reconnect, to record whether the open session remains
    usable. These are separate from event support.

If the baseline hits a bound before reaching DCIM, retry deliberately with a
larger—but still bounded—value, for example `--max-depth 12 --max-objects
15000`. Do not start with the hard maximum.

## Reading the JSON lines

Each stdout line is one complete JSON object with `event` and `timestamp`.
Diagnostics and HRESULT values are also JSON, so the output is safe to process
line by line even when the driver fails midway.

| Record | Interpretation |
| --- | --- |
| `device_discovered` | A normal WPD device. `apple_candidate` is a metadata/Apple USB-vendor heuristic, not proof that the device is an iPhone. |
| `device_opened` | The driver accepted a `GENERIC_READ` WPD connection. |
| `device_open_error` | Unlock/trust the phone, close competing import software, and inspect `hresult`. |
| `supported_events_summary` | What the driver claims. `object_added_advertised: false` means event-only automatic detection is not available through this WPD session. |
| `supported_event` | Includes the event GUID and whether the driver marks it as broadcast/available to `Advise`. |
| `event_subscription_started` | `Advise` succeeded. This does **not** prove object-added delivery. |
| `catalog_object` | Existing interesting metadata used to seed snapshot A. Emitted only with `--show-metadata`; it is not a newly captured screenshot. |
| `catalog_summary` | Shows coverage, metadata failures, and whether a bound truncated the catalog. A `fatal_hresult` commonly indicates lock/trust/session access failure. |
| `wpd_event` with `OBJECT_ADDED` | Direct runtime evidence that this driver/session emitted the WPD event. |
| `new_catalog_object` | A pseudonymous object identity not present in the baseline. Default output includes classification; `--show-metadata` additionally exposes dimensions, filename, and timing. |
| `rescan_summary` with `reason: "wpd_event"` | An event triggered a catalog refresh, even if the event did not include an object ID. |
| `rescan_summary` with `reason: "poll_timer"` | Timer polling, rather than a WPD event, discovered the change. |
| `rescan_summary` with `reason: "post_subscribe_gap_check"` | Snapshot B found something added between snapshot A and the completed `Advise` call. |

The strongest USB result is all of the following in the event-only run:

1. `object_added_advertised: true`
2. `object_added_broadcast: true`
3. a runtime `wpd_event` named `OBJECT_ADDED`
4. a matching image `new_catalog_object`

If only the polling run produces `new_catalog_object`, a bounded polling
adapter is feasible but true event-driven delivery was not demonstrated. If
neither run sees the saved screenshot, do not infer that Windows+iPhone USB is
implementable from WPD on that configuration.

One successful phone/Windows/iOS combination does not prove all Apple driver
versions. Record Windows build, Apple Devices version, iPhone model, iOS
version, screenshot format, and locked/unlocked state beside each result.

## Options and exit codes

```text
--observe-seconds N  Event observation window, 0-600 (default 30)
--poll-interval N    Re-enumeration interval, 0-60; 0 disables timer polling
--max-depth N        Content-tree depth, 1-16 (default 8)
--max-objects N      Objects visited per catalog, 1-50000 (default 5000)
--device-index N     Probe only zero-based WPD enumeration index N
--all-devices        Permit probing devices not recognized by the Apple heuristic
--show-metadata      Include device names and per-object metadata
--show-ids           Include sensitive raw PnP/object/persistent IDs
--help               Print usage
```

| Exit | Meaning |
| ---: | --- |
| 0 | At least one selected device opened and completed both the supported-event query and a minimum catalog path. |
| 1 | COM/WPD manager initialization or device enumeration failed. |
| 2 | Invalid command-line arguments. |
| 3 | `--device-index` did not exist in this enumeration. |
| 4 | No Apple candidate or explicitly permitted device was selected. |
| 5 | Device(s) were selected, but none completed the minimum capability/catalog path. |

## Primary API references

- [IPortableDevice::Open and `GENERIC_READ`](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevice-open)
- [Enumerating WPD devices](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/enumerating-devices)
- [Official Portable Devices COM API sample](https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/portable-devices-com-api/)
- [Retrieving supported events](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/retrieving-the-events-supported-by-a-device)
- [`IPortableDevice::Advise`](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevice-advise)
- [WPD event constants](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/event-constants)
- [WPD object properties](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/object-properties)
- [Apple's Windows USB import prerequisites](https://support.apple.com/en-us/120267)
- [Apple's iOS 26 SDR/PNG and HDR/HEIC screenshot formats](https://support.apple.com/guide/iphone/iph2d2500abc/26/ios/26)
