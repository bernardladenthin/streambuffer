#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side (README.md here): the A18 graph check (src/test/jpf/trace/check-graph.sh) for every
# scenario of a list, with its controls, several at once and WITHOUT a time limit: a scenario runs
# until it ends (a scenario cut off at a limit has no result, and the hours up to it are lost);
# status.sh shows how far each one is. Results in <payload>/out/a18: <name>.log per scenario,
# progress.log (one line per scenario, UTC), DONE once all have ended.
#
# Usage: <payload>/sb/src/test/remote/run-a18.sh [scenarios file] [parallel]
#   scenarios file  lines "<name> <bytes> <chunk> <read length> <read() readers> <record readers>
#                   <wait callers> <after|any>" (default: a18-scenarios.txt next to this script)
#   parallel        scenarios at once (default: memory / (JPF_HEAP + 3 GB), at most cores / 4)
# Environment: JPF_HEAP (default 7g; JPF is single-threaded and needs the heap), TLC_WORKERS
#   (default 4: the product's TLC run, single-threaded in its dump anyway).
# Start it detached (detach.sh), never in the foreground of an ssh session.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
payload="$(cd "$here/../../../.." && pwd)"
# shellcheck disable=SC1091
. "$payload/tools/env.sh"
list="${1:-$here/a18-scenarios.txt}"
heap="${JPF_HEAP:-7g}"
mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
par="${2:-$(( mem_gb / (${heap%g} + 3) ))}"
cap=$(( $(nproc) / 4 ))
[ -n "${2:-}" ] || [ "$par" -le "$cap" ] || par="$cap"
[ "$par" -ge 1 ] || par=1
out="$payload/out/a18"
mkdir -p "$out"
rm -f "$out/DONE"
log() { echo "$(date -u +%H:%M:%S) $*" >> "$out/progress.log"; }
log "start: $(grep -c . "$list") scenarios, $par at once, JPF heap $heap, $mem_gb GB, $(nproc) cores, commit $(cut -c1-12 "$payload/COMMIT" 2>/dev/null)"

one() { # one <name> <args...>
  local name="$1"
  shift
  local s e
  s=$(date +%s)
  WORK="$payload/work/a18/$name" JPF_HEAP="$heap" TLC_WORKERS="${TLC_WORKERS:-4}" \
    bash "$payload/sb/src/test/jpf/trace/check-graph.sh" "$name" "$@" controls > "$out/$name.log" 2>&1
  e=$?
  log "$name ($*): exit $e in $(( $(date +%s) - s )) s; $(grep -cE '^OK' "$out/$name.log") OK, $(grep -cE '^FAIL' "$out/$name.log") FAIL, $(grep -cE '^SKIP' "$out/$name.log") SKIP"
  # TLC's dump of the product is the big file (GBs); the logs keep the numbers
  rm -f "$payload/work/a18/$name"/*/product.dot
}
export -f one log
export payload out heap
grep -v '^#' "$list" | grep . | xargs -P "$par" -L 1 bash -c 'one "$@"' _
log DONE
touch "$out/DONE"
