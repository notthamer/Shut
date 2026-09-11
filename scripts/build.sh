#!/bin/bash
# Builds Shut.app from the SwiftPM package without Xcode.
#
#   scripts/build.sh          -> build/Shut.app
#   scripts/build.sh --zip    -> also build/Shut-<version>.zip for GitHub Releases
#
# The app is ad-hoc signed. Screen Recording permission is tied to the bundle
# identifier plus the code signature, so a rebuild may need the permission to be
# re-granted in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)
APP=build/Shut.app
BIN=.build/release/shut
BUNDLE=.build/release/Shut_TransitionKit.bundle

echo "Building Shut $VERSION (release)…"
swift build -c release --product shut 2>&1 | tail -1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shut"
cp App/Info.plist "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$APP/Contents/Resources/"
else
  echo "warning: $BUNDLE not found; shaders will be missing" >&2
fi

# Prefer a stable local certificate so Screen Recording permission survives
# rebuilds (see App/Signing.xcconfig); fall back to ad-hoc.
IDENTITY="${SHUT_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Shut Dev"'; then
  IDENTITY="Shut Dev"
fi
codesign --force --sign "${IDENTITY:--}" --entitlements App/Shut.entitlements "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc identity})"

if [ "${1:-}" = "--zip" ]; then
  ZIP="build/Shut-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Zipped to $ZIP"
fi
