# Automatic Wi-Fi capture (development preview)

Use **Set Up Automatic Wi-Fi…** from the menu. A new phone needs a cable once, unlocked, with Trust approved in Finder and on the phone. The setup screen selects one device and enables wireless access. An already discoverable paired device can be selected over Wi-Fi. Keep both devices on the same LAN, unplug, wait for Ready, and save screenshots normally.

Only the explicit Enable Wireless action writes the phone’s `com.apple.mobile.wireless_lockdown/EnableWifiConnections` preference through an existing trusted USB session. The app never initiates pairing, resets trust, or changes photo files. Wi-Fi capture reads AFC through Apple's Network connection, with a direct Bonjour/TCP fallback when that connection is absent or fails to open. Both routes authenticate the selected phone using its existing pairing. Turning the watcher off leaves the phone’s Apple Wi-Fi setting and trust intact.

First-run automatic capture and the legacy upload receiver both default off independently. Enabling automatic capture does not start the HTTP upload receiver. Its controls remain under **Shortcut & Developer Uploads**.

## Behavior and limits

- Initial catalog entries are skipped before Ready. Capture after Ready; startup scanning is not historical import.
- New pending paths remain retryable across temporary disconnects during an enabled session.
- Individual failures back off while other captures continue; transport failures reconnect.
- A connected cable takes precedence for the same phone. USB and Wi-Fi share a capture identity to avoid saving the same capture twice.
- Capture dates determine panel order. DCIM folder/filename sequence breaks ties for captures in the same EXIF second, independently of receive order.
- Complete PNG/HEIF structure, stable remote size/modification time, and image decoding are required before presentation. Downloads are capped at 32 MB.
- Screenshot recognition uses phone-screen geometry and absence of camera exposure metadata. It is a heuristic; matching saved images can be included, and full-page PDFs or unusual dimensions may be omitted.
- Discovery depends on the phone remaining available. Unlock when reconnecting if needed. Sleep/wake retries are implemented; overnight standby, power consumption, network changes, and large libraries are not yet extensively validated.
- Disabling or restarting begins a new baseline; captures from the disabled period are not imported. Source images remain on the phone.

## Build and verification

Install development dependencies with `brew install pkgconf libimobiledevice openssl@3`, then run `swift test`, `./scripts/build-app.sh`, and `./scripts/smoke-test.sh`. The app bundles transitive native dylibs, rewrites their paths, includes license notices, and verifies ad-hoc signatures. Python is used by developer packaging and local transport tests, not by the shipped app.

The Swift deployment target is macOS 13. The final bundle uses the highest minimum version among its native libraries. Homebrew bottles built for Tahoe require macOS 26, so this local preview is 26+. Build and test dependency binaries on an older OS before distributing to that OS; do not lower the plist value to hide an incompatible library.

An explicit, read-only native hardware check is available:

```sh
PHONESNAP_LIVE_DEVICE_TEST=1 swift test --filter AutomaticWirelessTests/testNativeWiFiConnectionWhenExplicitlyRequested
```

It requires a visible, paired iPhone and no cable; it lists image paths without downloading existing images or writing to the device. Ordinary test runs skip it.

## Preview test results — 17 September 2026

- The earlier standalone prototype received 5/5 deliberate screenshots on iOS 26.5. Native existing-trust Network connection and DCIM listing passed separately.
- The bundled native app was copied outside the checkout and launched with a separate preview bundle identifier. All six loaded native libraries were verified to come from its own Frameworks folder. Ad-hoc signatures and transitive relocation checks passed.
- The first catalog contained 784 images; all were skipped before Ready. The user enabled capture through the setup screen and confirmed both subsequent screenshots appeared in Recent from iPhone. Native download-through-save took 0.782 and 0.456 seconds; this excludes screenshot-button-to-discovery time.
- The original checkout’s 23 source/binary baseline checksums remain unchanged. The original running app was quit for the preview test; its bundle was preserved.
- Full suite: 31 automated tests passed, with one opt-in hardware test skipped in that run. The hardware test passed separately. Legacy HTTP receiver smoke checks passed.
- Independent review verified same-second ordering, retry isolation, background delivery, stop/setup generation invalidation, and native packaging after corrections.
- USB-to-Wi-Fi capture handoff and actual cross-transport identity matching remain pending. The separate fresh-pairing test below established USB Wi-Fi enablement, renewed trust, unplugged captures and app-restart persistence after delayed discovery recovery. Long standby/network changes remain unverified.

## Fresh-pairing test — 17 September 2026

This was a controlled reset of the same iPhone 15 Plus running iOS 26.5 and the same Mac, not an untouched second Mac. With user approval, only that phone's pairing with this host was removed, its Wi-Fi access was disabled and verified, and PhoneSnap used an empty isolated preferences suite. The Mac pairing-record lookup returned `ENOENT`. No factory or global privacy reset was performed.

