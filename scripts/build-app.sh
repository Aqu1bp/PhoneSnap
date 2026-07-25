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

# Sign the assembled bundle, not just the binary. `swift build` leaves a
# linker-signed Mach-O, which does not seal Info.plist or Resources — so the
# bundle's signature is invalid, and macOS reports a downloaded copy as
# "damaged and can't be opened" rather than merely unidentified.
#
# Ad-hoc (`-`) is the best we can do without a Developer ID. It does not make
# the app notarized: a download still needs right-click → Open once. It does
# mean Gatekeeper reports that honestly instead of sending users to the Trash.
echo "→ codesign (ad-hoc)"
codesign --force --sign - --identifier dev.phonesnap.PhoneSnap "$APP"
codesign --verify --deep --strict "$APP"

echo "→ built $APP"
echo "  binary: $(du -h "$APP/Contents/MacOS/PhoneSnap" | cut -f1)"
echo "  signature: $(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature/{print $2}')"
echo
echo "Run: open ./$APP"
echo "Or move to /Applications: mv $APP /Applications/"
