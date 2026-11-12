#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Unbounded safety (TODO roadmap A13), each check against its expected outcome:
# - Apalache: IndInv of StreamBufferCounters.tla (read()) holds initially (Init => IndInv) and is
#   inductive (IndInv /\ Next => IndInv'), for N readers and any number of written bytes (Bytes
#   symbolic); it implies the safety properties. Without the re-check of F278 it is not inductive.
#   The same for SafeModInv of StreamBufferRecords.tla (read(b, 0, K): any record size K, any
#   chunking of the writes); for the two-phase read before #212 it is not inductive. And SafeInv
#   of StreamBufferWait.tla (read() readers next to waitForAtLeast(M) callers, any M); before
#   CheckedReturn (waitForAtLeast read availableBytes again for its result) it is not inductive.
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
}

refine() { # module, config
  local log="$work/$2.log"
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$work/$2" \
    -config "$2.cfg" "$1.tla" > "$log" 2>&1
  set -e
  expect "$2" "Model checking completed. No error has been found." "$log"
}

C=StreamBufferCounters
for n in "" 3 4 8 12; do
  label="N=${n:-2}"
  apa "read(): init $label" $C IndInv "ConstInit$n" Init 0 NoError
  apa "read(): inductive $label" $C IndInv "ConstInit$n" IndInit 1 NoError
done
apa "read(): inductive without the re-check (before F278)" $C IndInv ConstInitNoReCheck IndInit 1 Error

R=StreamBufferRecords
for n in "" 3 4; do
  label="N=${n:-2}, any K"
  apa "records: init $label" $R SafeModInv "ConstInit$n" Init 0 NoError
  apa "records: inductive $label" $R SafeModInv "ConstInit$n" SafeModInit 1 NoError
done
apa "records: inductive for the two-phase read (before #212)" $R SafeModInv ConstInitTwoPhase SafeModInit 1 Error

W=StreamBufferWait
for c in "" 22 31; do
  case "$c" in "") label="1 reader, 1 waiter" ;; 22) label="2 readers, 2 waiters" ;; 31) label="3 readers, 1 waiter" ;; esac
  apa "waitForAtLeast: init $label, any M" $W SafeInv "ConstInit$c" Init 0 NoError
  apa "waitForAtLeast: inductive $label, any M" $W SafeInv "ConstInit$c" SafeInit 1 NoError
done
apa "waitForAtLeast: inductive before CheckedReturn" $W SafeInv ConstInitUnchecked SafeInit 1 Error

refine RefineCounters RefineCondition2
refine RefineCounters RefineCondition3
refine RefineRecords RefineRecordsRecords2
refine RefineRecords RefineRecordsChunks2
refine RefineWait RefineWaitWaitAndRead2
refine RefineWait RefineWaitWaitChecked2
exit "$failed"
