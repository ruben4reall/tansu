#!/bin/bash
# scripts/finish-release.sh <version>: turns the notarized dist/Tansu-<version>.dmg into everything a release publishes,
# and publishes nothing: the stapled image and its stable copy dist/Tansu.dmg, its SHA-256, the release notes (from
# CHANGELOG.md), the new appcast item (EdDSA-signed with the key in the login keychain: macOS asks once to let
# generate_appcast use it) and the Homebrew cask. scripts/release.sh runs it; after NOTARIZE_LATER, run it yourself.
#
# TANSU_APPCAST (default site/appcast.xml) and TANSU_DOWNLOAD_PREFIX (default the GitHub release of <version>) let the
# update rehearsal serve a feed from this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/finish-release.sh <version>}"
REPO_URL=https://github.com/ruben4reall/tansu
SITE_URL=https://gettansu.vercel.app
ACCOUNT=ch.rubencatalao.tansu   # the keychain account of Tansu's Sparkle key (generate_keys --account)
APPCAST="${TANSU_APPCAST:-site/appcast.xml}"
PREFIX="${TANSU_DOWNLOAD_PREFIX:-$REPO_URL/releases/download/v$VERSION/}"
DMG="dist/Tansu-$VERSION.dmg"
fail() { echo "finish-release: $*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "not a version: $VERSION"
[ -f "$DMG" ] || fail "$DMG is missing: run scripts/release.sh first"
[ -d "$(dirname "$APPCAST")" ] || fail "$(dirname "$APPCAST")/ is missing: the website serves the appcast"

# 1. Apple's ticket goes into the image first: stapling changes its bytes, and everything below signs or hashes them.
xcrun stapler staple "$DMG" >/dev/null || fail "Apple has not accepted $DMG yet (see dist/notary-pending.txt)"
xcrun stapler validate "$DMG" >/dev/null || fail "$DMG carries no valid ticket"
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "$DMG does not verify"
cp "$DMG" dist/Tansu.dmg
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "$SHA  Tansu-$VERSION.dmg" > "dist/Tansu-$VERSION.dmg.sha256"

# 2. Release notes, for GitHub and for Sparkle's update window.
NOTES=$(scripts/changelog-section.sh "$VERSION")
UPDATES=.build/release-updates
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
printf '%s\n' "$NOTES" > "$UPDATES/Tansu-$VERSION.md"
{
  printf '%s\n\n' "$NOTES"
  printf 'SHA-256 of Tansu-%s.dmg: `%s`\n\n' "$VERSION" "$SHA"
  printf 'Tansu is not affiliated with Apple.\n'
} > dist/release-notes.md

# 3. The appcast: the new item on top, older items kept, the whole feed signed (the app sets SURequireSignedFeed).
# -quit rather than "| head -1": with pipefail, find would die of SIGPIPE if it found a second copy.
GENERATE_APPCAST=$(find .build/spm/artifacts -type f -name generate_appcast -perm -u+x -print -quit 2>/dev/null || true)
[ -n "$GENERATE_APPCAST" ] || fail "Sparkle's tools are missing from .build/spm: build with scripts/release.sh first"
"$GENERATE_APPCAST" --account "$ACCOUNT" --download-url-prefix "$PREFIX" --link "$SITE_URL" \
  --full-release-notes-url "$REPO_URL/releases" --embed-release-notes --maximum-deltas 0 -o "$APPCAST" "$UPDATES"
rm -rf "$UPDATES"   # a second copy of the image, only needed by generate_appcast
swift scripts/verify-update.swift App/Info.plist "$APPCAST" "$VERSION" "$DMG"

# 4. The cask for the tap.
mkdir -p dist/homebrew/Casks
scripts/render-cask.sh "$VERSION" "$SHA" > dist/homebrew/Casks/tansu.rb

echo "Ready: $DMG, dist/Tansu.dmg, dist/release-notes.md, $APPCAST, dist/homebrew/Casks/tansu.rb"
echo "Publication, each step on Ruben's go-ahead: scripts/publish.sh release $VERSION, then tap, then site."
