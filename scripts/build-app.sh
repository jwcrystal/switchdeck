#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP="build/SwitchDeck.app"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product SwitchDeck

BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/SwitchDeck"
if [ ! -x "$BIN" ]; then
  echo "error: binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SwitchDeck"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>SwitchDeck</string>
    <key>CFBundleExecutable</key>
    <string>SwitchDeck</string>
    <key>CFBundleIdentifier</key>
    <string>studio.anyfun.switchdeck</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SwitchDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.7.1</string>
    <key>CFBundleVersion</key>
    <string>8</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>SwitchDeck uses System Events to change appearance and other system settings.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>SwitchDeck records audio when you start Recording from its menu.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
# A certificate identity keeps the designated requirement stable across builds,
# so macOS keeps the Accessibility grant. Falls back to ad-hoc (CDHash-based,
# which loses permission on every rebuild) when the identity is missing.
SIGN_IDENTITY="${SIGN_IDENTITY:-SwitchDeck Local Signing}"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
  echo "    signed with: $SIGN_IDENTITY"
else
  codesign --force --sign - --timestamp=none "$APP"
  echo "    signed ad-hoc (run scripts/setup-signing.sh for a stable identity)"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'
codesign -d -r- "$APP" 2>&1 | grep designated | sed 's/^/    /'

echo "==> Built $APP"
echo "    open $APP"
