#!/bin/bash
# Builds QR Code Opener and assembles it into a .app bundle.
#
# Flavours:
#
#   ./build.sh                          Local development build (ad-hoc signed).
#   MAS=1 SIGN_IDENTITY="Apple Distribution: Robots Drinking Tea LLC (TEAMID)" ./build.sh
#                                       Mac App Store build: sandbox + hardened runtime,
#                                       signed with a real Apple certificate.
#
# Why dev builds are ad-hoc — this was learned the hard way, do not "fix" it:
# TCC never lists an app signed with an untrusted (e.g. self-signed) certificate in
# System Settings > Privacy & Security > Screen Recording. The app re-prompts forever and
# can never be granted. Verified A/B with identical bundles: ad-hoc appears in the pane,
# self-signed-cert does not. Real Apple certificates chain to a trusted root and are fine.
#
# The cost of ad-hoc: the designated requirement is the binary's cdhash, so any build that
# changes the code invalidates the existing grant. This script detects that and resets the
# TCC record, so the pane shows a clean re-approval instead of a stale enabled toggle that
# silently grants nothing.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="QRCodeOpener"
BUNDLE_ID="com.robotsdrinkingtea.qrcodeopener"
# /Applications: the standard location users (and the System Settings file picker) expect.
# Keep the path stable — the TCC grant is tied to it.
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP="$INSTALL_DIR/$APP_NAME.app"
MAS="${MAS:-0}"

if [ "$MAS" = "1" ] && [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "MAS=1 requires SIGN_IDENTITY set to an Apple Distribution certificate name." >&2
    echo "See APPSTORE.md." >&2
    exit 1
fi

echo "==> Building (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

# Remember the outgoing signature so we can tell whether this build invalidates the grant.
OLD_CDHASH=""
if [ -d "$APP" ]; then
    OLD_CDHASH="$(codesign -dvvv "$APP" 2>&1 | awk -F= '/^CDHash=/{print $2}')" || true
fi

echo "==> Assembling $APP"
# Quit a running copy so the binary isn't replaced underneath it.
pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> Building icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -z $((size * 2)) $((size * 2)) AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
# Point at the .icns we just built. Info.plist itself only carries CFBundleIconName, which
# is what Xcode builds use to resolve the icon from Assets.xcassets.
plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"

if [ "$MAS" = "1" ]; then
    echo "==> Signing for Mac App Store: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" \
        --entitlements QRCodeOpener.entitlements --options runtime "$APP"
else
    echo "==> Signing (ad-hoc, development)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

    NEW_CDHASH="$(codesign -dvvv "$APP" 2>&1 | awk -F= '/^CDHash=/{print $2}')"
    if [ -n "$OLD_CDHASH" ] && [ "$OLD_CDHASH" != "$NEW_CDHASH" ]; then
        echo "==> Binary changed ($OLD_CDHASH -> $NEW_CDHASH): resetting stale TCC grant"
        tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
        echo "    Screen Recording must be re-approved on next launch (expected with ad-hoc)."
    fi
fi

echo
echo "Built: $APP"
echo "Launch it with:  open \"$APP\""
