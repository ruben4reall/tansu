#!/bin/bash
# scripts/publish.sh <release|tap|site> <version> [--confirm <version>]
#
# The publication steps of a release, in this order, once scripts/release.sh (and finish-release.sh) are done. Each one
# needs Ruben's go-ahead: in a terminal it asks for the version to be typed; an agent passes --confirm <version> only
# after Ruben has said yes to that step in the conversation.
#   release  tags the commit the app was built from as v<version>, pushes the tag, publishes the GitHub release with
#            both disk images, then checks that the published files are the ones the appcast signs
#   tap      pushes the release's cask to ruben4reall/homebrew-tap, once the published download matches its SHA-256
#   site     deploys site/ to Vercel production in the scope TIROIR_VERCEL_SCOPE names (the maintainer's personal scope,
#            never a team), checks the live appcast, then commits and pushes it
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=ruben4reall/tiroir
TAP=ruben4reall/homebrew-tap
SITE_URL=https://gettiroir.vercel.app
STEP="${1:-}"
VERSION="${2:-}"
fail() { echo "publish: $*" >&2; exit 1; }
if [[ ! "$STEP" =~ ^(release|tap|site)$ ]] || [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "usage: scripts/publish.sh <release|tap|site> <version> [--confirm <version>]"
fi
DMG="dist/Tiroir-$VERSION.dmg"
DOWNLOAD="https://github.com/$REPO/releases/download/v$VERSION/Tiroir-$VERSION.dmg"

confirm() {
  if [ "${3:-}" = "--confirm" ] && [ "${4:-}" = "$VERSION" ]; then return 0; fi
  [ -t 0 ] || fail "not confirmed: run it in a terminal, or pass --confirm $VERSION once Ruben has said yes"
  local answer
  read -r -p "Publish ($STEP) Tiroir $VERSION? Type the version to go ahead: " answer
  [ "$answer" = "$VERSION" ] || fail "not confirmed"
}

fetch() {   # fetch <url> <file>: downloads a published file, following GitHub's redirects
  curl -fsSL --retry 3 -o "$2" "$1" || fail "cannot download $1"
}

publish_release() {
  local file commit tmp
  for file in "$DMG" dist/Tiroir.dmg dist/release-notes.md dist/build-commit.txt; do
    [ -f "$file" ] || fail "dist/ is incomplete ($file): run scripts/release.sh for $VERSION first"
  done
  cmp -s "$DMG" dist/Tiroir.dmg || fail "dist/Tiroir.dmg is not the same file as $DMG"
  xcrun stapler validate "$DMG" >/dev/null || fail "$DMG carries no notarization ticket"
  [ "$(gh repo view "$REPO" --json visibility --jq .visibility)" = PUBLIC ] \
    || fail "$REPO is private: nobody could download the release (making it public is its own go-ahead)"
  commit=$(cat dist/build-commit.txt)
  git fetch -q origin main
  git merge-base --is-ancestor "$commit" origin/main || fail "the build commit $commit is not on origin/main"
  if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then fail "tag v$VERSION exists"; fi
  git tag -a "v$VERSION" "$commit" -m "Tiroir $VERSION"
  git push -q origin "v$VERSION"
  gh release create "v$VERSION" "$DMG" dist/Tiroir.dmg --repo "$REPO" --title "Tiroir $VERSION" \
    --notes-file dist/release-notes.md --verify-tag
  tmp=$(mktemp -d)
  fetch "$DOWNLOAD" "$tmp/Tiroir-$VERSION.dmg"
  cmp -s "$tmp/Tiroir-$VERSION.dmg" "$DMG" || fail "the published $DOWNLOAD differs from $DMG"
  swift scripts/verify-update.swift App/Info.plist site/appcast.xml "$VERSION" "$tmp/Tiroir-$VERSION.dmg"
  fetch "https://github.com/$REPO/releases/latest/download/Tiroir.dmg" "$tmp/Tiroir.dmg"
  cmp -s "$tmp/Tiroir.dmg" "$DMG" || fail "releases/latest/download/Tiroir.dmg is not Tiroir $VERSION"
  rm -rf "$tmp"
  echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"
}

publish_tap() {
  local cask=dist/homebrew/Casks/tiroir.rb clone=.build/homebrew-tap tmp published
  [ -f "$cask" ] || fail "$cask is missing: run scripts/finish-release.sh $VERSION"
  grep -qF "version \"$VERSION\"" "$cask" || fail "$cask is not for $VERSION"
  gh repo view "$TAP" >/dev/null 2>&1 || fail "$TAP does not exist (creating it is its own go-ahead)"
  tmp=$(mktemp -d)
  fetch "$DOWNLOAD" "$tmp/Tiroir-$VERSION.dmg"
  published=$(shasum -a 256 "$tmp/Tiroir-$VERSION.dmg" | awk '{print $1}')
  rm -rf "$tmp"
  grep -qF "sha256 \"$published\"" "$cask" || fail "the cask's SHA-256 is not the published download's ($published)"
  if [ -d "$clone/.git" ]; then git -C "$clone" pull -q --ff-only; else gh repo clone "$TAP" "$clone" -- -q; fi
  mkdir -p "$clone/Casks"
  cp "$cask" "$clone/Casks/tiroir.rb"
  git -C "$clone" add Casks/tiroir.rb
  if git -C "$clone" diff --cached --quiet; then echo "The tap already has tiroir $VERSION."; return 0; fi
  git -C "$clone" -c user.name="Ruben Catalao" -c user.email=ruben.ctlo@protonmail.com commit -q -m "tiroir $VERSION"
  git -C "$clone" push -q origin HEAD
  echo "Pushed tiroir $VERSION to $TAP: brew install --cask ruben4reall/tap/tiroir"
}

publish_site() {
  : "${TIROIR_VERCEL_SCOPE:?set TIROIR_VERCEL_SCOPE to the personal Vercel scope of the maintainer}"
  [ "$(git branch --show-current)" = main ] || fail "publish the site from main"
  scripts/check-site.sh "$VERSION"
  grep -q '"projectName": *"tiroir"' site/.vercel/project.json 2>/dev/null \
    || fail "site/ is not linked to the Vercel project tiroir: (cd site && vercel link --yes --project tiroir --scope \"\$TIROIR_VERCEL_SCOPE\")"
  (cd site && vercel deploy --prod --yes --scope "$TIROIR_VERCEL_SCOPE")
  local tmp; tmp=$(mktemp)
  fetch "$SITE_URL/appcast.xml" "$tmp"
  cmp -s "$tmp" site/appcast.xml || fail "$SITE_URL/appcast.xml is not the local appcast"
  rm -f "$tmp"
  git add site/appcast.xml
  if ! git diff --cached --quiet; then
    git commit -q -m "Publish the appcast for $VERSION"
    git push -q origin main
  fi
  echo "Live: $SITE_URL"
}

confirm "$@"
"publish_$STEP"
