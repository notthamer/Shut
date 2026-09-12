#!/bin/bash
# Packages build/Shut.app into build/releases/Shut-<version>.dmg with a SHA-256.
# Needs an APFS/HFS checkout (extended attributes carry the signature).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)
APP=build/Shut.app
[ -d "$APP" ] || scripts/build.sh
OUT=build/releases
mkdir -p "$OUT"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Shut-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Shut" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
shasum -a 256 "$DMG" > "$DMG.sha256"
rm -rf "$STAGE"
echo "Packaged $DMG"
cat "$DMG.sha256"
