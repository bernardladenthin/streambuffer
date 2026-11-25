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

# model | expected TLC message | distinct states (a model that checks clean): a spec edit that
# leaves a branch unreachable keeps every invariant and every expected message, but explores fewer
# states, so the count of a clean model is part of its expected outcome (the vacuity audit of
# 2026-11-25; a model that fails stops at a counterexample, at a count that depends on the
# workers). A change of a spec that changes a count updates it here, with the reason in the commit.
models=(
  "Condition1|Model checking completed. No error has been found.|748"
  "Condition2|Model checking completed. No error has been found.|19124"
  "Condition3|Model checking completed. No error has been found.|408708"
  "Semaphore1|Model checking completed. No error has been found.|447"
  "Semaphore2|Error: Invariant NoEmptyTake is violated."
  "SemaphoreReCheck2|Error: Deadlock reached."
  "ConditionNoReCheck2|Error: Invariant NoEmptyTake is violated."
  "Records2|Model checking completed. No error has been found.|35738"
  "RecordsTwoPhase2|Error: Invariant RecordsWhole is violated."
  "RecordsCountPerEntry2|Error: Invariant AvailLinearizable is violated."
  "Chunks2|Model checking completed. No error has been found.|23776"
  "Mixed2|Model checking completed. No error has been found.|20900"
  "WaitAndRead2|Model checking completed. No error has been found.|3125"
  "SemaphoreWaitAndRead2|Error: Deadlock reached."
  "WaitSnapshot2|Error: Invariant WaitEnoughOrClosed is violated."
  "WaitChecked2|Model checking completed. No error has been found.|4318"
  # up to two spurious wake-ups of Condition.await(); the probe shows that one happens
  "SpuriousCondition2|Model checking completed. No error has been found.|58329"
  "SpuriousCondition3|Model checking completed. No error has been found.|1267691"
  "SpuriousMixed2|Model checking completed. No error has been found.|63639"
  "SpuriousWaitAndRead2|Model checking completed. No error has been found.|9638"
  "SpuriousWaitChecked2|Model checking completed. No error has been found.|13313"
  "SpuriousReached2|Error: Invariant NoSpuriousWake is violated."
  "WaitAlone1|Model checking completed. No error has been found.|164"
  "SpuriousWaitAlone1|Model checking completed. No error has been found.|410"
  # several writers and closers (the bytes shared in commit order); the probes show they interleave
  "Writers2Condition2|Model checking completed. No error has been found.|99069"
  "Closers2Condition2|Model checking completed. No error has been found.|82760"
  "Writers2Records2|Model checking completed. No error has been found.|170131"
  "Writers2Mixed2|Model checking completed. No error has been found.|478703"
  "Writers2WaitChecked2|Model checking completed. No error has been found.|93381"
  "Writers2WaitAndRead2|Model checking completed. No error has been found.|14472"
  "Writers2Reached2|Error: Invariant NoTwoWritersSignalling is violated."
  "Closers2Reached2|Error: Invariant NoTwoClosersSignalling is violated."
  # a word of A18's S6A automaton, accepted without spurious wake-ups since the finally block of
  # the wait is a step of its own (the trace's TraceNotDone violated: every line consumed; the
  # model before ReaderWaitExit rejected it at line 40)
  "TraceSignalBeforeExit@TraceSignalBeforeExit|Error: Invariant TraceNotDone is violated."
  # model@module: threads that call forever; fairness per process, no lock fairness
  "WaitForever2@StreamBufferWaitForever|Model checking completed. No error has been found.|545730"
  "WaitForever3@StreamBufferWaitForever|Model checking completed. No error has been found.|1594802"
  "WaitForever2W2@StreamBufferWaitForever|Model checking completed. No error has been found.|883826"
  "WaitForeverSpurious2@StreamBufferWaitForever|Model checking completed. No error has been found.|1645670"
  "WaitForeverNextOnly2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverNoClose2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # AllStop fails because forever runs exist; that no run gets stuck is WaitForever2, same constants
  "WaitForeverRuns2@StreamBufferWaitForever|Error: Temporal properties were violated."
  "WaitForeverStarve2@StreamBufferWaitForever|Error: Temporal properties were violated."
  # the "max 1 permit" release of an external signal (F280): before, the first fix, since
  "SignalNone2@StreamBufferSignal|Error: Invariant MaxOne is violated."
  "SignalSkip2@StreamBufferSignal|Error: Invariant NoLostSignal is violated."
  "SignalReplay3@StreamBufferSignal|Model checking completed. No error has been found.|70"
  # the argument of the TLAPS proof: the measure, and fairness per thread implies fairness by role
  "WaitForeverMeasure2@StreamBufferWaitForeverLive|Model checking completed. No error has been found.|545730"
  "WaitForeverMeasureSpurious2@StreamBufferWaitForeverLive|Model checking completed. No error has been found.|1645670"
  "WaitForeverRole2@StreamBufferWaitForeverLive|Model checking completed. No error has been found.|545730"
  # the detailed model, every thread calling again when done, forever
  "ForeverWaitAndRead2@StreamBufferForever|Model checking completed. No error has been found.|5454"
  "ForeverWaitChecked2@StreamBufferForever|Model checking completed. No error has been found.|9192"
  "ForeverMixed2@StreamBufferForever|Model checking completed. No error has been found.|28647"
  "ForeverRecords2@StreamBufferForever|Model checking completed. No error has been found.|48290"
  "ForeverChunks2@StreamBufferForever|Model checking completed. No error has been found.|31768"
  "ForeverCondition3@StreamBufferForever|Model checking completed. No error has been found.|606945"
  "ForeverWriters2Mixed2@StreamBufferForever|Model checking completed. No error has been found.|673198"
  "ForeverNextOnlyWaitAndRead2@StreamBufferForever|Error: Temporal properties were violated."
)

