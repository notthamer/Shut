#!/bin/bash
# Builds, signs, notarizes and staples Shut.app, then the DMG around it, so the
# result passes Gatekeeper offline. Needs a Developer ID Application certificate
# in the keychain and a notarytool keychain profile (the default is "shut",
# created once with `xcrun notarytool store-credentials shut --apple-id ...`).
#
#   SHUT_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/notarize.sh
#
# Produces build/releases/Shut-<version>.dmg and its .sha256. Upload those to the
# draft release the Release workflow made, then run the Appcast workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SHUT_SIGN_IDENTITY:?set SHUT_SIGN_IDENTITY to a Developer ID Application identity}"
PROFILE="${SHUT_NOTARY_PROFILE:-shut}"
VERSION=$(scripts/version.sh)
APP=build/Shut.app
ZIP="build/Shut-$VERSION-notary.zip"
DMG="build/releases/Shut-$VERSION.dmg"

scripts/build.sh
codesign --verify --deep --strict "$APP"
# Nothing goes to Apple that would not launch on somebody else's Mac.
scripts/smoke.sh

echo "Notarizing the app…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

rm -rf build/releases
scripts/package-dmg.sh

echo "Notarizing the disk image…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
# Stapling changed the bytes: the checksum is of what people download.
(cd build/releases && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
xcrun stapler validate "$DMG"
echo "Ready: $DMG"
cat "$DMG.sha256"
