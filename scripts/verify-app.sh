#!/bin/bash
# Validate the actual packaged binary without opening the UI or using credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Axios Notch.app}"
PLIST="$APP/Contents/Info.plist"
plutil -lint "$PLIST"
CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :AxiosBuildChannel' "$PLIST")"
case "$CHANNEL" in
    production) BUNDLE_ID='com.axiosnotch.app'; ICON='Packaging/AppIcon.icns' ;;
    test) BUNDLE_ID='com.axiosnotch.app.test'; ICON='Packaging/TestAppIcon.icns' ;;
    *) echo "Unknown build channel: $CHANNEL" >&2; exit 1 ;;
esac
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = "$BUNDLE_ID"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" = '14.0'
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
test "$EXECUTABLE" = 'AxiosNotch'
test -x "$APP/Contents/MacOS/$EXECUTABLE"
cmp Sources/AxiosNotch/Resources/AxiosMark.png "$APP/Contents/Resources/AxiosMark.png"
cmp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
for FONT in Sources/AxiosNotch/Resources/Fonts/*.ttf; do
    cmp "$FONT" "$APP/Contents/Resources/Fonts/$(basename "$FONT")"
done
for LICENSE in Sources/AxiosNotch/Resources/Fonts/licenses/*; do
    cmp "$LICENSE" "$APP/Contents/Resources/Fonts/licenses/$(basename "$LICENSE")"
done
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/$EXECUTABLE" --verify-bundle
echo "Verified: $APP"
