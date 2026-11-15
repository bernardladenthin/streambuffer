#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side (README.md here): one look at a long run, for a check every 30 minutes. Prints the
# progress logs of run-a18.sh and run-formal.sh, the result lines of each scenario or check so far,
# the processes that compute, load, memory and disk, and a WARN line for each sign that the run
# should be stopped rather than paid for: memory or disk almost full, or nothing computing while
# a run has no DONE. Exit 0 all well, 1 a WARN, 2 every run DONE.
#
# Usage: <payload>/sb/src/test/remote/status.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
payload="$(cd "$here/../../../.." && pwd)"
warn=0
w() { echo "WARN  $*"; warn=1; }
runs=0
done_runs=0
for d in "$payload"/out/a18 "$payload"/out/formal; do
  [ -d "$d" ] || continue
  runs=$(( runs + 1 ))
  echo "== $(basename "$d"): $(test -f "$d/DONE" && echo DONE || echo running)"
  [ -f "$d/DONE" ] && done_runs=$(( done_runs + 1 ))
  tail -n 15 "$d/progress.log" 2>/dev/null | sed 's/^/   /'
  for f in "$d"/*.log; do
    case "$(basename "$f")" in progress.log) continue ;; esac
    lines="$(grep -E '^ *(JPF|TLC) |^OK|^FAIL|^SKIP|minimal dfa|obligations (proved|failed)|^traces:' "$f" 2>/dev/null \
      | sed 's/^ *//' | tr '\n' ';' | cut -c1-400)"
    echo "   $(basename "$f" .log): ${lines:-(nothing yet)}"
  done
done
[ "$runs" -gt 0 ] || echo "no run under $payload/out"
# java runs by their command line; the provers by their exact name (Isabelle runs as poly)
computing=$(( $(pgrep -c -f 'RunJPF|tlc2.TLC|apalache' 2>/dev/null; true) + $(pgrep -c -x 'tlapm|z3|zenon|poly' 2>/dev/null; true) ))
echo "== computing processes: $computing"
uptime
free -g | sed -n '1,2p'
df -h "$payload" | tail -n 1
avail_pct=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) * 100 / $(awk '/MemTotal/ {print $2}' /proc/meminfo) ))
disk_pct="$(df --output=pcent "$payload" | tail -n 1 | tr -dc 0-9)"
[ "$avail_pct" -ge 10 ] || w "memory: only $avail_pct % available"
[ "$disk_pct" -le 90 ] || w "disk: $disk_pct % used"
if [ "$runs" -gt "$done_runs" ] && [ "$computing" -eq 0 ]; then
  w "a run has no DONE, but nothing computes (crashed or killed?)"
fi
[ "$warn" -eq 0 ] || exit 1
[ "$runs" -eq 0 ] || [ "$runs" -gt "$done_runs" ] || exit 2
exit 0
