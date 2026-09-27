#!/bin/bash
# brand/scripts/render-html.sh <input.html> <output.png> <width> <height> [background]
# Renders a page with Google Chrome without a window. background: optional RRGGBBAA hex (00000000 keeps the page
# transparent); without it, Chrome's default white.
set -euo pipefail
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
input="$1"
query=""
case "$input" in *\?*) query="?${input#*\?}"; input="${input%%\?*}" ;; esac
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --allow-file-access-from-files \
  ${5:+--default-background-color="$5"} --window-size="$3,$4" --screenshot="$2" \
  "file://$(cd "$(dirname "$input")" && pwd)/$(basename "$input")$query" >/dev/null 2>&1
test -s "$2"
