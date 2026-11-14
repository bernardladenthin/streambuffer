# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
"""A18 gate 2: the size of JPF's state graph as a minimal deterministic automaton over its events.

Reads GraphExport's file (I, E, F lines), splits multi-event edges into chains, removes the edges
without an event (epsilon closure), determinizes (subset construction) and minimizes (Moore's
partition refinement) the automaton of the prefix-closed language (every state accepting).
Usage: python graphmin.py <graph.txt>
"""
import sys
import time
from collections import defaultdict

t0 = time.time()
init = None
eps = defaultdict(list)
lab = defaultdict(list)  # state -> [(event, state)]
nodes = set()
fresh = -2
nedges = 0
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("I "):
        init = int(line.split()[1])
        nodes.add(init)
    elif line.startswith("E "):
        parts = line.rstrip("\n").split(" ", 3)
        a, b = int(parts[1]), int(parts[2])
        events = [e for e in parts[3].split("|") if e] if len(parts) > 3 else []
        nodes.update((a, b))
        nedges += 1
        if not events:
            eps[a].append(b)
        else:
            cur = a
            for i, e in enumerate(events):
                nxt = b if i == len(events) - 1 else fresh
                if nxt == fresh:
                    fresh -= 1
                lab[cur].append((e, nxt))
                cur = nxt
print("graph: %d states, %d edges, %d labelled sources, init %s (%.1fs)" % (len(nodes), nedges, len(lab), init, time.time() - t0))

closure_cache = {}


def closure(states):
    key = states
    if key in closure_cache:
        return closure_cache[key]
    seen = set(states)
    todo = list(states)
    while todo:
        s = todo.pop()
        for n in eps.get(s, ()):
            if n not in seen:
                seen.add(n)
                todo.append(n)
    r = frozenset(seen)
    closure_cache[key] = r
    return r


start = closure(frozenset([init]))
index = {start: 0}
order = [start]
trans = []  # dfa state -> {event: dfa state}
i = 0
while i < len(order):
    S = order[i]
    moves = defaultdict(set)
    for s in S:
        for e, n in lab.get(s, ()):
            moves[e].add(n)
    row = {}
    for e, ns in moves.items():
        T = closure(frozenset(ns))
        if T not in index:
            index[T] = len(order)
            order.append(T)
        row[e] = index[T]
    trans.append(row)
    i += 1
    if i % 20000 == 0:
        print("  determinizing: %d done, %d found (%.0fs)" % (i, len(order), time.time() - t0))
alphabet = sorted({e for row in trans for e in row})
print("dfa: %d states, %d transitions, alphabet %d (%.1fs)" % (len(trans), sum(len(r) for r in trans), len(alphabet), time.time() - t0))

# Moore minimization: start with one block (all accepting), refine by the signature of moves
block = [0] * len(trans)
nblocks = 1
while True:
    sig = {}
    newblock = [0] * len(trans)
    for s, row in enumerate(trans):
        key = (block[s], tuple(sorted((e, block[t]) for e, t in row.items())))
        if key not in sig:
            sig[key] = len(sig)
        newblock[s] = sig[key]
    if len(sig) == nblocks:
        break
    nblocks = len(sig)
    block = newblock
print("minimal dfa: %d states (%.1fs)" % (nblocks, time.time() - t0))
