#!/bin/bash
# Builds Sinkhole.app from the SwiftPM package without Xcode.
#
#   scripts/build.sh          -> build/Sinkhole.app
#   scripts/build.sh --zip    -> also build/Sinkhole-<version>.zip for GitHub Releases
#
# The app is ad-hoc signed. Screen Recording permission is tied to the bundle
# identifier plus the code signature, so a rebuild may need the permission to be
# re-granted in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)
APP=build/Sinkhole.app
BIN=.build/release/sinkhole
BUNDLE=.build/release/Sinkhole_TransitionKit.bundle

echo "Building Sinkhole $VERSION (release)…"
swift build -c release --product sinkhole 2>&1 | tail -1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sinkhole"
cp App/Info.plist "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$APP/Contents/Resources/"
else
  echo "warning: $BUNDLE not found; shaders will be missing" >&2
fi

codesign --force --sign - --entitlements App/Sinkhole.entitlements "$APP"
echo "Built $APP"

if [ "${1:-}" = "--zip" ]; then
  ZIP="build/Sinkhole-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Zipped to $ZIP"
fi
