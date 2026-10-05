#!/bin/bash
# Builds "build/Axios Notch.app" from the SwiftPM executable.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build (faster)
#   scripts/build-app.sh release test  isolated internal build with yellow test icon
# The app is ad-hoc signed, which is enough to run it on this Mac. To
# distribute it, sign with a Developer ID (CODESIGN_IDENTITY="Developer ID
# Application: …") and notarize it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
CHANNEL="${2:-production}"
VERSION="${VERSION:-1.0.3}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
case "$CHANNEL" in
    production) APP="build/Axios Notch.app"; BUNDLE_ID="com.axiosnotch.app"; ICON="Packaging/AppIcon.icns" ;;
    test) APP="build/Axios Notch Teste.app"; BUNDLE_ID="com.axiosnotch.app.test"; ICON="Packaging/TestAppIcon.icns" ;;
    *) echo "Unknown build channel: $CHANNEL (expected production or test)" >&2; exit 1 ;;
esac
test -f "$ICON"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AxiosNotch" "$APP/Contents/MacOS/AxiosNotch"
cp Sources/AxiosNotch/Resources/AxiosMark.png "$APP/Contents/Resources/"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# Terminal fonts (Nerd Font builds of six popular families) ride inside the app,
# with their licences, so nothing has to be installed separately.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Sources/AxiosNotch/Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp -R Sources/AxiosNotch/Resources/Fonts/licenses "$APP/Contents/Resources/Fonts/licenses"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AxiosBuildChannel string $CHANNEL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
if [ "$CHANNEL" = "test" ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Axios Notch Teste' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Axios Notch Teste' "$APP/Contents/Info.plist"
fi

# Bundled SwiftPM resource bundles (none are needed at runtime: AppResources
# reads straight from Contents/Resources), so nothing else to copy.
# An ad-hoc signature is identified by the hash of the code, which changes on
# every build — so macOS treats each build as a brand-new app and asks for every
# permission (Music, Documents, Desktop…) again. Pin the identity to the bundle
# identifier instead, so approvals survive rebuilds. (A Developer ID signature
# already has a stable identity, so it needs no such requirement.)
if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --options runtime --sign - \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
else
    codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built: $APP (version $VERSION, build $BUILD)"
