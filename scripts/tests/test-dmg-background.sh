#!/bin/bash
# The installer background: drawn in the brand's colors, sized for Finder, light where Finder writes the labels.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
colors() { grep -oE 'color\("#[0-9A-Fa-f]{6}"' scripts/make-dmg-background.swift | grep -oE '[0-9A-Fa-f]{6}'; }
several() { [ "$(colors | wc -l)" -ge 5 ]; }
check "the script names its colors" several
# The palette's source of truth is brand/tokens/tokens.json. Until brand/ is in the repository there is nothing to
# compare with; once it is, a missing tokens file fails like a color that is not a token.
if [ -d brand ]; then
  for hex in $(colors); do
    check "#$hex is a brand token (brand/tokens/tokens.json)" grep -qi "$hex" brand/tokens/tokens.json
  done
else
  echo "  skipped: brand/ is not in the repository yet, so the colors cannot be compared with its tokens"
fi
check "the script draws a background" swift scripts/make-dmg-background.swift "$TMP/background.png"
check "a fresh background passes the layout checks" swift scripts/tests/check-dmg-background.swift "$TMP/background.png"
check "the committed background passes the layout checks" swift scripts/tests/check-dmg-background.swift packaging/dmg-background.png
dpi_144() { [[ "$(sips -g dpiWidth "$1")" == *"dpiWidth: 144"* ]]; }
check "the committed background is marked 144 dpi, so Finder shows it at 660 x 400 points" dpi_144 packaging/dmg-background.png
