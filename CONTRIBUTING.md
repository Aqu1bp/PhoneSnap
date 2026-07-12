# Contributing

Thanks for your interest in PhoneSnap!

## Building

```bash
swift build            # debug build of all targets
swift test             # parser, resolver, process, and bridge unit tests
./scripts/build-app.sh # release build wrapped into PhoneSnap.app
./scripts/smoke-test.sh # wireless receiver smoke test after swift build
swift run PhoneSnap    # run from source with logs on stderr
```

Requires macOS 13+ and Xcode 15+ / Swift 5.9+.

The Windows receiver uses .NET 10. From `receivers/windows`, restore the locked
packages, run `dotnet test`, then build the WinForms host for `win-x64` or
`win-arm64`. See [the Windows receiver guide](receivers/windows/README.md) for
the exact commands.

## Testing

There is no automated hardware end-to-end test — the wired paths require a
real trusted iPhone or an authorized Android device, and the Windows Safari
path requires a real Windows desktop, iPhone, firewall, and LAN. Before opening
a PR that touches the capture or wireless pipeline, run the relevant Swift or
.NET suite, then walk through the applicable sections of
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

- Keep the macOS app dependency-free (AppKit + system frameworks only), and
  keep Windows dependencies minimal, pinned, and locked.
- iPhone USB is the primary automatic path, Android ADB is an explicit capture
  path, and wireless is a fallback. Don't regress an existing capture path to
  improve another.
- Read [SECURITY.md](SECURITY.md) before changing the wireless receiver —
  in particular, nothing may broadcast or serve the pair ID or token beyond
  the existing QR/setup-URL flow.
- Manual Safari upload is the implemented Windows+iPhone beta. Keep it marked
  hardware-unverified until its physical test plan passes, and keep WPD
  labelled experimental until the separate hardware gate in
  [docs/WINDOWS_RESEARCH.md](docs/WINDOWS_RESEARCH.md) passes.
- The `senders/` packages are deprecated experimental references; changes
  there are low priority.
