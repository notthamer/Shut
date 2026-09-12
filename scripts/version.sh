#!/bin/bash
# Prints the app version; the single source of truth is App/Info.plist.
cd "$(dirname "$0")/.."
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist
