#!/bin/bash
# scripts/bench.sh measures what it is given, and refuses what it cannot measure.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
refuses "a malformed pid" "usage" scripts/bench.sh tansu
refuses "a malformed duration" "usage" scripts/bench.sh 1 soon
refuses "a zero duration" "usage" scripts/bench.sh 1 0
refuses "a process that does not exist" "no process" scripts/bench.sh 99999999 1
sleep 60 & QUIET=$!
disown "$QUIET"   # ended by the trap below, without the shell reporting it
trap 'kill "$QUIET" 2>/dev/null || true; rm -rf "$TMP"' EXIT
measured() {
  scripts/bench.sh "$QUIET" 1 > "$TMP/bench" || return 1
  cat "$TMP/bench"
  grep -qE '^footprint: [0-9]+\.[0-9] MB$' "$TMP/bench" && grep -qE '^cpu: [0-9]+\.[0-9]{4} %$' "$TMP/bench"
}
check "a quiet process, one second: its footprint and its processor time, to 0.0001 %" measured
