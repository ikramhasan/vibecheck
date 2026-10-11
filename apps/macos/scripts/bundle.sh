#!/usr/bin/env bash
# Builds a release binary, wraps it in apps/macos/build/vibecheck.app and zips it.
# Usage: bundle.sh [version]   (defaults to 0.0.0 for local builds)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"

swift build -c release
scripts/fetch-codexbar.sh
BIN="$(swift build -c release --show-bin-path)/Vibecheck"
APP="build/vibecheck.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vibecheck"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM resources (provider icons).
cp -R "$(dirname "$BIN")/Vibecheck_Vibecheck.bundle" "$APP/Contents/Resources/"
# CodexBar CLI finds its resource bundle next to itself, so they travel together.
cp vendor/codexbar/CodexBarCLI "$APP/Contents/Helpers/CodexBarCLI"
cp -R vendor/codexbar/CodexBar_CodexBarCore.bundle "$APP/Contents/Helpers/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>vibecheck</string>
  <key>CFBundleDisplayName</key><string>vibecheck</string>
  <key>CFBundleIdentifier</key><string>com.ikramulhasan.vibecheck</string>
  <key>CFBundleExecutable</key><string>Vibecheck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>vibecheck selects the terminal tab an agent is running in when you click its session.</string>
</dict>
</plist>
PLIST

# Sign nested code inside-out, then the app (no --deep: it's deprecated and unordered).
codesign --force --sign - "$APP/Contents/Helpers/CodexBar_CodexBarCore.bundle" >/dev/null 2>&1
codesign --force --sign - "$APP/Contents/Helpers/CodexBarCLI" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP"

# ditto keeps the code signature intact; plain zip can break it.
ZIP="build/vibecheck-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zipped $(pwd)/$ZIP"
