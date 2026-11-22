#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Roadmap A18: every interleaving JPF explores of one scenario is a run of the model.
#   1. JPF runs JpfTraceHarness over the instrumented class of A6 (TracedClassDump's output), with
#      state matching, and GraphExport writes the state graph, each transition labelled with the
#      accesses it logged;
#   2. graphmin.py reduces it to the minimal deterministic automaton over those events, a module of
#      TraceGraph.tla;
#   3. TLC dumps the product of that automaton and the trace acceptance of TraceStreamBuffer.tla;
#   4. GraphCheck.java decides, by a subset construction, whether every word of the automaton is
#      accepted; an empty set of model states is a counterexample, printed as its word. It is
#      graphcheck.py (the reference) in at most about 70 bytes per product state instead of
#      about 700; with zstd on the path TLC's dump goes through it into product.dot.zst (S6A:
#      3.32 GB to 0.22 GB, 15:1).
# With "controls" it also checks that the chain fails where it must: a model whose writer never
# signals, a corrupted returned byte, and a class whose reads (readSingleByte, readIntoArray) do not
# lower the count.
#
# Usage: src/test/jpf/trace/check-graph.sh <name> <bytes> <chunk> <read length> <read() readers>
#          <record readers> <waitForAtLeast callers> <after|any> [controls]
# Environment: JPF_CORE (jpf-core, built), JAVA_JPF (a JDK 11 java for JPF), JAVA_TLC (java 11+
#   for TLC), TLA2TOOLS (the jar), TRACED (the instrumented class files), TRACED_MUTANT (the same
#   with TracedClassDump's no-decrement, for the controls), LIB (the annotation jars:
#   checker-qual.jar, jspecify.jar, error-prone-annotations.jar), WORK (a scratch directory),
#   JPF_HEAP (default 6g), TLC_WORKERS (default auto), TLC_HEAP (optional: TLC's -Xmx; the JVM's
#   default is a quarter of the memory, and a product of millions of states grows past it), GRAPHMIN_LOCK (optional: a lock file, so
#   that the graphmin.py of scenarios run at once take turns; each holds its whole graph in
#   memory, about 0.7 GB per GB of graph), REUSE_GRAPH (1: take the graph and JPF log of an earlier run
#   in the same WORK instead of running JPF again, checked as a new one is: to finish a scenario
#   whose later steps were cut off, without repeating a day of JPF), GRAPHCHECK_HEAP (optional:
#   GraphCheck's -Xmx), GRAPHCHECK_REFERENCE (1: run graphcheck.py too and fail unless both print
#   the same; for small scenarios, it needs about 700 bytes per product state).
set -euo pipefail
name="$1" bytes="$2" chunk="$3" readlen="$4" nbyte="$5" nrecord="$6" nwait="$7" close="$8"
controls="${9:-}"
here="$(cd "$(dirname "$0")" && pwd)"
tla="$(cd "$here/../../tla" && pwd)"
py="$(command -v python3 || command -v python)"
javac_jpf="$(dirname "$JAVA_JPF")/javac"
mkdir -p "$WORK"
failed=0

# the reader names of the harness: r1.. as read() readers, record readers, wait callers
readers="" byte_readers="" wait_callers=""
n=$((nbyte + nrecord + nwait))
for ((i = 1; i <= n; i++)); do
  readers="${readers:+$readers,}r$i"
  if [ "$i" -le "$nbyte" ]; then byte_readers="${byte_readers:+$byte_readers,}r$i"; fi
  if [ "$i" -gt $((nbyte + nrecord)) ]; then wait_callers="${wait_callers:+$wait_callers,}r$i"; fi
done

jpf_graph() {  # jpf_graph <label> <traced classes> [mutant]: writes $WORK/<label>.graph
  local out="$WORK/$1-classes"
  rm -rf "$out" && mkdir -p "$out"
  "$javac_jpf" --release 8 -nowarn -cp "$2:$LIB/*:$JPF_CORE/build/jpf-classes.jar:$JPF_CORE/build/jpf.jar" -d "$out" \
    "$here/net/ladenthin/streambuffer/trace/TraceRecorder.java" \
    "$here/net/ladenthin/streambuffer/jpf/JpfTraceHarness.java" \
    "$here/net/ladenthin/streambuffer/jpf/GraphExport.java"
  cat > "$WORK/$1.jpf" <<EOF
target = net.ladenthin.streambuffer.jpf.JpfTraceHarness
target.args = $bytes,$chunk,$readlen,$nbyte,$nrecord,$nwait,false,$close
classpath = $out;$2;$LIB/checker-qual.jar;$LIB/jspecify.jar;$LIB/error-prone-annotations.jar;$JPF_CORE/build/jpf-classes.jar
native_classpath+=;$out
listener = net.ladenthin.streambuffer.jpf.GraphExport
graph.out = $WORK/$1.graph
vm.enable_assertions = true
# a yield is the scheduling point of every logged access (the JPF tracer); set, not left to the default
cg.threads.break_yield = true
EOF
  local s
  s=$(date +%s)
  "$JAVA_JPF" "-Xmx${JPF_HEAP:-6g}" -jar "$JPF_CORE/build/RunJPF.jar" "$WORK/$1.jpf" > "$WORK/$1.jpf.log" 2>&1 || true
  echo "  JPF $1: $(grep -oE 'new=[0-9]+' "$WORK/$1.jpf.log" | head -1) states, $(grep -cE '^error #' "$WORK/$1.jpf.log" || true) errors, $(( $(date +%s) - s )) s"
  graph_ok "$@"
}

