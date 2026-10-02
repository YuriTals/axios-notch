#!/bin/bash
# Builds "build/Axios Notch.app" from the SwiftPM executable.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build (faster)
# The app is ad-hoc signed, which is enough to run it on this Mac. To
# distribute it, sign with a Developer ID (CODESIGN_IDENTITY="Developer ID
# Application: …") and notarize it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/Axios Notch.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AxiosNotch" "$APP/Contents/MacOS/AxiosNotch"
cp Sources/AxiosNotch/Resources/AxiosMark.png "$APP/Contents/Resources/"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "$APP/Contents/Info.plist"

# Bundled SwiftPM resource bundles (none are needed at runtime: AppResources
# reads straight from Contents/Resources), so nothing else to copy.
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP (version $VERSION, build $BUILD)"
