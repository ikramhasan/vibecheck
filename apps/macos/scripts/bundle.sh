#!/usr/bin/env bash
# Builds a release binary, wraps it in apps/macos/build/vibecheck.app and zips it.
# Usage: bundle.sh [version]   (defaults to 0.0.0 for local builds)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"

swift build -c release
scripts/build-diff-viewer.sh
BIN="$(swift build -c release --show-bin-path)/Vibecheck"
APP="build/vibecheck.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Vibecheck"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Vibecheck"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM resources (provider icons).
cp -R "$(dirname "$BIN")/Vibecheck_Vibecheck.bundle" "$APP/Contents/Resources/"
cp -R vendor/diff-viewer "$APP/Contents/Resources/DiffViewer"

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
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/ikramhasan/homebrew-tap/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>S/wgXQZ30k26DJL1yAHhoVhjq7XnmAQyPhkIzMkIE6s=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>vibecheck selects the terminal tab an agent is running in when you click its session.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the app (no --deep: it's deprecated and unordered).
codesign --force --sign - "$APP" >/dev/null 2>&1
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP"

# ditto keeps the code signature intact; plain zip can break it.
ZIP="build/vibecheck-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zipped $(pwd)/$ZIP"
