#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Roadmap A18: GraphCheck.java and its reference graphcheck.py on small hand-written products, in
# TLC's dump format: each must give the expected verdict (exit 0 accepted, 3 rejected, else no
# result), both must print the same (timings aside), and a dump that is not whole must give no
# result, never a rejection a negative control would count. check-graph.sh compares the two on
# every real product too (GRAPHCHECK_REFERENCE=1, in CI for S1A and its controls).
#
# Usage: src/test/jpf/trace/graphcheck-test.sh   (needs java 11+ and python 3 on PATH; zstd too
#   for the compressed case, which it skips without)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
py="$(command -v python3 || command -v python)"
java="${JAVA:-java}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

# the automaton: 0 -e1-> 1 -e2-> 2
cat > "$work/Graph.tla" <<'EOF'
---- MODULE Graph ----
TInit == 0
TEdge == <<
  [i |-> 1, f |-> 0, d |-> 1, e |-> [t |-> "w", m |-> "writeFromArray", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>]]
, [i |-> 2, f |-> 1, d |-> 2, e |-> [t |-> "r1", m |-> "read", a |-> "getAvail", n |-> 0, v |-> 1, b |-> <<>>]]
>>
====
EOF

node() {  # node <fp> <g> <pend> [filled]: a state line of TLC's dot dump
  printf '%s [label="/\\\\ g = %s\\n/\\\\ k = 0\\n/\\\\ pend = %s\\n/\\\\ bl = \\"none\\""%s];\n' \
    "$1" "$2" "$3" "${4:+,style = filled}"
}
edge() {  # edge <from> <to> <action>
  printf '%s -> %s [label="%s",color="black",fontcolor="black"];\n' "$1" "$2" "$3"
}
product() {  # product <file> <with the second consume: yes|no> [cut]
  {
    printf 'strict digraph DiskGraph {\nnodesep=0.35;\nsubgraph cluster_graph {\ncolor="white";\n'
    node 11 0 -1 filled
    edge 11 -22 Choose
    node -22 0 1
    edge -22 33 GSilent
    edge -22 -22 GSilent
    node 33 0 1
    edge 33 44 GConsume
    node 44 1 -1
    edge 44 55 Choose
    node 55 1 2
    if [ "$2" = yes ]; then
      edge 55 66 GConsume
      node 66 2 -1
    fi
    if [ -n "${3:-}" ]; then edge 55 77 GConsume; fi
    printf '}\n{rank = same; 11;}\n}\n'
  } > "$1"
}

run() {  # run <label> <dump> <expected exit: 0 | 3 | fail>
  local label="$1" dump="$2" want="$3" je=0 pe=0
  "$java" "$here/GraphCheck.java" "$dump" "$work/Graph.tla" > "$work/j.out" 2> "$work/j.err" || je=$?
  "$py" -I "$here/graphcheck.py" "$dump" "$work/Graph.tla" > "$work/p.out" 2> "$work/p.err" || pe=$?
  local ok=1
  if [ "$want" = fail ]; then
    [ "$je" != 0 ] && [ "$je" != 3 ] && [ "$pe" != 0 ] && [ "$pe" != 3 ] || ok=0
  else
    [ "$je" = "$want" ] && [ "$pe" = "$want" ] || ok=0
    diff <(sed -E 's/ \([0-9.]+s\)//' "$work/p.out") <(sed -E 's/ \([0-9.]+s\)//' "$work/j.out") \
      > "$work/diff" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "OK    $label (GraphCheck.java exit $je, graphcheck.py exit $pe)"
  else
    echo "FAIL  $label (GraphCheck.java exit $je, graphcheck.py exit $pe, expected $want)"
    sed 's/^/      /' "$work/diff" "$work/j.err" "$work/p.err" 2> /dev/null | head -20
    failed=1
  fi
}

product "$work/accepted.dot" yes
run "every word a run of the model: accepted" "$work/accepted.dot" 0
product "$work/rejected.dot" no
run "the second event never consumed: rejected" "$work/rejected.dot" 3
grep -q '^  \[t |-> "r1", m |-> "read"' "$work/p.out" && grep -q '^  \[t |-> "r1", m |-> "read"' "$work/j.out" \
  && echo "OK    the rejected word names the second event" \
  || { echo "FAIL  the rejected word does not name the second event"; failed=1; }
product "$work/cut.dot" yes cut
run "an edge to a state not in the dump: no result" "$work/cut.dot" fail
grep -v '^44 ' "$work/accepted.dot" > "$work/nostate.dot"
run "a state's line missing: no result" "$work/nostate.dot" fail
if command -v zstd > /dev/null; then
  zstd -q -f "$work/accepted.dot" -o "$work/accepted.dot.zst"
  run "the compressed dump: accepted" "$work/accepted.dot.zst" 0
  zstd -q -f "$work/rejected.dot" -o "$work/rejected.dot.zst"
  run "the compressed dump: rejected" "$work/rejected.dot.zst" 3
  head -c "$(( $(wc -c < "$work/accepted.dot.zst") / 2 ))" "$work/accepted.dot.zst" > "$work/broken.dot.zst"
  run "a broken compressed dump: no result" "$work/broken.dot.zst" fail
else
  echo "SKIP  the compressed dump (no zstd)"
fi
exit "$failed"
