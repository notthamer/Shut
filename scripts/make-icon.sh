#!/bin/bash
# Redraws the app icon from scripts/make-icon.swift and recuts every size into
# App/Assets.xcassets/AppIcon.appiconset. The artwork is code, not a binary.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc -O -o "$TMP/make-icon" scripts/make-icon.swift -framework AppKit
"$TMP/make-icon" "$TMP/icon-1024.png"
SET=App/Assets.xcassets/AppIcon.appiconset
mkdir -p "$SET"
rm -f "$SET"/*.png
entries=""
for spec in "16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2"; do
  set -- $spec; pt=$1; scale=$2; px=$((pt * scale))
  name="icon_${pt}x${pt}@${scale}x.png"
  sips -z $px $px "$TMP/icon-1024.png" --out "$SET/$name" >/dev/null
  entries="$entries    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${pt}x${pt}\" },\n"
done
printf '{\n  "images" : [\n%b  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "${entries%,\\n}" > "$SET/Contents.json"
cp "$TMP/icon-1024.png" build/icon-1024.png 2>/dev/null || true
echo "Icon written to $SET"
