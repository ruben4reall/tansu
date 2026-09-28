#!/bin/bash
# The Homebrew cask renders for a release, stays valid Ruby, and removes everything Tiroir leaves behind on zap.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
SHA=$(printf 'tiroir' | shasum -a 256 | awk '{print $1}')
CASK="$TMP/tiroir.rb"
render() { scripts/render-cask.sh 1.2.3 "$SHA" > "$CASK"; }
check "the cask renders" render
check "it names the version" grep -qF 'version "1.2.3"' "$CASK"
check "it names the SHA-256" grep -qF "sha256 \"$SHA\"" "$CASK"
check "it downloads the versioned disk image" grep -qF 'url "https://github.com/ruben4reall/tiroir/releases/download/v#{version}/Tiroir-#{version}.dmg"' "$CASK"
check "it needs macOS 26" grep -qF 'depends_on macos: :tahoe' "$CASK"
check "it leaves updates to Sparkle" grep -qF 'auto_updates true' "$CASK"
check "it follows the appcast" grep -qF 'url "https://gettiroir.vercel.app/appcast.xml"' "$CASK"
check "it quits Tiroir before removing it" grep -qF 'uninstall quit: "ch.rubencatalao.tiroir"' "$CASK"
check "zap removes the settings" grep -qF '"~/Library/Preferences/ch.rubencatalao.tiroir.plist",' "$CASK"
check "zap removes the settings of a Debug build" grep -qF '"~/Library/Preferences/ch.rubencatalao.tiroir.debug.plist",' "$CASK"
no_marker() { ! grep -q '@[A-Z0-9]*@' "$1"; }
check "no template marker is left" no_marker "$CASK"
check "it is valid Ruby" /usr/bin/ruby -c "$CASK"
refuses "a malformed version" "not a version" scripts/render-cask.sh 1.2 "$SHA"
refuses "a malformed SHA-256" "not a SHA-256" scripts/render-cask.sh 1.2.3 abc
