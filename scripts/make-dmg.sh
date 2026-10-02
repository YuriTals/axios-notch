#!/bin/bash
# Builds "build/AxiosNotch-<version>.dmg": the installer people open and drag the app from.
#   scripts/make-dmg.sh            builds the app (release) first, then the .dmg
#   VERSION=1.2.0 scripts/make-dmg.sh
#
# The tools it needs (dmgbuild, Pillow) live in a throwaway virtualenv under build/, so
# nothing is installed on the system. The app is ad-hoc signed unless CODESIGN_IDENTITY is
# set; an ad-hoc app downloaded from the internet needs one extra step on first launch
# (right-click > Open) because it is not notarized — see README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="build/Axios Notch.app"
DMG="build/AxiosNotch-$VERSION.dmg"
VENV="build/.dmgvenv"

VERSION="$VERSION" scripts/build-app.sh release

if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet dmgbuild pillow
fi
[ -f Packaging/dmg-background.png ] || "$VENV/bin/python" scripts/make-dmg-background.py

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s Packaging/dmg-settings.py \
    -D app="$APP" -D icon="Packaging/AppIcon.icns" -D packaging="Packaging" -D settings_dir="Packaging" \
    "Axios Notch" "$DMG"

# A broken installer is worse than none: confirm it mounts and holds a valid app.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -readonly -quiet
trap 'hdiutil detach "$MOUNT" -quiet || true' EXIT
codesign --verify --deep --strict "$MOUNT/Axios Notch.app"
[ -e "$MOUNT/Applications" ] || { echo "Applications shortcut missing" >&2; exit 1; }
echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"
