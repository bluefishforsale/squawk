#!/bin/bash
# Regenerates design/screenshots/*.png, the pane images in the README.
#
# The debug binary run outside the app bundle has its own preferences domain
# ("Squawk"), so this fills that with sample data and never touches, or
# shows, the settings of an installed copy.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
domain=Squawk
defaults delete "$domain" >/dev/null 2>&1 || true
defaults write "$domain" names -data "$(printf '%s' \
    '[{"id":"00000000-0000-0000-0000-000000000001","text":"Terrac","soundsLike":"terek, tarik, derrick"},{"id":"00000000-0000-0000-0000-000000000002","text":"Squawk","soundsLike":"squak, squalk"}]' \
    | xxd -p | tr -d '\n')"
defaults write "$domain" replacements -string $'kube cuddle => kubectl\nmy sequel => MySQL'
.build/debug/Squawk --render-panes design/screenshots
defaults delete "$domain" >/dev/null 2>&1 || true
ls design/screenshots
