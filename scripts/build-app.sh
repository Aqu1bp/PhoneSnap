#!/usr/bin/env bash
# Build PhoneSnap as a launchable macOS .app bundle.
# Run from the project root: ./scripts/build-app.sh
# Output: ./PhoneSnap.app
set -euo pipefail

cd "$(dirname "$0")/.."
echo "→ swift build -c release"
swift build -c release

APP="PhoneSnap.app"
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

# Version reported in Finder and the About panel. Taken from the most recent
# git tag so a release bundle cannot claim a version it is not, with an
# override for building outside a tagged checkout.
# `|| true` matters: CI checks out without tags, and under `set -e` a failing
# git describe aborts the script before the fallback below can apply.
VERSION="${PHONESNAP_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-0.0.0-dev}"
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
  <string>dev.phonesnap.PhoneSnap</string>
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
  <key>NSHumanReadableCopyright</key>
  <string>Local-only utility, no telemetry.</string>
</dict>
</plist>
PLIST

echo "→ built $APP"
echo "  binary: $(du -h "$APP/Contents/MacOS/PhoneSnap" | cut -f1)"
echo
echo "Run: open ./$APP"
echo "Or move to /Applications: mv $APP /Applications/"
