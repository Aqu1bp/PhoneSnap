# iPhone setup — Send Screenshot to Mac

This walks through the **one-time setup** on your iPhone. Total time ≈ 2 minutes. Repeat steps 1–3 only if you switch to a different Mac or change the server port.

## What you need before starting

- iPhone and Mac on the **same Wi-Fi network** (no AP isolation; most home routers are fine).
- The ScreenshotCatch app **running on Mac**. The menu bar item will show the URL — it looks like `http://192.168.x.y:8472/screenshot` or `http://Yourname-MacBook-Pro.local:8472/screenshot`. Note that URL down; you will paste it in the Shortcut.

## Step 1 — Build the Shortcut

1. On iPhone, open **Shortcuts**.
2. Tap **+** (top right).
3. Tap the title bar at the top → rename to `Send Screenshot to Mac`.
4. Tap **Add Action**. In the search field type `latest screenshots`. Tap the **Get Latest Screenshots** action to add it. Leave the count at **1**.
5. Tap **Add Action**. Search `contents of URL`. Tap **Get Contents of URL** to add it.
6. On the *Get Contents of URL* card:
   - Tap the URL field and paste your Mac's URL exactly: `http://<MAC-IP>:8472/screenshot`
   - Tap the **▸** to expand the options.
   - **Method**: change from GET to **POST**.
   - **Request Body**: change to **Form**.
   - Tap **Add new field**:
     - Type: **File**
     - Key: `file`
     - Tap the value pill and from the *Magic Variables* bar at the top of the keyboard, pick **Latest Screenshots**.
7. *(Optional but recommended for confirmation)* Tap **Add Action**. Search `notification`. Add **Show Notification**, type `Sent to Mac` in the body.
8. Tap the **ⓘ** info icon at the bottom of the editor:
   - Toggle **Show in Share Sheet** ON.
   - Below it, *Share Sheet Types*: ensure **Images** is the only one needed (it's enabled by default).
9. Tap **Done** (top right) to save.

## Step 2 — Bind a trigger (pick one)

### A. Back Tap (most iPhones)
1. `Settings → Accessibility → Touch → Back Tap`.
2. Tap **Double Tap** (or Triple Tap).
3. Scroll to the bottom and choose **Send Screenshot to Mac**.

Now: take a screenshot, double-tap the back of the phone, the thumbnail pops on the Mac.

### B. Action Button (iPhone 15 Pro, 15 Pro Max, 16 series)
1. `Settings → Action Button`.
2. Swipe to the **Shortcut** option.
3. Tap **Choose a Shortcut** → pick **Send Screenshot to Mac**.

Now: take a screenshot, long-press the Action Button.

### C. Share Sheet (fallback / for any iPhone)
After taking a screenshot, tap the bottom-left preview that appears, tap **Share**, scroll to **Send Screenshot to Mac**. (Or in Photos → tap a screenshot → Share → Send Screenshot to Mac.)

## Step 3 — First run, accept the prompts

The very first time the Shortcut runs, iOS will prompt:

1. **Allow Shortcuts to access Photos** → tap **Allow Full Access** (Limited Access works too if you only screenshot, but Full is simpler).
2. **Allow Shortcuts to find and connect to devices on your local network** → tap **OK**.

These prompts only appear once. If you accidentally tap *Don't Allow*: `Settings → Privacy & Security → Local Network → Shortcuts → ON` and `Settings → Privacy & Security → Photos → Shortcuts → All Photos`.

## Step 4 — Test

1. Take any screenshot (Side Button + Volume Up).
2. Fire your trigger (double-tap back / Action Button / Share Sheet).
3. The Mac shows a floating thumbnail in the bottom-right within ~1s.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Shortcut runs but no thumbnail on Mac | Wrong URL in shortcut | Open the Shortcut → check the URL matches the menu-bar item exactly |
| `The connection could not be established` in Shortcuts | Mac app not running, OR Local Network blocked | Start the Mac app; check `Settings → Privacy & Security → Local Network → Shortcuts` |
| Thumbnail appears but on a stale/old screenshot | Shortcut grabbed cached "latest" | Take a new screenshot and re-trigger; sometimes the first screenshot after permission needs one more tap |
| Works on home Wi-Fi but not at a coffee shop | AP isolation on public Wi-Fi blocks LAN-to-LAN | Use phone hotspot, or tether |
| Worked yesterday, fails today | Mac's DHCP IP changed | Use the `*.local` hostname URL in the Shortcut; or update the IP to whatever the menu bar shows now |
| Shortcut shows `403 / 415` | Image data malformed; rare | Re-trigger; verify *Request Body = Form* and File field key = `file` |

## Changing the URL later

Open Shortcuts → tap **Send Screenshot to Mac** → tap the URL pill → edit → tap *Done*.
