# iPhone setup — Send Screenshot to Mac (wireless fallback)

> **You probably don't need this if your iPhone is usually plugged into your Mac during dev work.** The cable path (just plug in, take a screenshot) works with **zero iPhone setup** via Apple's ImageCaptureCore framework. This doc is the wireless fallback for when the phone isn't docked.

The wireless path uses an iOS Shortcut to POST screenshots to the Mac app over your LAN. Total setup ≈ 2 minutes, one-time. After that, the Shortcut can be triggered by Back Tap, Action Button, Share Sheet, or anything else that runs a Shortcut on iOS.

## What you need before starting

- iPhone and Mac on the **same Wi-Fi network** (most home / office networks; some guest / café networks use AP isolation that blocks LAN-to-LAN traffic).
- The ScreenshotCatch app **running on Mac**. Click the menu bar icon — the first item is the URL you'll paste into the Shortcut. Two variants are shown:
  - `http://Yourname-MacBook-Pro.local:8472/screenshot` — **prefer this**, the `.local` hostname survives DHCP IP changes when you move between networks.
  - `http://192.168.x.y:8472/screenshot` — IP fallback, useful if your network blocks mDNS.

## Step 1 — Build the Shortcut

1. On iPhone, open **Shortcuts**.
2. Tap **+** (top right).
3. Tap the title at the top → rename to `Send Screenshot to Mac`.
4. Tap **Add Action**. Search `latest screenshots`. Tap the **Get Latest Screenshots** action. Leave count at **1**.
5. Tap **Add Action**. Search `contents of URL`. Tap **Get Contents of URL**.
6. On the *Get Contents of URL* card:
   - Tap the URL field and paste your Mac's URL (prefer the `.local` form).
   - Tap **▸** to expand options.
   - **Method**: POST.
   - **Request Body**: Form.
   - Tap **Add new field**:
     - Type: **File**
     - Key: `file`
     - Tap the value pill → from the *Magic Variables* row above the keyboard, pick **Latest Screenshots**.
7. *(Optional)* Add **Show Notification** with body `Sent to Mac` so you get a confirmation buzz.
8. Tap the **ⓘ** at the bottom:
   - Toggle **Show in Share Sheet** ON (lets you trigger from a screenshot's share sheet too).
9. Tap **Done**.

## Step 2 — Bind a trigger (pick one)

### A. Action Button — most reliable, iPhone 15 Pro / 15 Pro Max / 16 series

1. `Settings → Action Button`.
2. Swipe to the **Shortcut** option.
3. Tap **Choose a Shortcut** → pick **Send Screenshot to Mac**.

After taking a screenshot, long-press the Action Button. ~100% reliable since it's a physical button.

> **Note**: this section is based on Apple's documented Action Button → Shortcut binding behavior. We haven't physically tested it on a Pro device (the maintainer's iPhone doesn't have the Action Button). If you have a Pro and try it, please open an issue confirming or reporting any quirks.

### B. AssistiveTouch single tap — most reliable on any iPhone

A small dim dot floats on top of every app; one tap fires the Shortcut. Reliable because it's a visible tap target, not an accelerometer guess.

1. `Settings → Accessibility → Touch → AssistiveTouch` → toggle on.
2. Tap **Customize Top Level Menu…**
3. Set count to **1**, tap the icon, scroll down and pick **Shortcut → Send Screenshot to Mac**.
4. Now: take a screenshot, tap the AssistiveTouch dot once. (You can drag the dot to any corner.)

### C. Back Tap — convenient when it fires

1. `Settings → Accessibility → Touch → Back Tap`.
2. Tap **Double Tap** (or Triple Tap for fewer false positives).
3. Pick **Send Screenshot to Mac** at the bottom.

> Back Tap is accelerometer-based — works most of the time, occasionally misfires through cases. Triple Tap is more deliberate than Double Tap and misses less.

### D. Share Sheet — manual

After taking a screenshot, tap the bottom-left preview, tap **Share**, scroll to **Send Screenshot to Mac**.

## Step 3 — First run, accept the prompts

The first time the Shortcut runs, iOS will prompt:

1. **Allow Shortcuts to access Photos** → tap **Allow Full Access**.
2. **Allow Shortcuts to find and connect to devices on your local network** → tap **OK**.

If you accidentally tapped *Don't Allow*: re-enable in `Settings → Privacy & Security → Local Network → Shortcuts` and `Settings → Privacy & Security → Photos → Shortcuts`.

## Step 4 — Test

1. Take a screenshot (Side Button + Volume Up).
2. Fire your trigger.
3. Mac shows a floating thumbnail in the bottom-right within ~1s.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Shortcut runs but no thumbnail on Mac | Wrong URL | Open Shortcut → verify URL matches the menu-bar item |
| `The connection could not be established` | Mac app not running, or iOS Local Network permission denied | Start Mac app; check `Settings → Privacy & Security → Local Network → Shortcuts` |
| Stale screenshot delivered | Shortcut grabbed cached "latest" | Take a fresh screenshot, re-trigger |
| Works at home, fails at café | AP isolation on the network | Use phone hotspot |
| Worked yesterday, fails today | Mac's IP changed (DHCP lease) | If using IP form, switch to the `.local` form — it auto-resolves |
| HTTP 415 | Image bytes malformed | Verify *Request Body = Form*, field type = File, key = `file` |

## Changing the URL later

Open Shortcuts → tap **Send Screenshot to Mac** → tap the URL pill → edit → **Done**.

## Coming soon

A QR-code pairing flow that ships a pre-built Shortcut with your Mac's URL already baked in — eliminates step 1 entirely. See the README for status.
