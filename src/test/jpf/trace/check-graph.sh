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
#   4. graphcheck.py decides, by a subset construction, whether every word of the automaton is
#      accepted; an empty set of model states is a counterexample, printed as its word.
# With "controls" it also checks that the chain fails where it must: a model whose writer never
# signals, a corrupted returned byte, and a class whose readSingleByte does not lower the count.
#
# Usage: src/test/jpf/trace/check-graph.sh <name> <bytes> <chunk> <read length> <read() readers>
#          <record readers> <waitForAtLeast callers> <after|any> [controls]
# Environment: JPF_CORE (jpf-core, built), JAVA_JPF (a JDK 11 java for JPF), JAVA_TLC (java 11+
#   for TLC), TLA2TOOLS (the jar), TRACED (the instrumented class files), TRACED_MUTANT (the same
#   with TracedClassDump's no-decrement, for the controls), LIB (the annotation jars:
#   checker-qual.jar, jspecify.jar, error-prone-annotations.jar), WORK (a scratch directory),
#   JPF_HEAP (default 6g), TLC_WORKERS (default auto).
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

jpf_graph() {  # jpf_graph <label> <traced classes>: writes $WORK/<label>.graph
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
EOF
  local s
  s=$(date +%s)
  "$JAVA_JPF" "-Xmx${JPF_HEAP:-6g}" -jar "$JPF_CORE/build/RunJPF.jar" "$WORK/$1.jpf" > "$WORK/$1.jpf.log" 2>&1 || true
  echo "  JPF $1: $(grep -oE 'new=[0-9]+' "$WORK/$1.jpf.log" | head -1) states, $(grep -cE '^error #' "$WORK/$1.jpf.log" || true) errors, $(( $(date +%s) - s )) s"
}

product() {  # product <label> <graph> <model dir> [sed for the cfg]: TLC's dump and the check
  local d="$WORK/$1"
  rm -rf "$d" && mkdir -p "$d"
  cp "$3/StreamBuffer.tla" "$3/TraceStreamBuffer.tla" "$3/TraceGraph.tla" "$d/"
  "$py" -I "$here/graphmin.py" "$2" "Graph_$name" "$d" "$readers" "$byte_readers" "$wait_callers" \
    "$bytes" "$chunk" "$readlen" | sed 's/^/  /'
  if [ -n "${4:-}" ]; then sed -i "$4" "$d/Graph_$name.cfg"; fi
  local s
  s=$(date +%s)
  (cd "$d" && "$JAVA_TLC" -XX:+UseParallelGC -cp "$TLA2TOOLS" tlc2.TLC -workers "${TLC_WORKERS:-auto}" \
     -dump dot,actionlabels product.dot -config "Graph_$name.cfg" "Graph_$name.tla" > tlc.log 2>&1) || true
  echo "  TLC $1: $(grep -oE '[0-9]+ distinct states found' "$d/tlc.log" | tail -1), $(( $(date +%s) - s )) s"
  local e=0
  "$py" -I "$here/graphcheck.py" "$d/product.dot" "$d/Graph_$name.tla" > "$d/check.log" 2>&1 || e=$?
  grep -E '^OK|^REJECTED|^FAIL' "$d/check.log" | head -1 | sed 's/^/  /'
  rm -f "$d/product.dot"
  return "$e"
}

expect() {  # expect <label> <0 accepted | 1 rejected> <command...>
  local label="$1" want="$2"
  shift 2
  local e=0
  "$@" || e=$?
  if [ "$want" = 0 ] && [ "$e" = 0 ]; then echo "OK    $label: every word accepted"
  elif [ "$want" = 1 ] && [ "$e" = 1 ]; then echo "OK    $label: rejected, as it must be"
  else echo "FAIL  $label (graphcheck exit $e)"; failed=1
  fi
}

jpf_graph "$name" "$TRACED"
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
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"\tret\t\d+\t\d+\t(\d+)", s)
s = s[:m.start(1)] + str(int(m.group(1)) + 1) + s[m.end(1):]
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(s)
EOF
  expect "control: a returned byte + 1 in the graph" 1 product "$name-byte" "$corrupt" "$tla"
  jpf_graph "$name-mutant" "$TRACED_MUTANT"
  expect "control: readSingleByte does not lower the count" 1 product "$name-mutant" "$WORK/$name-mutant.graph" "$tla"
fi
exit "$failed"
