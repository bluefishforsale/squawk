#!/bin/bash
# Turns the icon SVG into packaging/Squawk.icns, the file bundle.sh copies
# into the app. Run it again whenever the artwork changes.
#
#   scripts/make-icns.sh [design/icons/squawk-icon.svg]
set -euo pipefail
cd "$(dirname "$0")/.."

source_svg="${1:-design/icons/squawk-icon.svg}"
source_png="${source_svg%.svg}.png"
swift scripts/render-svg.swift 1024 "$source_svg" >/dev/null
iconset="$(mktemp -d)/Squawk.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns --output packaging/Squawk.icns "$iconset"
echo packaging/Squawk.icns
