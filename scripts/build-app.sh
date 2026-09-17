#!/usr/bin/env bash
# Build PhoneSnap as a launchable macOS .app bundle.
# Run from the project root: ./scripts/build-app.sh
# Output: ./PhoneSnap.app
set -euo pipefail

cd "$(dirname "$0")/.."
if ! command -v pkg-config >/dev/null || ! pkg-config --exists libimobiledevice-1.0 libusbmuxd-2.0 openssl; then
  echo "Install build dependencies first: brew install pkgconf libimobiledevice openssl@3"
  exit 1
fi
echo "→ swift build -c release"
swift build -c release

APP="${PHONESNAP_APP_NAME:-PhoneSnap}.app"
BUNDLE_ID="${PHONESNAP_BUNDLE_ID:-dev.phonesnap.PhoneSnap}"
BIN_SRC=".build/release/PhoneSnap"
if [ ! -f "$BIN_SRC" ]; then
  echo "ERROR: $BIN_SRC not found — release build failed?"
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_SRC" "$APP/Contents/MacOS/PhoneSnap"
chmod +x "$APP/Contents/MacOS/PhoneSnap"
cp Resources/PhoneSnap.icns "$APP/Contents/Resources/PhoneSnap.icns"

# Version reported in Finder and the About panel.
#
# Only a build from a clean checkout sitting exactly on a tag gets a bare
# version number. Anything else is marked -dev, because an app that claims to
# be 0.1.2 while carrying unreleased commits is indistinguishable from the
# release in a bug report.
#
#   on tag, clean       0.1.2
#   on tag, dirty       0.1.2-dev+dirty
#   5 commits past tag  0.1.2-dev+5.gabc1234
#   ...and dirty        0.1.2-dev+5.gabc1234.dirty
#   no tags (CI)        0.0.0-dev
#
# `|| true` matters: CI checks out without tags, and under `set -e` a failing
# git describe aborts the script before the fallback can apply.
if [ -n "${PHONESNAP_VERSION:-}" ]; then
  VERSION="$PHONESNAP_VERSION"
else
  BASE="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  BASE="${BASE#v}"
  if [ -z "$BASE" ]; then
    VERSION="0.0.0-dev"
  else
    # --long always renders as <tag>-<count>-g<sha>, so reading the last two
    # fields stays correct even if a tag itself contains a hyphen.
    LONG="$(git describe --tags --long 2>/dev/null || true)"
    COUNT="$(printf '%s' "$LONG" | awk -F- '{print $(NF-1)}')"
    SHA="$(printf '%s' "$LONG" | awk -F- '{print $NF}')"
    DETAIL=""
    [ "${COUNT:-0}" != "0" ] && DETAIL="$COUNT.$SHA"
    [ -n "$(git status --porcelain 2>/dev/null)" ] && DETAIL="${DETAIL:+$DETAIL.}dirty"
    VERSION="$BASE${DETAIL:+-dev+$DETAIL}"
  fi
fi
echo "→ bundle version $VERSION"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>PhoneSnap</string>
  <key>CFBundleDisplayName</key>
  <string>PhoneSnap</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleIconFile</key>
  <string>PhoneSnap</string>
  <key>CFBundleExecutable</key>
  <string>PhoneSnap</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>PhoneSnap connects to your trusted iPhone on Wi-Fi to receive new screenshots.</string>
  <key>NSBonjourServices</key>
  <array><string>_apple-mobdev2._tcp</string></array>
  <key>NSHumanReadableCopyright</key>
  <string>Local-only utility, no telemetry.</string>
</dict>
</plist>
PLIST

# Relocate libraries before sealing the complete bundle, including Info.plist
# and Resources. The helper signs libraries and the app, then verifies both.
python3 scripts/bundle-native-libs.py "$APP"

echo "→ built $APP"
echo "  binary: $(du -h "$APP/Contents/MacOS/PhoneSnap" | cut -f1)"
echo "  signature: $(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature/{print $2}')"
echo
echo "Run: open ./$APP"
echo "Or move to /Applications: mv $APP /Applications/"
