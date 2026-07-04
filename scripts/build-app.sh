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

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
  <string>0.1.0</string>
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
