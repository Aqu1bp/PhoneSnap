# Contributing

Thanks for your interest in PhoneSnap!

## Building

```bash
swift build            # debug build of all targets
./scripts/build-app.sh # release build wrapped into PhoneSnap.app
swift run PhoneSnap    # run from source with logs on stderr
```

Requires macOS 13+ and Xcode 15+ / Swift 5.9+.

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

## Guidelines

- Keep the app dependency-free (AppKit + system frameworks only).
- Wired USB is the primary path; wireless is a fallback. Don't regress wired
  behavior to improve wireless.
- Read [SECURITY.md](SECURITY.md) before changing the wireless receiver —
  in particular, nothing may broadcast or serve the pair ID or token beyond
  the existing QR/setup-URL flow.
- The `senders/` packages are deprecated experimental references; changes
  there are low priority.
