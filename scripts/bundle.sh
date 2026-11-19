#!/bin/bash
# Builds dist/Squawk.app and dist/Squawk-<version>.dmg from the SwiftPM
# package. There is no Xcode project on purpose: this is the whole packaging
# step, and it runs the same on a laptop with only the command line tools as
# it does in CI.
#
#   VERSION        version string for the bundle, default 0.0.0
#   SIGN_IDENTITY  "Developer ID Application: ..." to sign for distribution;
#                  unset gives an ad-hoc signature that only suits local use.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:-0.0.0}"
identity="${SIGN_IDENTITY:--}"
app="dist/Squawk.app"
dmg="dist/Squawk-$version.dmg"

swift build -c release --arch arm64

rm -rf dist
mkdir -p "$app/Contents/MacOS"
cp .build/arm64-apple-macosx/release/Squawk "$app/Contents/MacOS/Squawk"
sed "s/__VERSION__/$version/g" packaging/Info.plist > "$app/Contents/Info.plist"

# FluidAudio's SwiftPM resource bundle is left out: it only holds text-to-speech
# lexicons, which this app never loads.

# Apple's timestamp server refuses ad-hoc signatures, so only ask for one
# when signing for real.
timestamp="--timestamp=none"
if [ "$identity" != "-" ]; then
    timestamp="--timestamp"
fi
codesign --force --options runtime "$timestamp" \
    --entitlements packaging/Squawk.entitlements --sign "$identity" "$app"

hdiutil create -quiet -volname Squawk -srcfolder "$app" -ov -format UDZO "$dmg"
if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi

echo "$dmg"
