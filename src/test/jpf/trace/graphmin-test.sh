#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Roadmap A18: graphmin.py on small hand-written JPF graphs (GraphExport's format) whose automata
# are worked out by hand: the edges without an event (and a cycle of them), an edge of two events
# (a chain), the subset construction (two edges of one event to different states) and Moore's
# minimization (two states with the same future merge). An incomplete graph gives no module.
#
# Usage: src/test/jpf/trace/graphmin-test.sh   (needs python 3 on PATH)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
py="$(command -v python3 || command -v python)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

ev() {  # ev <name>: one event of the graph (thread, method, access, n, value, bytes; tabs)
  printf 'r1\t%s\tgetAvail\t0\t0\t' "$1"
}

# words a, ab, ac, abd, acd, and e f after them (one edge of two events). Edges without an event:
# 3 -> 5 and 5 -> 3 (a cycle). Subsets: {0}, {1,2} after a, {3,5} after ab, {4} after ac, {6}
# after abd or acd, the chain's inner state after e, {7} after f. And g, h from 0 to 11 and 12,
# each with an edge without an event to 10: the subsets {10,11} and {10,12} share their smallest
# state but not their future (i to 13, j to 14), so a key that confused them would show. 11 dfa
# states, 11 transitions, 10 events. Minimal: {3,5} and {4} both have d to {6} only, and {7},
# {13}, {14} have no move: 8 states, 10 edges.
{
  echo "I 0"
  echo "E 0 1 $(ev a)"
  echo "E 0 2 $(ev a)"
  echo "E 1 3 $(ev b)"
  echo "E 2 4 $(ev c)"
  echo "E 3 5 "
  echo "E 5 3 "
  echo "E 5 6 $(ev d)"
  echo "E 4 6 $(ev d)"
  echo "E 6 7 $(ev e)|$(ev f)"
  echo "E 0 11 $(ev g)"
  echo "E 0 12 $(ev h)"
  echo "E 11 10 "
  echo "E 12 10 "
  echo "E 11 13 $(ev i)"
  echo "E 12 14 $(ev j)"
  echo "F 7"
  echo "# edges 15"
} > "$work/g.graph"

check() {  # check <label> <regex>...: graphmin.py's output must have a line matching each
  local label="$1" ok=1
  shift
  for want in "$@"; do
    grep -qE -- "$want" "$work/out" || { ok=0; echo "      missing: $want"; }
  done
  if [ "$ok" = 1 ]; then echo "OK    $label"; else echo "FAIL  $label"; sed 's/^/      /' "$work/out"; failed=1; fi
}

mkdir -p "$work/m"
"$py" -I "$here/graphmin.py" "$work/g.graph" Graph_T "$work/m" r1 r1 "" 1 1 1 > "$work/out" 2>&1
check "the subset construction: 11 dfa states over 10 events" \
  '^graph: 13 states, 15 edges, ' '^dfa: 11 states, 11 transitions, alphabet 10 \('
check "the states with the same future merge: 8 of 11" \
  '^minimal dfa: 8 states \(' '^module Graph_T: 8 states, 10 edges$'
n=$(grep -cE '^(  |, )\[i \|-> ' "$work/m/Graph_T.tla")
if [ "$n" = 10 ]; then echo "OK    the module's TEdge has the 10 edges"; else echo "FAIL  the module's TEdge has $n edges"; failed=1; fi

# without the trailer the graph is no complete search: no module
grep -v '^# edges' "$work/g.graph" > "$work/cut.graph"
mkdir -p "$work/c"
if "$py" -I "$here/graphmin.py" "$work/cut.graph" Graph_T "$work/c" r1 r1 "" 1 1 1 > "$work/out" 2>&1; then
  echo "FAIL  a graph without its trailer gave a module"; failed=1
elif [ -e "$work/c/Graph_T.tla" ]; then
  echo "FAIL  a graph without its trailer wrote a module"; failed=1
else
  echo "OK    a graph without its trailer: no module"
fi

# an edge lost on the way (a full disk) while the trailer was written: no module
awk '/^E / && !d { d = 1; next } { print }' "$work/g.graph" > "$work/lost.graph"
mkdir -p "$work/l"
if "$py" -I "$here/graphmin.py" "$work/lost.graph" Graph_T "$work/l" r1 r1 "" 1 1 1 > "$work/out" 2>&1; then
  echo "FAIL  a graph with an edge fewer than its trailer gave a module"; failed=1
elif [ -e "$work/l/Graph_T.tla" ]; then
  echo "FAIL  a graph with an edge fewer than its trailer wrote a module"; failed=1
else
  echo "OK    a graph with an edge fewer than its trailer: no module"
fi
exit "$failed"
