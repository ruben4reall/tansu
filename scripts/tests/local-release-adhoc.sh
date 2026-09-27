#!/bin/bash
# scripts/tests/local-release-adhoc.sh: runs scripts/release.sh without a team (ad hoc), then opens the disk image and
# checks what people would get. Local only: it builds the app (a few minutes, and several hundred MB in .build) and may
# show a Finder window.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
env -u TANSU_TEAM_ID scripts/release.sh
DMG="dist/Tansu-$VERSION.dmg"
MNT=$(mktemp -d)
fail() { echo "FAIL: $*" >&2; hdiutil detach "$MNT" -quiet -force 2>/dev/null || true; exit 1; }
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "$DMG does not verify"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG" >/dev/null
APP="$MNT/Tansu.app"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
[ -d "$APP" ] || fail "no Tansu.app in the image"
[ "$(readlink "$MNT/Applications")" = /Applications ] || fail "no Applications link"
if [ -f packaging/dmg-background.png ]; then
  cmp -s "$MNT/.background/background.png" packaging/dmg-background.png || fail "the background is not packaging/dmg-background.png"
fi
[ -f "$MNT/.DS_Store" ] || echo "note: no .DS_Store, so Finder did not apply the layout (automation denied?)"
[ "$(plist CFBundleIdentifier)" = ch.rubencatalao.tansu ] || fail "CFBundleIdentifier is not ch.rubencatalao.tansu"
[ "$(plist CFBundleShortVersionString)" = "$VERSION" ] || fail "CFBundleShortVersionString is not $VERSION"
[ "$(plist CFBundleVersion)" = "$VERSION" ] || fail "CFBundleVersion is not $VERSION"
[ "$(plist SUFeedURL)" = "https://gettansu.vercel.app/appcast.xml" ] || fail "SUFeedURL is not the website's appcast"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || fail "Sparkle.framework is not embedded"
[ -f "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md" ] || fail "THIRD-PARTY-NOTICES.md is not in the app"
codesign --verify --deep --strict "$APP" || fail "the signature does not verify"
sig=$(codesign -dv "$APP" 2>&1 || true)
[[ "$sig" == *"flags=0x2(adhoc)"* ]] || fail "expected an ad hoc signature without the hardened runtime: $sig"
hdiutil detach "$MNT" -quiet
echo "PASS: $DMG"
