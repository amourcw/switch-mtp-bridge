#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MTPFileTransfer"
BUNDLE_ID="local.codex.MTPFileTransfer"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
ASSET_CATALOG="$ROOT_DIR/Assets.xcassets"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

ACTOOL_PATH="$(xcrun --find actool 2>/dev/null || true)"
ICON_NAME_ENTRY=""
if [[ -n "$ACTOOL_PATH" ]]; then
  ICON_NAME_ENTRY=$'  <key>CFBundleIconName</key>\n  <string>AppIcon</string>'
fi

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/SwitchMTPBridge"
HELPER_BINARY="$ROOT_DIR/.build/mtp-helper"

clang Tools/mtp-helper.c -I/usr/local/include -L/usr/local/lib -lmtp -lusb-1.0 -o "$HELPER_BINARY"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$HELPER_BINARY" "$APP_MACOS/mtp-helper"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
if [[ -n "$ACTOOL_PATH" ]]; then
  "$ACTOOL_PATH" --compile "$APP_RESOURCES" --platform macosx --minimum-deployment-target "$MIN_SYSTEM_VERSION" --app-icon AppIcon "$ASSET_CATALOG"
fi
chmod +x "$APP_BINARY"
chmod +x "$APP_MACOS/mtp-helper"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
$ICON_NAME_ENTRY
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$APP_BUNDLE"
