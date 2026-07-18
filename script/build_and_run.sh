#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MTPFileTransfer"
BUNDLE_ID="local.codex.MTPFileTransfer"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
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

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/SwitchMTPBridge"
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

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