failed=0
check() {  # check <entry> [label prefix]: run the model in the current directory
  local model="${1%%|*}" expected="${1#*|}" prefix="${2:-}" module=StreamBuffer log states want=""
  if [[ "$expected" == *"|"* ]]; then
    want="${expected##*|}"
    expected="${expected%|*}"
  fi
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
  if grep -qF "$expected" "$log" && [ -n "$want" ] && [ "${states%% *}" != "$want" ]; then
    echo "FAIL $prefix$model: $expected, but $states, not $want"
    failed=1
  elif grep -qF "$expected" "$log"; then
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
    check "WaitAlone1|Model checking completed. No error has been found.|170" "mutant-"
    check "SpuriousWaitAlone1|Error: Invariant WaitEnoughOrClosed is violated." "mutant-"
    exit "$failed"
  ) || failed=1
else
  echo "FAIL mutant: the step of ReaderWaitLock was not found"
  failed=1
fi

# negative controls of the properties no model of older code violates (the vacuity audit of
# 2026-11-25): each mutant must fail with exactly its property, checked alone in a copy of
# Condition2.cfg (two read() readers of two single-byte writes), so no other invariant fires first
mutate() {  # mutate <label> <property> <INVARIANT|PROPERTY> <expected> <sed program>
  local d="$work/mutant-$1"
  mkdir -p "$d"
  cp ./*.tla "$d/"
  sed -i "$5" "$d/StreamBuffer.tla"
  if cmp -s StreamBuffer.tla "$d/StreamBuffer.tla"; then
    echo "FAIL mutant-$1: the sed program changed nothing"
    failed=1
    return
  fi
  sed -e '/^INVARIANTS$/,$d' Condition2.cfg > "$d/Mutant.cfg"
  printf '%s\n    TypeOK\n' "INVARIANTS" >> "$d/Mutant.cfg"
  if [ "$3" = INVARIANT ]; then
    printf '    %s\n' "$2" >> "$d/Mutant.cfg"
  else
    printf 'PROPERTIES\n    %s\n' "$2" >> "$d/Mutant.cfg"
  fi
  (
    cd "$d"
    check "Mutant|$4" "mutant-$1-"
    exit "$failed"
  ) || failed=1
}
# a read commits its bytes before those taken earlier: the bytes leave the buffer out of order
mutate fifo Fifo INVARIANT "Error: Invariant Fifo is violated." \
  's/^    \/\\ taken. = taken \\o hold\[r\]$/    \/\\ taken\x27 = hold[r] \\o taken/'
# a reader's reads are kept newest first: what one reader got is out of order
mutate order ReaderOrder INVARIANT "Error: Invariant ReaderOrder is violated." \
  's/THEN \/\\ reads. = \[reads EXCEPT !\[r\] = Append(@, c)\]/THEN \/\\ reads\x27 = [reads EXCEPT ![r] = <<c>> \\o @]/'
# a reader at the end of a closed stream starts again instead of returning -1: it keeps taking
# steps (no deadlock, which the older code's controls show) and never finishes
mutate livelock AllReadersFinish PROPERTY "Error: Temporal properties were violated." \
  '/^ReaderEof(r) ==$/,/^$/ s/Goto(r, "done")/Goto(r, "start")/'

# every model is run: each .cfg here is an entry above, a model of inductive.sh, or a ConstCache one
for cfg in ./*.cfg; do
  n="$(basename "$cfg" .cfg)"
  if ! grep -qE "(^|[^A-Za-z0-9])$n([^A-Za-z0-9]|\$)" check.sh inductive.sh \
     && ! { [[ "$n" == RefineWait* ]] && grep -qE "^for c in .*\b${n#RefineWait}\b|^ +.*\b${n#RefineWait}\b.*; do$" inductive.sh; }; then
    echo "FAIL $n.cfg: no script runs it"
    failed=1
  fi
done
exit "$failed"
