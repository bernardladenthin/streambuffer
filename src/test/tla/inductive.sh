#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Unbounded safety (TODO roadmap A13), each check against its expected outcome:
# - Apalache: IndInv of StreamBufferCounters.tla (read()) holds initially (Init => IndInv) and is
#   inductive (IndInv /\ Next => IndInv'), for N readers and any number of written bytes (Bytes
#   symbolic); it implies the safety properties. The same for SafeModInv of StreamBufferRecords.tla
#   (read(b, 0, K): any record size K, any chunking of the writes, several writers) and of
#   StreamBufferWait.tla (read(b, 0, K) readers next to waitForAtLeast(M) callers, any K and M,
#   several writers).
# - No existential of the abstractions ranges over a set a..b that can be empty: Apalache 0.63.0
#   asserts a <= c <= b of \E c \in a..b as a global fact, so a range empty in some state cut
#   every path through that state, whichever action it took (missed violations, an inductive step
#   that skipped pre-states; README, A13).
# - Apalache, the older code: a bounded search from Init reaches a violation of the safety
#   property itself (not just of a helper conjunct): the empty take without the re-check of F278,
#   a torn record with the two-phase read before #212, waitForAtLeast(M) < M on an open buffer
#   before CheckedReturn.
# - TLC: StreamBuffer.tla refines the abstractions in its read(), record and wait configurations, so
#   they are the protocol the detailed model checks, not separate hand-written ones.
# The TLAPS proofs for any number of readers are in proof.sh.
#
# Usage: src/test/tla/inductive.sh <path to tla2tools.jar> <path to apalache-mc>
#        (run from anywhere; needs java on PATH)
set -euo pipefail
jar="$1"
apalache="$2"
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
expect() { # name, expected substring, log
  if grep -qF "$2" "$3"; then
    echo "OK   $1: $2"
  else
    echo "FAIL $1: expected \"$2\""
    grep -E 'The outcome is|Error|error|violated' "$3" | head -3 | sed 's/^/     /'
    failed=1
  fi
}

apa() { # name, module, invariant, constant init, init, length, expected outcome
  local log="$work/apa-$RANDOM.log"
  set +e
  "$apalache" check --out-dir="$work/out" --cinit="$4" --init="$5" --inv="$3" --length="$6" \
    "$2.tla" > "$log" 2>&1
  set -e
  expect "$1" "The outcome is: $7" "$log"
  # an expected violation must be the checked invariant itself, not a tool or parse error
  if [ "$7" = Error ]; then
    expect "$1" "state invariant 0 violated" "$log"
  fi
}

refine() { # module, config
  local log="$work/$2.log"
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$work/$2" \
    -config "$2.cfg" "$1.tla" > "$log" 2>&1
  set -e
  expect "$2" "Model checking completed. No error has been found." "$log"
}

# only ranges that are never empty: 1..Bytes (Bytes >= 1) and 0..left[r] (left is a Nat)
for m in StreamBufferCounters StreamBufferRecords StreamBufferWait; do
  bad="$(sed 's/\\\*.*$//' "$m.tla" | grep -nE '\\E [A-Za-z_]+ \\in [^:]*\.\.' \
    | grep -vE '\\in (1\.\.Bytes|0\.\.left\[r\]) :' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL $m: an existential over a range that can be empty"
    echo "$bad" | sed 's/^/     /'
    failed=1
  else
    echo "OK   $m: no existential over a range that can be empty"
  fi
done

C=StreamBufferCounters
for n in "" 3 4 8 12; do
  label="N=${n:-2}"
  apa "read(): init $label" $C IndInv "ConstInit$n" Init 0 NoError
  apa "read(): inductive $label" $C IndInv "ConstInit$n" IndInit 1 NoError
done
# the code before F278 reaches an empty take: a bounded search from Init finds it
apa "read(): empty take reachable without the re-check (before F278)" $C NoEmptyTake ConstInitNoReCheck Init 14 Error

R=StreamBufferRecords
for c in "" 3 4 W3; do
  case "$c" in "") label="2 readers, 2 writers" ;; 3) label="3 readers, 2 writers" ;; 4) label="4 readers, 2 writers" ;; W3) label="2 readers, 3 writers" ;; esac
  apa "records: init $label, any K" $R SafeModInv "ConstInit$c" Init 0 NoError
  apa "records: inductive $label, any K" $R SafeModInv "ConstInit$c" SafeModInit 1 NoError
done
# the two-phase read before #212 reaches a torn record
apa "records: torn record reachable with the two-phase read (before #212)" $R RecordsAligned ConstInitTwoPhase Init 16 Error

W=StreamBufferWait
for c in "" 22 31; do
  case "$c" in "") label="1 reader, 1 waiter" ;; 22) label="2 readers, 2 waiters" ;; 31) label="3 readers, 1 waiter" ;; esac
  label="$label, 2 writers"
  apa "waitForAtLeast: init $label, any K and M" $W SafeModInv "ConstInit$c" Init 0 NoError
  apa "waitForAtLeast: inductive $label, any K and M" $W SafeModInv "ConstInit$c" SafeModInit 1 NoError
done
# the code before CheckedReturn reaches waitForAtLeast(M) < M on an open buffer
apa "waitForAtLeast: short result on an open buffer reachable before CheckedReturn" $W WaitEnoughOrClosed ConstInitUnchecked Init 14 Error

refine RefineCounters RefineCondition2
refine RefineCounters RefineCondition3
refine RefineRecords RefineRecordsRecords2
refine RefineRecords RefineRecordsChunks2
refine RefineWait RefineWaitWaitAndRead2
refine RefineWait RefineWaitWaitChecked2
exit "$failed"