graph_ok() {  # graph_ok <label> <traced classes> [mutant]: $WORK/<label>.graph is a whole search
  # the graph is the whole search only if JPF finished it: no error (it stops at the first one),
  # and the listener's trailer written; the class mutant is expected to stop at its error
  if ! tail -c 4096 "$WORK/$1.graph" 2>/dev/null | grep -q '^# edges '; then
    echo "FAIL  JPF $1: the graph is incomplete (no trailer)"
    return 1
  fi
  if [ -z "${3:-}" ] && ! grep -q 'no errors detected' "$WORK/$1.jpf.log"; then
    echo "FAIL  JPF $1: JPF reported an error or did not finish; the graph is no complete search"
    grep -A3 '^error #' "$WORK/$1.jpf.log" | head -8 | sed 's/^/      /'
    return 1
  fi
}

product() {  # product <label> <graph> <model dir> [sed for the cfg]: TLC's dump and the check
  local d="$WORK/$1"
  rm -rf "$d" && mkdir -p "$d"
  cp "$3/StreamBuffer.tla" "$3/TraceStreamBuffer.tla" "$3/TraceGraph.tla" "$d/"
  local lock=()
  [ -z "${GRAPHMIN_LOCK:-}" ] || lock=(flock "$GRAPHMIN_LOCK")
  "${lock[@]}" "$py" -I "$here/graphmin.py" "$2" "Graph_$name" "$d" "$readers" "$byte_readers" "$wait_callers" \
    "$bytes" "$chunk" "$readlen" > "$d/graphmin.log" 2>&1 || { sed 's/^/  /' "$d/graphmin.log"; return 2; }
  sed 's/^/  /' "$d/graphmin.log"
  if [ -n "${4:-}" ]; then sed -i "$4" "$d/Graph_$name.cfg" || return 2; fi
  local s dump="$d/product.dot" zpid=""
  s=$(date +%s)
  # with zstd, TLC writes its dump into a pipe that zstd compresses (about 6:1; the plain dump of
  # S3A was 29 GB): TLC opens product.dot as a file, and the fifo there is zstd's input
  if command -v zstd > /dev/null && mkfifo "$d/product.dot"; then
    dump="$d/product.dot.zst"
    zstd -q -T2 -f -o "$dump" < "$d/product.dot" &
    zpid=$!
  fi
  (cd "$d" && "$JAVA_TLC" -XX:+UseParallelGC ${TLC_HEAP:+"-Xmx$TLC_HEAP"} -cp "$TLA2TOOLS" tlc2.TLC -workers "${TLC_WORKERS:-auto}" \
     -dump dot,actionlabels product.dot -config "Graph_$name.cfg" "Graph_$name.tla" > tlc.log 2>&1) || true
  local ze=0
  if [ -n "$zpid" ]; then
    # a TLC that stopped before it opened the dump leaves zstd waiting for a writer
    if kill -0 "$zpid" 2> /dev/null; then timeout 10 sh -c ': > "$1"' _ "$d/product.dot" || true; fi
    wait "$zpid" || ze=$?
    rm -f "$d/product.dot"
  fi
  echo "  TLC $1: $(grep -oE '[0-9]+ distinct states found' "$d/tlc.log" | tail -1), $(( $(date +%s) - s )) s"
  if ! grep -q 'Model checking completed. No error has been found.' "$d/tlc.log" || [ ! -s "$dump" ] || [ "$ze" != 0 ]; then
    echo "  TLC $1 did not complete; no result"
    grep -E 'Error' "$d/tlc.log" | head -3 | sed 's/^/    /'
    [ "$ze" = 0 ] || echo "    zstd exit $ze"
    return 2
  fi
  local e=0
  "$JAVA_TLC" ${GRAPHCHECK_HEAP:+"-Xmx$GRAPHCHECK_HEAP"} "$here/GraphCheck.java" "$dump" "$d/Graph_$name.tla" \
    > "$d/check.log" 2>&1 || e=$?
  grep -E '^OK|^REJECTED|^FAIL' "$d/check.log" | head -1 | sed 's/^/  /'
  if [ "${GRAPHCHECK_REFERENCE:-}" = 1 ]; then
    # the reference: graphcheck.py must print the same (timings aside) and exit the same
    local re=0
    "$py" -I "$here/graphcheck.py" "$dump" "$d/Graph_$name.tla" > "$d/check-reference.log" 2>&1 || re=$?
    if [ "$re" != "$e" ] || ! diff <(sed -E 's/ \([0-9.]+s\)//' "$d/check-reference.log") \
        <(sed -E 's/ \([0-9.]+s\)//' "$d/check.log") > "$d/check-diff.log"; then
      echo "  FAIL  GraphCheck.java (exit $e) and graphcheck.py (exit $re) differ:"
      head -10 "$d/check-diff.log" | sed 's/^/    /'
      rm -f "$dump"
      return 2
    fi
    echo "  GraphCheck.java and graphcheck.py agree (exit $e)"
  fi
  rm -f "$dump"
  return "$e"
}

