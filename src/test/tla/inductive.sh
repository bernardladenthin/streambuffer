#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Unbounded safety of the read() protocol (TODO roadmap A13), each check against its expected
# outcome:
# - Apalache: IndInv of StreamBufferCounters.tla holds initially (Init => IndInv) and is inductive
#   (IndInv /\ Next => IndInv'), for N readers and any number of written bytes (Bytes symbolic);
#   IndInv implies the safety properties. Without the re-check of F278 it is not inductive.
# - TLC: StreamBuffer.tla refines StreamBufferCounters.tla in the read() configurations, so the
#   abstraction is the one the detailed model checks, not a separate hand-written protocol.
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

apa() { # name, constant init, init, length, expected outcome
  local log="$work/$1.log"
  set +e
  "$apalache" check --out-dir="$work/out-$1" --cinit="$2" --init="$3" --inv=IndInv --length="$4" \
    StreamBufferCounters.tla > "$log" 2>&1
  set -e
  expect "$1" "The outcome is: $5" "$log"
}

for n in "" 3 4 8 12; do
  label="N=${n:-2}"
  apa "init $label" "ConstInit$n" Init 0 NoError
  apa "inductive $label" "ConstInit$n" IndInit 1 NoError
done
apa "inductive without the re-check (before F278)" ConstInitNoReCheck IndInit 1 Error

for model in RefineCondition2 RefineCondition3; do
  log="$work/$model.log"
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$work/$model" \
    -config "$model.cfg" RefineCounters.tla > "$log" 2>&1
  set -e
  expect "$model" "Model checking completed. No error has been found." "$log"
done
exit "$failed"
