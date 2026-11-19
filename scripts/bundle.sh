#!/bin/bash
# Builds dist/Squawk.app and dist/Squawk-<version>.dmg from the SwiftPM
# package. There is no Xcode project on purpose: this is the whole packaging
# step, and it runs the same on a laptop with only the command line tools as
# it does in CI.
#
#   VERSION        version string for the bundle, default 0.0.0
#   SIGN_IDENTITY  "Developer ID Application: ..." to sign with. Unset, the
#                  first Developer ID in the keychain is used, and failing that
#                  an ad-hoc signature. Ad-hoc works but macOS then treats every
#                  rebuild as a different app and forgets its Accessibility and
#                  Microphone grants; a real identity keeps them.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VERSION:-0.0.0}"
identity="${SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
identity="${identity:--}"
app="dist/Squawk.app"
dmg="dist/Squawk-$version.dmg"

swift build -c release --arch arm64

rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Squawk "$app/Contents/MacOS/Squawk"
cp packaging/Squawk.icns "$app/Contents/Resources/Squawk.icns"
cp packaging/MenuBarCrow.png "$app/Contents/Resources/MenuBarCrow.png"
sed "s/__VERSION__/$version/g" packaging/Info.plist > "$app/Contents/Info.plist"

# FluidAudio's SwiftPM resource bundle is left out: it only holds text-to-speech
# lexicons, which this app never loads.

# A secure timestamp is required for notarization, so CI asks Apple's server
# for one. Local builds skip it and so keep working offline.
timestamp="--timestamp=none"
if [ "$identity" != "-" ] && [ -n "${CI:-}" ]; then
    timestamp="--timestamp"
fi
codesign --force --options runtime "$timestamp" \
    --entitlements packaging/Squawk.entitlements --sign "$identity" "$app"

hdiutil create -quiet -volname Squawk -srcfolder "$app" -ov -format UDZO "$dmg"
if [ "$identity" != "-" ]; then
    codesign --force "$timestamp" --sign "$identity" "$dmg"
fi

echo "$dmg"
