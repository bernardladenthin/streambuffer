#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side (README.md here): lifts the time limit of a run that is already going, for runs
# started under `timeout <seconds> ...` (the scripts here set none). GNU timeout's limit cannot be
# changed, and killing timeout is wrong: its caller then takes the scenario as ended and cleans
# up under it (a deleted dump the running TLC still writes). Instead each matching timeout is
# stopped (SIGSTOP; its child computes on) and continued only once that child has ended, so the
# caller then logs and cleans up as usual. The caller sees exit 124 once the limit has passed;
# the child's own log is the result. Logs to stdout; start it with detach.sh.
#
# Usage: lift-timeout.sh <text the timeout command line must contain>   (required: the machine
# may be shared, and another's timeout is not ours to stop)
set -u
pattern="${1:-}"
[ -n "$pattern" ] || { echo "usage: lift-timeout.sh <text of the timeout command line>" >&2; exit 2; }
declare -A child
for t in $(pgrep -x timeout); do
  tr '\0' ' ' < "/proc/$t/cmdline" | grep -qF -- "$pattern" || continue
  c="$(pgrep -P "$t" | head -n 1)"
  [ -n "$c" ] || continue
  kill -STOP "$t"
  child[$t]="$c"
  echo "$(date -u +%H:%M:%S) timeout $t stopped, its child $c computes on"
done
[ "${#child[@]}" -gt 0 ] || { echo "no matching timeout process"; exit 1; }
while [ "${#child[@]}" -gt 0 ]; do
  sleep 60
  for t in "${!child[@]}"; do
    st="$(ps -o stat= -p "${child[$t]}" 2>/dev/null | cut -c1)"
    if [ -z "$st" ] || [ "$st" = Z ]; then
      kill -CONT "$t" 2>/dev/null
      echo "$(date -u +%H:%M:%S) child ${child[$t]} ended, timeout $t continued"
      unset "child[$t]"
    fi
  done
done
echo "$(date -u +%H:%M:%S) all ended"
