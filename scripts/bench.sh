#!/bin/bash
# scripts/bench.sh [pid] [seconds]: memory footprint and average processor use of a process over a quiet period
# (60 seconds by default), the numbers the README reports. Without a pid it measures the running Tiroir. Adapted from
# Islet's.
#
# Tiroir's budget at rest is under 30 MB and under 0.01 % of one core. At that level ps, which counts processor time in
# hundredths of a second, cannot tell 0.01 % from nothing over a minute, so the processor time comes from the kernel's
# own counters (proc_pid_rusage), in nanoseconds, read before and after the same interval. Leave the Mac alone while it
# runs: moving the pointer over the menu bar is work for Tiroir. Measuring Tiroir itself, the script fails when a number
# is over the budget.
set -euo pipefail
PID="${1:-}"
SECONDS_IDLE="${2:-60}"
fail() { echo "bench: $*" >&2; exit 1; }
if [ -z "$PID" ]; then
  PID=$(pgrep -x Tiroir || true)
  [ -n "$PID" ] || fail "Tiroir is not running: start it, or pass the pid of the process to measure"
  [[ "$PID" =~ ^[0-9]+$ ]] || fail "several processes are called Tiroir ($(echo $PID)): pass the pid to measure"
fi
[[ "$PID" =~ ^[0-9]+$ ]] && [[ "$SECONDS_IDLE" =~ ^[0-9]+$ ]] && [ "$SECONDS_IDLE" -gt 0 ] \
  || fail "usage: scripts/bench.sh [pid] [seconds]"
ps -p "$PID" >/dev/null 2>&1 || fail "no process $PID"
NAME=$(ps -o comm= -p "$PID" | sed 's#.*/##')
echo "Measuring $NAME ($PID) for $SECONDS_IDLE s: leave the Mac alone."

# The processor time, as a percentage of one core over the interval, measured in one Swift process so that compiling
# the snippet does not count as idle time.
CPU=$(swift - "$PID" "$SECONDS_IDLE" <<'SWIFT'
import Foundation

let pid = pid_t(CommandLine.arguments[1])!, seconds = UInt32(CommandLine.arguments[2])!
func processorTime() -> UInt64 {   // user and system time so far, in nanoseconds
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard status == 0 else { exit(1) }
    // The kernel counts in Mach time units: nanoseconds on Intel, ticks of 1/24 µs on Apple silicon.
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
}
let before = processorTime(), start = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
sleep(seconds)
let used = processorTime() - before, elapsed = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - start
print(String(format: "%.4f", Double(used) * 100 / Double(elapsed)))
SWIFT
) || fail "cannot read the processor time of $PID (it quit, or it belongs to another user)"

REPORT=$(footprint -f bytes --noCategories -p "$PID" 2>/dev/null) || fail "footprint cannot read $PID"
# The report, in bytes: "Tiroir [123]: 64-bit    Footprint: 14680064 B (...)" and "phys_footprint_peak: 15728640 B".
FOOTPRINT=$(awk '{ for (i = 1; i < NF; i++) if ($i == "Footprint:") { printf "%.1f", $(i + 1) / 1048576; exit } }' <<<"$REPORT")
PEAK=$(awk '$1 == "phys_footprint_peak:" { printf "%.1f", $2 / 1048576; exit }' <<<"$REPORT")
[ -n "$FOOTPRINT" ] || fail "no footprint in the report of $PID"
echo "footprint: $FOOTPRINT MB"
[ -z "$PEAK" ] || echo "peak: $PEAK MB"
echo "cpu: $CPU %"

if [ "$NAME" = Tiroir ]; then
  if awk -v memory="$FOOTPRINT" -v cpu="$CPU" 'BEGIN { exit !(memory < 30 && cpu < 0.01) }'; then
    echo "Within Tiroir's budget at rest: under 30 MB and 0.01 % of one core."
  else
    fail "over Tiroir's budget at rest: under 30 MB and 0.01 % of one core"
  fi
fi
