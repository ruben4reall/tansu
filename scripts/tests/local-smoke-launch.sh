#!/bin/bash
# scripts/tests/local-smoke-launch.sh: builds an ad hoc Release app and checks that it launches and keeps running.
# Local only: it quits any running Tansu, then shows Tansu in demo mode for a few seconds (generic icons: your own menu
# bar and your settings are left alone). It catches a framework the app cannot load, such as Sparkle refused by library
# validation.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=$(scripts/build.sh Release)
pkill -x Tansu 2>/dev/null || true
# -SUEnableAutomaticChecks NO keeps Sparkle from checking for updates during tests.
open -n "$APP" --args -TansuDemo YES -SUEnableAutomaticChecks NO
sleep 4
if ! pgrep -x Tansu >/dev/null; then
  echo "FAIL: Tansu is not running 4 s after launch" >&2
  /usr/bin/log show --last 30s --style compact --predicate 'process == "Tansu"' | tail -n 20 >&2
  exit 1
fi
# Read whole, then matched: with pipefail, "log show | grep -q" fails when grep stops reading early (SIGPIPE).
recent=$(/usr/bin/log show --last 10s --info --style compact --predicate 'subsystem == "ch.rubencatalao.tansu"' || true)
if [[ "$recent" != *"Tansu started"* ]]; then
  pkill -x Tansu
  echo "FAIL: no 'Tansu started' line in the log" >&2
  exit 1
fi
pkill -x Tansu
echo "PASS: $APP launches and runs"