- Fresh launch left automatic capture and the legacy HTTP receiver off. Setup remained a menu action. Before Trust, Enable Wireless correctly returned the Trust instruction.
- The user approved Trust. A cable reconnect was needed before the host pairing record appeared; a trusted USB session then succeeded while Wi-Fi remained disabled.
- The first USB Enable Wireless action changed the phone preference but crashed the app: `lockdownd_set_value` consumes its plist argument, and PhoneSnap freed it again. Removed the extra free; independent ownership review confirmed the fix. Rebuilt the portable bundle, disabled Wi-Fi again without removing trust, and repeated the actual UI action. The app stayed open, the user confirmed its cable-connected status, and independent readback verified Wi-Fi enabled. Six automated wireless tests passed; the opt-in Network hardware test was skipped in that run.
- After unplugging, Apple usbmux enumeration returned no Network device. Enabling and applying Finder's initially unchecked Wi-Fi option, cycling the phone's Wi-Fi, and restarting the user-level discovery agent did not immediately restore enumeration.
- A native Bonjour lookup found an advertisement whose authentication tag matched the saved pairing HostID. Direct TCP to lockdown port 62078 authenticated using that existing pairing, returned the expected device identity, and confirmed the phone's advertised instance and enabled Wi-Fi flag. Thus the phone's trust and direct wireless connection worked while the Mac's device list omitted it. The precise host-side cause is unresolved; stale state after re-pairing is a hypothesis.
- A system usbmux service restart was blocked by macOS System Integrity Protection. SIP was left enabled.
- The same preview process later reached Ready through the existing native path, with USB absent and one authenticated Network device. No direct-fallback build or successful system service restart preceded recovery. The first baseline skipped 787 images; two subsequent screenshots arrived and the user confirmed both. Download-through-save took 0.550 and 0.516 seconds, excluding screenshot-button-to-discovery time.
- Restarting the preview with the same test preferences automatically returned to Ready without repeating setup. Its new baseline skipped 789 images, including the two earlier captures. A third screenshot arrived in 0.594 seconds download-through-save and the user confirmed it. The preview was then returned to its usual settings and save directory; only one preview was left running.

At that point the app relied on Apple exposing the phone through usbmux; the direct fallback below was implemented afterward. This reset test passed capture and app-restart persistence after a prolonged discovery delay whose cause remains unresolved. It does not establish consistently seamless onboarding. A second Mac with no previous pairing would help distinguish a first-use issue from this reset-specific state.

## Direct Wi-Fi fallback

The watcher also browses the iPhone's `_apple-mobdev2._tcp` advertisement. It matches the selected pairing's modern authentication tag, or the saved Wi-Fi MAC for older advertisements. Discovery only selects a candidate: the connection must then authenticate with the existing host certificate, pin the device certificate's public key, and verify the device identifier inside TLS before opening photo access. Host credentials stay in memory; they are not copied into PhoneSnap preferences, files, or logs.

The direct route uses lockdown on port 62078 and the AFC port returned by the authenticated session. It enables pinned TLS on AFC when the iPhone requests service TLS. Requests are read-only and share the native route's baseline, pending-file retry, size, image-validation, and capture-identity checks. Socket operations use bounded deadlines and respond to cancellation. A cable still takes precedence. Ready requires a successful photo catalog scan; a saved pairing alone does not mean the phone is reachable.

For a deliberate direct-route hardware test, launch the executable inside the preview bundle with `PHONESNAP_DIRECT_WIFI_ONLY=1`. This developer override skips Apple's Network route but continues to respect USB presence. Remove it for normal use. Do not remove pairing or restart system services to test this fallback.

### Direct-route test — 17 September 2026

- The bundled native preview reached Ready in 4.568 seconds with the iPhone unplugged, unlocked, and the direct-only override enabled. The initial baseline skipped 792 existing images. This measured one successful connection, not a guaranteed maximum.
- Lockdown and AFC both used pinned TLS; the phone requested service TLS. Two subsequent normal-button screenshots arrived and the user confirmed both in Recent from iPhone. Download-through-save took 0.483 and 0.467 seconds, excluding screenshot-button-to-discovery time.
- Restarting with the same preferences reached Ready in 10.397 seconds and skipped the existing catalog. A new screenshot arrived in 0.624 seconds download-through-save and the user confirmed it. Logs also showed recovered connection interruptions, including photo connections that opened but failed before the catalog was ready. These tests demonstrate recovery and capture, not uninterrupted standby or guaranteed connection timing.
- Local transport tests cover fragmented plaintext/TLS reads, a wrong device certificate, truncated responses, prompt cancellation, shared header/body deadlines, malformed AFC framing, and advertisement matching without downgrading invalid modern tags to legacy matching.
- Full suite: 38 passed, one opt-in hardware test skipped. After the final discovery-generation guard, the 13 relevant automated tests passed again, with the same hardware skip. Independent review found no remaining blocker in the tested workflow. Post-read metadata verification has its own bounded operation timeout outside the file-read budget.
- The final bundle passed relocation and signature verification with six bundled libraries. The preview was returned to its usual preferences and save folder, with the test override removed and Shortcut receiver off; it reached Ready through Apple's Network route in 0.217 seconds. The original checkout's 23 baseline source/binary checksums remained unchanged.
