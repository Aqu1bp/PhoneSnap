#!/usr/bin/env bash
# Build ScreenshotCatch as a launchable macOS .app bundle.
# Run from the project root: ./scripts/build-app.sh
# Output: ./ScreenshotCatch.app
set -euo pipefail

cd "$(dirname "$0")/.."
echo "→ swift build -c release"
swift build -c release

APP="ScreenshotCatch.app"
BIN_SRC=".build/release/ScreenshotCatch"
if [ ! -f "$BIN_SRC" ]; then
  echo "ERROR: $BIN_SRC not found — release build failed?"
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_SRC" "$APP/Contents/MacOS/ScreenshotCatch"
chmod +x "$APP/Contents/MacOS/ScreenshotCatch"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>ScreenshotCatch</string>
  <key>CFBundleDisplayName</key>
  <string>ScreenshotCatch</string>
  <key>CFBundleIdentifier</key>
  <string>local.aquib.screenshotcatch</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>ScreenshotCatch</string>
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
echo "  binary: $(du -h "$APP/Contents/MacOS/ScreenshotCatch" | cut -f1)"
echo
echo "Run: open ./$APP"
echo "Or move to /Applications: mv $APP /Applications/"
