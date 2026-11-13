#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Runs every TLC model and compares each with its expected outcome: the models of the current code
# must check clean, the models of older code and the negative controls must fail with exactly the
# error that shows the defect (so the spec can fail, and fails for the right reason). A model is
# its .cfg; it checks StreamBuffer.tla unless the entry names another module.
# StreamBufferWaitForever.tla: liveness with threads that call forever (TODO, A13 follow-up).
#
# Usage: src/test/tla/check.sh <path to tla2tools.jar>   (run from anywhere; needs java on PATH)
set -euo pipefail
jar="$1"
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# model | expected TLC message
models=(
  "Condition1|Model checking completed. No error has been found."
  "Condition2|Model checking completed. No error has been found."
  "Condition3|Model checking completed. No error has been found."
  "Semaphore1|Model checking completed. No error has been found."
  "Semaphore2|Error: Invariant NoEmptyTake is violated."
  "SemaphoreReCheck2|Error: Deadlock reached."
  "ConditionNoReCheck2|Error: Invariant NoEmptyTake is violated."
  "Records2|Model checking completed. No error has been found."
  "RecordsTwoPhase2|Error: Invariant RecordsWhole is violated."
  "RecordsCountPerEntry2|Error: Invariant AvailLinearizable is violated."
  "Chunks2|Model checking completed. No error has been found."
  "Mixed2|Model checking completed. No error has been found."
  "WaitAndRead2|Model checking completed. No error has been found."
  "SemaphoreWaitAndRead2|Error: Deadlock reached."
  "WaitSnapshot2|Error: Invariant WaitEnoughOrClosed is violated."
  "WaitChecked2|Model checking completed. No error has been found."
  # model@module: threads that call forever; fairness per process, no lock fairness
  "WaitForever2@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForever3@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForever2W2@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForeverNextOnly2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverNoClose2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # AllStop fails because forever runs exist; that no run gets stuck is WaitForever2, same constants
  "WaitForeverRuns2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverStarve2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # the argument of the TLAPS proof: the measure, and fairness per thread implies fairness by role
  "WaitForeverMeasure2@StreamBufferWaitForeverLive|Model checking completed. No error has been found."
  "WaitForeverRole2@StreamBufferWaitForeverLive|Model checking completed. No error has been found."
  # the detailed model, every thread calling again when done, forever
  "ForeverWaitAndRead2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverWaitChecked2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverMixed2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverRecords2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverChunks2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverCondition3@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverNextOnlyWaitAndRead2@StreamBufferForever|Error: Temporal properties were violated."
)

failed=0
for entry in "${models[@]}"; do
  model="${entry%%|*}"
  expected="${entry#*|}"
  module=StreamBuffer
  if [[ "$model" == *@* ]]; then
    module="${model#*@}"
    model="${model%@*}"
  fi
  log="$work/$model.log"
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$work/$model" \
    -config "$model.cfg" "$module.tla" > "$log" 2>&1
  set -e
  states="$(grep -oE '[0-9]+ distinct states found' "$log" | tail -1 || true)"
  if grep -qF "$expected" "$log"; then
    echo "OK   $model: $expected ($states)"
  else
    echo "FAIL $model: expected \"$expected\""
    grep -E 'Error:|No error has been found' "$log" | head -3 | sed 's/^/     /'
    failed=1
  fi
done
exit "$failed"
