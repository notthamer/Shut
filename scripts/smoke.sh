#!/bin/bash
# Checks that build/Shut.app works on a Mac that did not build it.
#
# Everything else in this repo runs on the machine that compiled the code, where
# SwiftPM's .build directory exists. 0.1.0 and 0.2.0 found their fonts there through
# `Bundle.module` and crashed on launch everywhere else. So this:
#
#   1. refuses any use of `Bundle.module` in Sources (each target has a
#      `resourceBundle()` that looks inside the app instead);
#   2. copies Shut.app somewhere else, hides .build, and runs `Shut --self-check`,
#      which has to find the fonts, shaders and images from the app alone.
#
# Run after scripts/build.sh. scripts/notarize.sh and CI both call it.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Shut.app
[ -d "$APP" ] || { echo "smoke: $APP is missing; run scripts/build.sh first" >&2; exit 1; }

# Comment lines may mention it; code may not.
if grep -rn 'Bundle\.module' Sources --include='*.swift' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'; then
  echo "smoke: Bundle.module crashes outside the build machine; use the target's resourceBundle()" >&2
  exit 1
fi

STAGE=$(mktemp -d)
restore() {
  [ -d .build.away ] && mv .build.away .build
  rm -rf "$STAGE"
}
trap restore EXIT
cp -R "$APP" "$STAGE/"
[ -d .build ] && mv .build .build.away

"$STAGE/Shut.app/Contents/MacOS/Shut" --self-check
echo "smoke: Shut.app finds its resources away from the build directory"
