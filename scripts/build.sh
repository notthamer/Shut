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
BUNDLES=.build/release/Shut_*.bundle

echo "Building Shut $VERSION (release)…"
swift build -c release --product shut 2>&1 | tail -1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shut"
cp App/Info.plist "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
for bundle in $BUNDLES; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp App/Shut.icns "$APP/Contents/Resources/Shut.icns"
# This version's section of the changelog, for the "What's new" card shown once after an update.
scripts/release-notes.sh "$VERSION" > "$APP/Contents/Resources/WhatsNew.md"

# The typefaces are part of the product. Every font in the source tree has to be in
# the app, at the path Info.plist's ATSApplicationFontsPath points macOS to.
FONTS="$APP/Contents/Resources/$(/usr/libexec/PlistBuddy -c 'Print :ATSApplicationFontsPath' App/Info.plist)"
for font in Sources/Tuner/Fonts/*.otf Sources/Tuner/Fonts/*.ttf; do
  [ -f "$FONTS/$(basename "$font")" ] || { echo "build: $(basename "$font") did not reach $FONTS" >&2; exit 1; }
done

# Sparkle (in-app updates) is a dynamic framework; the executable looks for it in
# Contents/Frameworks (rpath set in Package.swift).
SPARKLE=$(ls -d .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework | head -1)
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"

# Prefer a stable local certificate so Screen Recording permission survives
# rebuilds (see App/Signing.xcconfig); fall back to ad-hoc.
IDENTITY="${SHUT_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Shut Dev"'; then
  IDENTITY="Shut Dev"
fi
# Sparkle's helpers are signed first, inside out, as its docs ask; hardened
# runtime only with a real identity (ad-hoc plus hardened runtime breaks the XPC services).
SIGN=(codesign --force --sign "${IDENTITY:--}")
[ -n "$IDENTITY" ] && SIGN+=(--options runtime --timestamp)
FW="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" --entitlements App/Shut.entitlements "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc identity})"

if [ "${1:-}" = "--zip" ]; then
  ZIP="build/Shut-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Zipped to $ZIP"
fi
