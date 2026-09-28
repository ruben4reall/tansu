#!/bin/bash
# brand/scripts/export-icon.sh: renders brand/Tiroir.icon to brand/icon-previews/ with Icon Composer's ictool.
#   default-1024.png ... default-16.png   the Default rendition, with the macOS mask and edge
#   Dark-1024.png, ClearLight-1024.png, TintedDark-1024.png   the other renditions
# Run node brand/scripts/icon/layers.mjs first when the icon changed. Needs Xcode 26 and ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."
ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ictool" ] || { echo "ictool is missing: install Xcode 26" >&2; exit 1; }
mkdir -p icon-previews
for size in 1024 256 128 64 32 16; do
  "$ictool" Tiroir.icon --export-image --output-file "icon-previews/default-$size.png" --platform macOS --rendition Default --width "$size" --height "$size" --scale 1 >/dev/null
done
for rendition in Dark ClearLight TintedDark; do
  "$ictool" Tiroir.icon --export-image --output-file "icon-previews/$rendition-1024.png" --platform macOS --rendition "$rendition" --width 1024 --height 1024 --scale 1 >/dev/null
done
# ictool writes some previews as 16-bit PNG: store 8-bit RGBA, and no timestamps, so the files do not change between runs.
for file in icon-previews/*.png; do
  magick "$file" -depth 8 -define png:exclude-chunks=date,tIME "PNG32:$file"
done
ls icon-previews
