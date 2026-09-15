#!/bin/bash
# Packages build/Shut.app into build/releases/Shut-<version>.dmg with a SHA-256.
#
# The disk image opens as a 600×300 Finder window over App/dmg-background.png
# (1200×600 at 144 dpi, so it is sharp on Retina), Shut.app on the left and an
# Applications shortcut on the right, both over the light part of the picture so
# their labels stay readable: drag one onto the other. The layout is
# written by Finder through AppleScript; if that is refused (no Automation
# permission, or a headless machine) the image is still produced, just plain.
#
# Needs an APFS/HFS checkout (extended attributes carry the signature).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)
APP=build/Shut.app
[ -d "$APP" ] || scripts/build.sh
OUT=build/releases
mkdir -p "$OUT"
DMG="$OUT/Shut-$VERSION.dmg"
RW="$OUT/Shut-$VERSION-rw.dmg"
VOLNAME="Shut"
BACKGROUND=App/dmg-background.png

# Window geometry in points. The background is 2× these dimensions.
WIN_X=200; WIN_Y=140; WIN_W=600; WIN_H=300
ICON_SIZE=128; TEXT_SIZE=13
APP_X=200; APPS_X=440; ICON_Y=135

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/background.png"

rm -f "$DMG" "$RW"
# Read-write first so Finder can save the window layout into .DS_Store; HFS+
# because every macOS mounts it and the layout keys are stable there.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -fs HFS+ -format UDRW "$RW" >/dev/null
rm -rf "$STAGE"

MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
[ -n "$MOUNT" ] || { echo "could not mount $RW"; exit 1; }
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

if osascript - "$VOLNAME" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H" "$ICON_SIZE" "$TEXT_SIZE" "$APP_X" "$APPS_X" "$ICON_Y" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set volName to item 1 of argv
  set {wx, wy, ww, wh} to {item 2 of argv as integer, item 3 of argv as integer, item 4 of argv as integer, item 5 of argv as integer}
  set {iconSize, textSize} to {item 6 of argv as integer, item 7 of argv as integer}
  set {appX, appsX, iconY} to {item 8 of argv as integer, item 9 of argv as integer, item 10 of argv as integer}
  tell application "Finder"
    tell disk volName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {wx, wy, wx + ww, wy + wh}
      set opts to icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to iconSize
      set text size of opts to textSize
      set label position of opts to bottom
      set background picture of opts to file ".background:background.png"
      set position of item "Shut.app" to {appX, iconY}
      set position of item "Applications" to {appsX, iconY}
      close
      open
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT
then
  echo "Finder layout written"
else
  echo "warning: Finder layout skipped (Automation permission or no GUI); plain image"
fi

# Keep the helper folder out of sight even with hidden files shown.
chflags hidden "$MOUNT/.background" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet
trap - EXIT

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Packaged $DMG"
cat "$DMG.sha256"
