# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
"""A18: is every word of the automaton (every interleaving JPF explored) a run of the model?

Reads the state graph TLC dumped of TraceGraph.tla's product (`-dump dot,actionlabels`) and the
automaton's module (its edges: id, from, to), and runs a subset construction over the words: for a
word w, X(w) is the set of product states with no edge chosen that some run reaches by consuming
w; X(w e) is reached from X(w) by Choose of e, any number of GSilent (at most K, as TraceGraph.tla
allows), and GConsume. Every word is accepted exactly when no reachable X(w e) is empty for an edge
e of the automaton's state after w; an empty one is a counterexample, printed as its word.
Usage: python graphcheck.py <product.dot> <automaton module .tla>
Exit codes: 0 every word accepted, 3 a word rejected, anything else the check could not run
(a missing or malformed input), so a negative control never mistakes a crash for a rejection.
"""
import re
import sys
import time
from collections import defaultdict, deque

t0 = time.time()
NODE = re.compile(r'^(-?\d+) \[label="(.*)"(,style = filled)?\];?$')
EDGE = re.compile(r'^(-?\d+) -> (-?\d+) \[label="(\w+)"')
G = re.compile(r'/\\\\ g = (-?\d+)')
PEND = re.compile(r'/\\\\ pend = (-?\d+)')

info = {}
initial = []
succ = defaultdict(list)
for line in open(sys.argv[1], encoding="utf-8"):
    m = EDGE.match(line)
    if m:
        succ[int(m.group(1))].append((m.group(3), int(m.group(2))))
        continue
    m = NODE.match(line)
    if m:
        node = int(m.group(1))
        label = m.group(2)
        info[node] = (int(G.search(label).group(1)), int(PEND.search(label).group(1)))
        if m.group(3):
            initial.append(node)
print("product: %d states, %d with successors, %d initial (%.1fs)"
      % (len(info), len(succ), len(initial), time.time() - t0))

EDGE_DEF = re.compile(r'\[i \|-> (\d+), f \|-> (\d+), d \|-> (\d+), e \|-> (\[.*\])\]')
edges_from = defaultdict(list)
event = {}
ginit = None
for line in open(sys.argv[2], encoding="utf-8"):
    m = EDGE_DEF.search(line)
    if m:
        i, f, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        edges_from[f].append((i, d))
        event[i] = m.group(4)
    elif line.startswith("TInit == "):
        ginit = int(line.split("==")[1])
print("automaton: %d edges, initial state %s" % (len(event), ginit))
# the module must be read whole: its edges numbered 1.., and as many as TEdge has lines
tedge_lines = sum(1 for line in open(sys.argv[2], encoding="utf-8") if line.lstrip(", ").startswith("[i |-> "))
if ginit is None or not event or sorted(event) != list(range(1, len(event) + 1)) or len(event) != tedge_lines:
    sys.exit("FAIL: the automaton module was not read whole (%d edges parsed, %d edge lines)" % (len(event), tedge_lines))
if not info or len(info) < len(succ):
    sys.exit("FAIL: the product dump was not read whole (%d states parsed)" % len(info))
if not initial or any(info[n] != (ginit, -1) for n in initial):
    sys.exit("FAIL: the product's initial states are not at the automaton's initial state")


def step(states, i):
    """The product states with no edge chosen after consuming edge i from states."""
    out = set()
    for p in states:
        for act, p1 in succ.get(p, ()):
            if act != "Choose" or info[p1][1] != i:
                continue
            seen = {p1}
            todo = [p1]
            while todo:
                q = todo.pop()
                for act2, r in succ.get(q, ()):
                    if act2 == "GSilent" and r not in seen:
                        seen.add(r)
                        todo.append(r)
                    elif act2 == "GConsume":
                        out.add(r)
    return frozenset(out)


start = (ginit, frozenset(initial))
parent = {start: None}
queue = deque([start])
violations = []
while queue and len(violations) < 5:
    d, states = queue.popleft()
    for i, d2 in edges_from.get(d, ()):
        nxt = step(states, i)
        if not nxt:
            word = [i]
            key = (d, states)
            while parent[key] is not None:
                key, j = parent[key]
                word.append(j)
            violations.append(list(reversed(word)))
            continue
        key2 = (d2, nxt)
        if key2 not in parent:
            parent[key2] = ((d, states), i)
            queue.append(key2)
print("subsets explored: %d (%.1fs)" % (len(parent), time.time() - t0))
if violations:
    for w in violations:
        print("REJECTED word of %d events, the last is the first the model cannot take:" % len(w))
        for i in w:
            print("  " + event[i])
    sys.exit(3)
print("OK: every word of the automaton is a run of the model (%d words' states, %d edges)"
      % (len(parent), len(event)))
