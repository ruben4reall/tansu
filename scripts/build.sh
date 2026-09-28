#!/bin/bash
# scripts/build.sh: generates the Xcode project with XcodeGen and builds Tiroir.app into .build/xcode.
#
#   scripts/build.sh [Debug|Release]
#
# Signing: ad hoc by default, with the hardened runtime off (library validation would refuse Sparkle). Set
# TIROIR_TEAM_ID to your Apple team ID to sign with your Apple Development certificate instead. The Debug build uses
# the bundle identifier ch.rubencatalao.tiroir.debug, so it keeps its own settings and Accessibility grant.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-Debug}"
case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo "usage: scripts/build.sh [Debug|Release]" >&2; exit 64 ;;
esac
command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
SIGNING=(ENABLE_HARDENED_RUNTIME=NO)
if [ -n "${TIROIR_TEAM_ID:-}" ]; then
  SIGNING=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TIROIR_TEAM_ID" CODE_SIGN_IDENTITY="Apple Development")
fi
# Debug builds only the Mac's own architecture; Release is universal (Apple silicon and Intel).
DESTINATION='generic/platform=macOS'
[ "$CONFIGURATION" = Debug ] && DESTINATION='platform=macOS'
mkdir -p .build/xcode
LOG=.build/xcode/build.log
# No index store: the build stays small and fast, and nothing needs it outside an Xcode window.
xcodebuild -project Tiroir.xcodeproj -scheme Tiroir -configuration "$CONFIGURATION" -destination "$DESTINATION" \
  -derivedDataPath .build/xcode -clonedSourcePackagesDirPath .build/spm COMPILER_INDEX_STORE_ENABLE=NO \
  ${SIGNING[@]+"${SIGNING[@]}"} build > "$LOG" 2>&1 \
  || { grep -E "error:" "$LOG" | head -20 >&2; tail -n 20 "$LOG" >&2; exit 1; }
APP=".build/xcode/Build/Products/$CONFIGURATION/Tiroir.app"
codesign --verify --strict "$APP"
echo "$APP"