expect() {  # expect <label> <0 accepted | 1 rejected> <command...>
  local label="$1" want="$2"
  shift 2
  local e=0
  "$@" || e=$?
  if [ "$want" = 0 ] && [ "$e" = 0 ]; then echo "OK    $label: every word accepted"
  elif [ "$want" = 1 ] && [ "$e" = 3 ]; then echo "OK    $label: rejected, as it must be"
  else echo "FAIL  $label (exit $e: 0 accepted, 3 rejected, else no result)"; failed=1
  fi
}

if [ "${REUSE_GRAPH:-}" = 1 ]; then
  echo "  JPF $name: the graph of an earlier run, $(grep -oE 'new=[0-9]+' "$WORK/$name.jpf.log" | head -1) states"
  graph_ok "$name" "$TRACED" || exit 1
else
  jpf_graph "$name" "$TRACED" || exit 1
fi
expect "$name" 0 product "$name" "$WORK/$name.graph" "$tla"
if [ "$controls" = controls ]; then
  mutant="$WORK/model-nosignal"
  rm -rf "$mutant" && mkdir -p "$mutant" && cp "$tla/StreamBuffer.tla" "$tla/TraceStreamBuffer.tla" "$tla/TraceGraph.tla" "$mutant/"
  sed -i 's/IF waiters # 0 THEN "siglock" ELSE WriterDone/WriterDone/' "$mutant/StreamBuffer.tla"
  if grep -q 'ELSE WriterDone' "$mutant/StreamBuffer.tla"; then echo "FAIL  the writer's signal not found"; failed=1; fi
  # no spurious wake-ups here: they could explain the wake-ups the missing signal leaves out
  expect "control: the model's writer never signals" 1 \
    product "$name-nosignal" "$WORK/$name.graph" "$mutant" 's/    Spurious = [0-9]*/    Spurious = 0/'
  corrupt="$WORK/$name-byte.graph"
  "$py" -I - "$WORK/$name.graph" "$corrupt" <<'EOF'
import re, sys
# the first byte a read returned; in a scenario without reads, the count a waitForAtLeast returned.
# Line by line (a graph of two readers is 9 GB): first the line to change, then the copy.
ret, wfa = re.compile(r"\tret\t\d+\t\d+\t(\d+)"), re.compile(r"\twfa\t\d+\t(-?\d+)\t")
target = None
first_wfa = None
with open(sys.argv[1], encoding="utf-8") as f:
    for k, line in enumerate(f):
        if ret.search(line):
            target = (k, ret)
            break
        if first_wfa is None and wfa.search(line):
            first_wfa = k
if target is None:
    target = (first_wfa, wfa)
with open(sys.argv[1], encoding="utf-8") as f, open(sys.argv[2], "w", encoding="utf-8", newline="\n") as out:
    for k, line in enumerate(f):
        if k == target[0]:
            m = target[1].search(line)
            line = line[:m.start(1)] + str(int(m.group(1)) + 1) + line[m.end(1):]
        out.write(line)
EOF
  expect "control: a returned byte (or count) + 1 in the graph" 1 product "$name-byte" "$corrupt" "$tla"
  if [ $((nbyte + nrecord)) -gt 0 ]; then
    jpf_graph "$name-mutant" "$TRACED_MUTANT" mutant || failed=1
    expect "control: the reads do not lower the count" 1 product "$name-mutant" "$WORK/$name-mutant.graph" "$tla"
  else
    # the mutation is on the read paths, which a scenario of waitForAtLeast callers only never runs
    echo "SKIP  control: the reads do not lower the count (no reader in this scenario)"
  fi
fi
exit "$failed"
