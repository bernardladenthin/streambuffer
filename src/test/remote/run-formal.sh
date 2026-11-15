#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side (README.md here): the TLA+ checks of src/test/tla at once, without a time limit.
#   check      check.sh (TLC, every model against its expected outcome)
#   inductive  inductive.sh (Apalache and the TLC refinement checks; needs setup.sh apalache)
#   trace      trace.sh, then trace-controls.sh, over the payload's traces/ (A6)
#   proofs     every module of proof.sh at once, each in a directory of its own (tlapm's cache,
#              .tlacache, is per directory) and in a process group of its own, killed when tlapm
#              ends (tlapm can leave backend provers running, which slow the others into timeouts)
# Results in <payload>/out/formal: one log per check or proof module, progress.log (UTC), DONE.
#
# Usage: <payload>/sb/src/test/remote/run-formal.sh [check] [inductive] [trace] [proofs]
#        (default: all four). Environment: PROOF_THREADS (default cores / 4, at least 2).
# Start it detached (detach.sh), never in the foreground of an ssh session.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
payload="$(cd "$here/../../../.." && pwd)"
# shellcheck disable=SC1091
. "$payload/tools/env.sh"
tla="$payload/sb/src/test/tla"
out="$payload/out/formal"
mkdir -p "$out"
rm -f "$out/DONE"
[ "$#" -gt 0 ] || set -- check inductive trace proofs
args=" $* "
log() { echo "$(date -u +%H:%M:%S) $*" >> "$out/progress.log"; }
timed() { # timed <label> <log> <command...>
  local label="$1" file="$2" s e
  shift 2
  s=$(date +%s)
  "$@" > "$file" 2>&1
  e=$?
  log "$label: exit $e in $(( $(date +%s) - s )) s"
}
log "start:$args commit $(cut -c1-12 "$payload/COMMIT" 2>/dev/null), $(nproc) cores"

case "$args" in *" check "*)
  timed check.sh "$out/check.log" bash "$tla/check.sh" "$TLA2TOOLS" & ;;
esac
case "$args" in *" inductive "*)
  ( PATH="$JAVA21_BIN:$PATH" timed inductive.sh "$out/inductive.log" bash "$tla/inductive.sh" "$TLA2TOOLS" "$APALACHE" ) & ;;
esac
case "$args" in *" trace "*)
  ( timed trace.sh "$out/trace.log" bash "$tla/trace.sh" "$TLA2TOOLS" "$payload/traces"
    timed trace-controls.sh "$out/trace-controls.log" bash "$tla/trace-controls.sh" "$TLA2TOOLS" "$payload/traces" ) & ;;
esac
case "$args" in *" proofs "*)
  threads="${PROOF_THREADS:-$(( $(nproc) / 4 ))}"
  [ "$threads" -ge 2 ] || threads=2
  # the modules and their order as proof.sh has them
  modules="$(sed -n '/^for proof in/,/; do$/p' "$tla/proof.sh" | tr -d '\\' | sed 's/for proof in//; s/; do//')"
  for p in $modules; do
    (
      d="$payload/work/proofs/$p"
      rm -rf "$d"
      mkdir -p "$d"
      cp "$tla"/*.tla "$d/"
      cd "$d" || exit 1
      stretch=3
      case "$p" in *Enabled) stretch=12 ;; esac # as proof.sh: the ENABLED steps under load
      s=$(date +%s)
      setsid "$TLAPM" --threads "$threads" --stretch "$stretch" "$p.tla" > "$out/$p.log" 2>&1 &
      pid=$!
      wait "$pid"
      kill -9 -- "-$pid" 2>/dev/null
      r="$(grep -E 'All [0-9]+ obligations proved|obligations failed' "$out/$p.log" | tail -1)"
      log "proof $p: ${r:-no result} ($(( $(date +%s) - s )) s)"
    ) &
  done ;;
esac
wait
log DONE
touch "$out/DONE"
