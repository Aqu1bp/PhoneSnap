# Contributing

Thanks for your interest in PhoneSnap!

## Building

```bash
brew install pkgconf libimobiledevice
swift build            # debug build of all targets
./scripts/build-app.sh # release build wrapped into PhoneSnap.app
./scripts/smoke-test.sh # wireless receiver smoke test after swift build
swift run PhoneSnap    # run from source with logs on stderr
```

Swift sources target macOS 13+ with Xcode 15+ / Swift 5.9+. Native Homebrew libraries may require a newer macOS; the bundle script records the highest dependency minimum in Info.plist. Build on the oldest supported deployment OS and validate there. The local Tahoe preview is macOS 26+. The app bundles all transitive dylibs and upstream license notices, then verifies ad-hoc signatures and relocation.

## Testing

There is no automated end-to-end test — the wired path requires a real,
trusted, USB-connected iPhone. Before opening a PR that touches the capture
or wireless pipeline, walk through the relevant sections of
[docs/TEST_PLAN.md](docs/TEST_PLAN.md) and note in the PR what you verified
on hardware.

The wireless receiver can be exercised without an iPhone:

```bash
PHONESNAP_WIRELESS_PORT=18472 PHONESNAP_DIR=/tmp/phonesnap-test swift run PhoneSnap
curl -i http://127.0.0.1:18472/pair/<pairId>
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the current direction and small issues that
are good places to start.

## Guidelines

- Keep the app dependency-free (AppKit + system frameworks only).
- Wired USB is the primary path; wireless is a fallback. Don't regress wired
  behavior to improve wireless.
- Read [SECURITY.md](SECURITY.md) before changing the wireless receiver —
  in particular, nothing may broadcast or serve the pair ID or token beyond
  the existing QR/setup-URL flow.
- The `senders/` packages are deprecated experimental references; changes
  there are low priority.
