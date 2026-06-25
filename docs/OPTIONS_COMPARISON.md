# OPTIONS_COMPARISON

| Option | Result | Notes |
|--------|--------|-------|
| USB cable + ImageCaptureCore | **Chosen** | Reliable enough for the current app. No iPhone setup beyond Trust This Computer. |
| iOS Shortcut + LAN HTTP | Removed | Theoretically useful, but unreliable in practice and easy to misconfigure. |
| QR pairing / signed Shortcut install | Removed | Added setup complexity without producing a dependable wireless path. |
| GitHub Gist rendezvous | Removed | Solved changing IPs, but introduced a third-party dependency and still depended on the unreliable wireless flow. |
| iCloud Photos polling | Rejected | Latency is too high and sync behavior is outside app control. |
| AirDrop | Rejected | Manual and not automatable for the intended workflow. |
| iOS companion app + PhotoKit/App Intent | Research | Most plausible future wireless path. Needs real-device testing because iOS background execution may prevent truly automatic screenshot delivery. |

Current product direction: keep PhoneSnap wired-only until there is a wireless design that can be tested and trusted end to end.
