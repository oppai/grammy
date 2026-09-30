#!/bin/bash
# Builds Grammy.app into ./build. Accessibility permission is tied to the code signature's
# designated requirement; set CODESIGN_IDENTITY to use a real certificate instead of ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/Grammy.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Grammy" "$APP/Contents/MacOS/Grammy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "$IDENTITY" = "-" ]; then
    # Ad-hoc signatures default to a cdhash-based designated requirement, which changes on
    # every build and silently invalidates the Accessibility grant. Pin it to the bundle ID instead.
    codesign --force --sign - --identifier ninja.oppai.grammy \
        --requirements '=designated => identifier "ninja.oppai.grammy"' "$APP"
else
    codesign --force --sign "$IDENTITY" --identifier ninja.oppai.grammy "$APP"
fi
echo "Built $APP (signed with: $IDENTITY)"
