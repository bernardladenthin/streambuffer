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
# StreamBufferSignal.tla: the "max 1 permit" release of an external signal (F280).
#
# Usage: src/test/tla/check.sh <path to tla2tools.jar>   (run from anywhere; needs java on PATH)
set -euo pipefail
jar="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
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
  # up to two spurious wake-ups of Condition.await(); the probe shows that one happens
  "SpuriousCondition2|Model checking completed. No error has been found."
  "SpuriousCondition3|Model checking completed. No error has been found."
  "SpuriousMixed2|Model checking completed. No error has been found."
  "SpuriousWaitAndRead2|Model checking completed. No error has been found."
  "SpuriousWaitChecked2|Model checking completed. No error has been found."
  "SpuriousReached2|Error: Invariant NoSpuriousWake is violated."
  "WaitAlone1|Model checking completed. No error has been found."
  "SpuriousWaitAlone1|Model checking completed. No error has been found."
  # several writers and closers (the bytes shared in commit order); the probes show they interleave
  "Writers2Condition2|Model checking completed. No error has been found."
  "Closers2Condition2|Model checking completed. No error has been found."
  "Writers2Records2|Model checking completed. No error has been found."
  "Writers2Mixed2|Model checking completed. No error has been found."
  "Writers2WaitChecked2|Model checking completed. No error has been found."
  "Writers2WaitAndRead2|Model checking completed. No error has been found."
  "Writers2Reached2|Error: Invariant NoTwoWritersSignalling is violated."
  "Closers2Reached2|Error: Invariant NoTwoClosersSignalling is violated."
  # model@module: threads that call forever; fairness per process, no lock fairness
  "WaitForever2@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForever3@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForever2W2@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForeverSpurious2@StreamBufferWaitForever|Model checking completed. No error has been found."
  "WaitForeverNextOnly2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverNoClose2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # AllStop fails because forever runs exist; that no run gets stuck is WaitForever2, same constants
  "WaitForeverRuns2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverStarve2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # the "max 1 permit" release of an external signal (F280): before, the first fix, since
  "SignalNone2@StreamBufferSignal|Error: Invariant MaxOne is violated."
  "SignalSkip2@StreamBufferSignal|Error: Invariant NoLostSignal is violated."
  "SignalReplay3@StreamBufferSignal|Model checking completed. No error has been found."
  # the argument of the TLAPS proof: the measure, and fairness per thread implies fairness by role
  "WaitForeverMeasure2@StreamBufferWaitForeverLive|Model checking completed. No error has been found."
  "WaitForeverMeasureSpurious2@StreamBufferWaitForeverLive|Model checking completed. No error has been found."
  "WaitForeverRole2@StreamBufferWaitForeverLive|Model checking completed. No error has been found."
  # the detailed model, every thread calling again when done, forever
  "ForeverWaitAndRead2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverWaitChecked2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverMixed2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverRecords2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverChunks2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverCondition3@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverWriters2Mixed2@StreamBufferForever|Model checking completed. No error has been found."
  "ForeverNextOnlyWaitAndRead2@StreamBufferForever|Error: Temporal properties were violated."
)

failed=0
check() {  # check <entry> [label prefix]: run the model in the current directory
  local model="${1%%|*}" expected="${1#*|}" prefix="${2:-}" module=StreamBuffer log states
  if [[ "$model" == *@* ]]; then
    module="${model#*@}"
    model="${model%@*}"
  fi
  log="$work/$prefix$model.log"
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -metadir "$work/$prefix$model" \
    -config "$model.cfg" "$module.tla" > "$log" 2>&1
  set -e
  states="$(grep -oE '[0-9]+ distinct states found' "$log" | tail -1 || true)"
  if grep -qF "$expected" "$log"; then
    echo "OK   $prefix$model: $expected ($states)"
  else
    echo "FAIL $prefix$model: expected \"$expected\""
    grep -E 'Error:|No error has been found' "$log" | head -3 | sed 's/^/     /'
    failed=1
  fi
}
for entry in "${models[@]}"; do
  check "$entry"
done

# a table substituted in the cfg (GEdge <- TEdge, TraceLog <- TTrace) is evaluated once, not at
# every step: TLC 1.7.4 evaluates such a constant anew at every use (tlaplus issue 648), and A18's
# products, which read the automaton's table at each step, ran at ~1,000 states a minute (S3A, 4
# days). TraceGraph.tla and TraceStreamBuffer.tla read them through definitions of their own, which
# TLC evaluates once; the modules print a line at each evaluation (3 at the start, per table), the
# old modules printed one at nearly every step (44 and 345 over 21 and 97 states).
cached() {  # cached <module> <table>...: each table evaluated at most 3 times, over 10+ states
  local m="$1" log="$work/$1.log" n states
  shift
  set +e
  java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers 1 -metadir "$work/$m" -config "$m.cfg" "$m.tla" \
    > "$log" 2>&1
  set -e
  states="$(grep -oE '[0-9]+ distinct states found' "$log" | tail -1 | grep -oE '^[0-9]+' || true)"
  if ! grep -qF "Model checking completed. No error has been found." "$log" || [ "${states:-0}" -lt 10 ]; then
    echo "FAIL $m: did not complete over 10 or more states (${states:-no} states)"
    grep -E 'Error' "$log" | head -3 | sed 's/^/     /'
    failed=1
    return
  fi
  for table in "$@"; do
    n="$(grep -cF "ConstCache: $table evaluated" "$log" || true)"
    if [ "$n" -gt 3 ]; then
      echo "FAIL $m: $table evaluated $n times over $states states (read at every step)"
      failed=1
    else
      echo "OK   $m: $table evaluated $n times over $states states"
    fi
  done
}
cached ConstCacheGraph TEdge TOut
cached ConstCacheTrace TTrace

# the negative control of the spurious wake-ups: a mutant whose woken thread skips the test of its
# loop (ReaderWaitLock goes to "wret" instead of "test"). Next to a lone waitForAtLeast(2) every
# signal wakes it to enough bytes or a closed buffer, so the mutant checks clean without spurious
# wake-ups and returns short on an open buffer with them: the step reaches what the test is for.
mutant="$work/mutant"
mkdir -p "$mutant"
cp ./*.tla ./*.cfg "$mutant/"
sed -i 's/Goto(r, IF rpc\[r\] = "lockwait" THEN "inc" ELSE "test")/Goto(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "wret")/' \
  "$mutant/StreamBuffer.tla"
if grep -q 'THEN "inc" ELSE "wret")' "$mutant/StreamBuffer.tla"; then
  (
    cd "$mutant"
    check "WaitAlone1|Model checking completed. No error has been found." "mutant-"
    check "SpuriousWaitAlone1|Error: Invariant WaitEnoughOrClosed is violated." "mutant-"
    exit "$failed"
  ) || failed=1
else
  echo "FAIL mutant: the step of ReaderWaitLock was not found"
  failed=1
fi
exit "$failed"
