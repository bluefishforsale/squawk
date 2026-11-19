#!/bin/bash
# Turns the icon SVGs into packaging/Squawk.icns and packaging/MenuBarCrow.png,
# the files bundle.sh copies into the app. Run it again whenever the artwork
# changes.
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

# The menu bar glyph is 18 pt; 72 px covers it at up to 4x.
swift scripts/render-svg.swift 72 design/icons/menubar-crow.svg >/dev/null
cp design/icons/menubar-crow.png packaging/MenuBarCrow.png
echo packaging/MenuBarCrow.png
