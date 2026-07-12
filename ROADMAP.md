# Roadmap

PhoneSnap's north star is simple: make real phone screenshots easy to hand to coding agents while keeping each desktop app small, local-first, and understandable.

## Now

- Keep wired USB capture reliable across macOS and iOS versions.
- Keep user-triggered Android ADB capture reliable across devices and SDK releases.
- Make the wireless Shortcut fallback easier to install and debug.
- Improve first-run and troubleshooting docs for non-Swift users.
- Package GitHub Releases so people can try PhoneSnap without building it.

## Next

- Add notarization and a cleaner first-launch path.
- Add a Homebrew Cask once releases are stable.
- Improve multi-display thumbnail placement and accessibility.
- Add richer diagnostics for ImageCaptureCore device state.
- Make the wireless setup page clearer when `.local` hostnames fail.

## Later

- Explore a signed helper or hardened runtime setup if sandboxing becomes practical.
- Add a lightweight in-app preferences window for save location, wireless port, and batch size.
- Revisit direct app-embedded senders if foreground-app workflows prove useful again.
- Prototype Windows Portable Devices event delivery before committing to a Windows+iPhone wired adapter.

## Good First Issues

- Improve a troubleshooting entry after reproducing it on real hardware.
- Add a focused smoke-test assertion for an existing wireless error case.
- Tighten README wording where a new user has to reread a step.
- Improve accessibility labels in AppKit views.
- Add a small diagnostic log message that would have helped debug a real failure.
