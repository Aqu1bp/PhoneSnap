# Android setup

PhoneSnap can capture the current display of an Android phone through Android
Debug Bridge (ADB). This path is local, requires no PhoneSnap app on the phone,
and works over either USB debugging or an existing ADB wireless-debugging
connection.

Unlike iPhone ImageCaptureCore delivery, Android ADB capture is user-triggered:
choose **Capture Android Screen** from the PhoneSnap menu. Android does not
provide a portable desktop event when the hardware screenshot buttons are
pressed.

## Install ADB

Install Android SDK Platform Tools with Android Studio's SDK Manager, from the
[official Platform Tools download](https://developer.android.com/tools/releases/platform-tools),
or with Homebrew:

```bash
brew install android-platform-tools
```

PhoneSnap checks these locations in order:

1. `PHONESNAP_ADB_PATH`
2. `$ANDROID_SDK_ROOT/platform-tools/adb`
3. `$ANDROID_HOME/platform-tools/adb`
4. `~/Library/Android/sdk/platform-tools/adb`
5. each directory in `PATH`
6. `/opt/homebrew/bin/adb` and `/usr/local/bin/adb`

The explicit override is useful for a nonstandard SDK location:

```bash
PHONESNAP_ADB_PATH=/path/to/platform-tools/adb open ./PhoneSnap.app
```

## USB debugging

1. On Android, enable **Developer options** by tapping **Build number** seven
   times in Settings.
2. Open Developer options and enable **USB debugging**.
3. Connect the phone to the Mac with USB.
4. Unlock the phone and accept **Allow USB debugging** for this Mac.
5. Verify the connection:

   ```bash
   adb devices -l
   ```

6. Open PhoneSnap. Its menu should say `Android: <model> ready`.
7. Put the UI you want to capture on the phone, then choose **Capture Android
   Screen**.

PhoneSnap streams a PNG directly from `adb exec-out screencap -p`, saves and
copies it, and shows the normal draggable single-thumbnail panel. It does not
create a second screenshot in the Android photo library.

If several capture-ready devices are connected, the menu shows a submenu with
their model names and shortened serial suffixes.

## Wireless debugging

Android 11 and later can establish ADB over Wi-Fi. Pair/connect the phone using
Android's Wireless debugging settings and `adb pair` / `adb connect`. Once the
device appears as `device` in `adb devices -l`, PhoneSnap treats it like a USB
ADB device.

PhoneSnap does not enable wireless debugging, scan the LAN, store ADB pairing
codes, or restart the shared ADB server.

## Troubleshooting

| PhoneSnap status | What to do |
| --- | --- |
| `adb not found` | Install Platform Tools or set `PHONESNAP_ADB_PATH`. |
| `no device` | Connect the phone, enable USB debugging, and run `adb devices -l`. |
| `allow USB debugging` | Unlock the phone and accept its RSA authorization prompt. |
| `device offline` | Reconnect USB, or reconnect the wireless ADB session. |
| `capture failed` | Run `adb exec-out screencap -p > screen.png` in Terminal and inspect the ADB error. |

ADB is optional. A missing or broken ADB installation never prevents PhoneSnap's
iPhone USB or wireless Shortcut paths from starting.
