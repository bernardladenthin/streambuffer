"""A18 gate 2: the size of JPF's state graph as a minimal deterministic automaton over its events.

Reads GraphExport's file (I, E, F lines), splits multi-event edges into chains, removes the edges
without an event (epsilon closure), determinizes (subset construction) and minimizes (Moore's
partition refinement) the automaton of the prefix-closed language (every state accepting).
Usage: python graphmin.py <graph.txt>

Memory: the graphs of two readers have 400 million edges and more (9 GB of text), so the edges
are kept in flat arrays of 32-bit integers (compressed sparse rows, events as small integers),
about 16 bytes per edge at the peak, not as Python objects (about 150 bytes per edge: the first
version needed more than RAM and swap of a 62 GB machine for one such graph). The subset
construction keeps its sets packed (pack: the sorted differences, zlib-compressed, exact); it
visits states and events in sorted order, so the numbering is deterministic; any
numbering gives the same automaton up to isomorphism, which is all TLC and graphcheck.py use.
"""
import operator
import sys
import time
import zlib
from array import array
from collections import defaultdict
from itertools import accumulate

# an unsigned type of 32 bits for the offsets ("I" is 4 bytes on the platforms Python runs on;
# checked, since a narrower one would wrap)
OFFSET = "I" if array("I").itemsize == 4 else "q"

t0 = time.time()
init = None
trailer = None  # the edge count of the trailer
nedges = 0
event_id = {}  # event text -> small integer
events = []  # small integer -> event text
# raw ids: JPF's state ids (>= -1), and fresh ids (<= -2) for the inner states of a chain
eps_s, eps_d = array("i"), array("i")
lab_s, lab_e, lab_d = array("i"), array("H"), array("i")
fresh = -2
maxid = -1
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        c = line[:2]
        if c == "E ":
            parts = line.rstrip("\n").split(" ", 3)
            a, b = int(parts[1]), int(parts[2])
            if a > maxid:
                maxid = a
            if b > maxid:
                maxid = b
            nedges += 1
            evs = [e for e in parts[3].split("|") if e] if len(parts) > 3 else []
            if not evs:
                eps_s.append(a)
                eps_d.append(b)
                continue
            cur = a
            last = len(evs) - 1
            for k, e in enumerate(evs):
                if k == last:
                    nxt = b
                else:
                    nxt = fresh
                    fresh -= 1
                ev = event_id.get(e)
                if ev is None:
                    ev = event_id[e] = len(events)
                    events.append(e)
                lab_s.append(cur)
                lab_e.append(ev)
                lab_d.append(nxt)
                cur = nxt
        elif c == "I ":
            init = int(line.split()[1])
            if init > maxid:
                maxid = init
        elif line.startswith("# edges "):
            trailer = int(line.split()[2])

# the trailer counts the edges GraphExport wrote: fewer read means lines lost (a full disk)
if init is None or nedges == 0 or trailer is None or trailer != nedges:
    sys.exit("FAIL: the graph is incomplete (init %s, %d edges, trailer %s)" % (init, nedges, trailer))

# dense ids: JPF's id v as v + 1 (so -1 is 0), fresh id v as njpf + (-2 - v)
njpf = maxid + 2
nfresh = -2 - fresh
nstates = njpf + nfresh


def csr(src, dst, lab=None):
    """The edges as compressed sparse rows over the dense ids: (offsets, targets[, labels])."""
    # offsets of 32 bits while the edges fit (S3N: 2.6 billion edges, ~700 million states: 5.6 GB
    # less than 64 bits for the two tables and their cursors)
    off = array(OFFSET if len(src) < 2 ** 32 else "q", [0]) * (nstates + 1)
    for v in src:
        off[(v + 1 if v >= -1 else njpf - 2 - v) + 1] += 1
    for k in range(nstates):
        off[k + 1] += off[k]
    pos = array(off.typecode, off)
    tgt = array("i", [0]) * len(src)
    lbl = array("H", [0]) * len(src) if lab is not None else None
    for k in range(len(src)):
        v = src[k]
        s = v + 1 if v >= -1 else njpf - 2 - v
        p = pos[s]
        w = dst[k]
        tgt[p] = w + 1 if w >= -1 else njpf - 2 - w
        if lbl is not None:
            lbl[p] = lab[k]
        pos[s] = p + 1
    return off, tgt, lbl


# JPF's states that occur, for the count (its ids may have gaps; the chains' inner states are
# not counted, as before)
seen_jpf = bytearray(njpf)
for arr in (eps_s, eps_d, lab_s, lab_d):
    for v in arr:
        if v >= -1:
            seen_jpf[v + 1] = 1
seen_jpf[init + 1] = 1
eoff, etgt, _ = csr(eps_s, eps_d)
del eps_s, eps_d
loff, ltgt, llab = csr(lab_s, lab_d, lab_e)
del lab_s, lab_d, lab_e
labelled = sum(1 for k in range(nstates) if loff[k + 1] > loff[k])
print("graph: %d states, %d edges, %d labelled sources, init %s (%.1fs)"
      % (sum(seen_jpf), nedges, labelled, init, time.time() - t0))
sys.stdout.flush()


def closure(states):
    """The epsilon closure of a set of dense ids, as a sorted array."""
    seen = set(states)
    todo = list(states)
    while todo:
        s = todo.pop()
        for k in range(eoff[s], eoff[s + 1]):
            n = etgt[k]
            if n not in seen:
                seen.add(n)
                todo.append(n)
    return array("i", sorted(seen))


def pack(sorted_ids):
    """A set of dense ids (a sorted array) as a short key: its differences, zlib-compressed.

    Exact: equal sets give equal keys and different sets different ones (the differences of a
    sorted set determine it, and zlib is lossless), so the automaton is the same as with the sets
    themselves. The sets are the memory of the subset construction: S6A's closures took 3.1 KB a
    dfa state, packed 0.2 KB; S3N's took ~10 KB, and its graphmin.py was killed at ~40 GB.
    """
    d = array("i", sorted_ids[:1])
    d.extend(map(operator.sub, sorted_ids[1:], sorted_ids[:-1]))
    return zlib.compress(d.tobytes(), 1)


def unpack(key):
    """The sorted array of dense ids a key of pack stands for."""
    d = array("i")
    d.frombytes(zlib.decompress(key))
    return array("i", accumulate(d))


start = pack(closure([init + 1]))
index = {start: 0}  # a dfa state (its sorted closure, packed) -> its number
via = {}  # a set of targets before the closure (packed) -> the dfa state its closure is
order = [start]  # the dfa states by number, packed; each dropped once its moves are known
trans = []  # dfa state -> {event: dfa state}
i = 0
while i < len(order):
    S = unpack(order[i])
    order[i] = None
    moves = defaultdict(set)
    for s in S:
        for k in range(loff[s], loff[s + 1]):
            moves[llab[k]].add(ltgt[k])
    row = {}
    for e in sorted(moves, key=events.__getitem__):
        key = pack(array("i", sorted(moves[e])))
        t = via.get(key)
        if t is None:
            tk = pack(closure(moves[e]))
            t = index.get(tk)
            if t is None:
                t = index[tk] = len(order)
                order.append(tk)
            via[key] = t
        row[e] = t
    trans.append(row)
    i += 1
    if i % 20000 == 0:
        print("  determinizing: %d done, %d found (%.0fs)" % (i, len(order), time.time() - t0))
        sys.stdout.flush()
del index, via, order
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

# ---------------------------------------------------------------------------------------------
# the minimal automaton as a TLA+ module of TraceGraph.tla, if asked for:
#   graphmin.py <graph.txt> <module> <out dir> <readers> <byte readers> <wait callers> <bytes>
#     <chunk length> <read length>   (the reader sets as comma-separated names, possibly empty)
if len(sys.argv) > 2:
    import os
    module, outdir = sys.argv[2], sys.argv[3]
    readers, byte_readers, wait_callers = (
        [x for x in a.split(",") if x] for a in sys.argv[4:7])
    nbytes, chunk, readlen = sys.argv[7:10]
    # the minimal automaton: the block of the initial state, and one edge per block and event
    edges = {}
    for s, row in enumerate(trans):
        for e, t in row.items():
            edges[(block[s], events[e])] = block[t]

    def tla_set(names):
        return "{" + ", ".join('"%s"' % n for n in names) + "}"

    def tla_event(e):
        t, m, a, n, v, b = e.split("\t")
        bs = "<<" + ", ".join(x for x in b.split(",") if x) + ">>"
        return '[t |-> "%s", m |-> "%s", a |-> "%s", n |-> %s, v |-> %s, b |-> %s]' % (t, m, a, n, v, bs)

    lines = ["---- MODULE %s ----" % module,
             "\\* Generated by src/test/jpf/trace/graphmin.py from a JPF state graph",
             "EXTENDS TraceGraph",
             "TReaders == " + tla_set(readers),
             "TByteReaders == " + tla_set(byte_readers),
             "TWaitCallers == " + tla_set(wait_callers),
             "TBytes == " + nbytes, "TChunkLen == " + chunk, "TReadLen == " + readlen,
             'TWriterName == <<"w">>', 'TCloserName == <<"c">>',
             "TEmpty == <<>>",
             "TInit == %d" % block[0]]
    ordered = sorted(edges.items())
    lines.append("TEdge == <<")
    for i, ((f, e), d) in enumerate(ordered):
        # a sequence is indexed from 1: edge i is TEdge[i]; "i" repeats the id for the checker
        lines.append(("  " if i == 0 else ", ") + "[i |-> %d, f |-> %d, d |-> %d, e |-> %s]" % (i + 1, f, d, tla_event(e)))
    lines.append(">>")
    out_of = defaultdict(list)
    for i, ((f, e), d) in enumerate(ordered):
        out_of[f].append(i + 1)
    # the edges out of each state: a sequence of sets, state s is element s + 1 (TraceGraph.tla reads
    # Out[g + 1]). Not a function [s \in 0..n |-> TOutSeq[s + 1]]: TLC builds that at its start with
    # TOutSeq evaluated anew for every state, quadratic (S6N, 20,392 states: 43 minutes)
    lines.append("TOut == <<")
    for s in range(nblocks):
        lines.append(("  " if s == 0 else ", ") + "{%s}" % ", ".join(map(str, out_of[s])))
    lines.append(">>")
    lines += ["===="]
    with open(os.path.join(outdir, module + ".tla"), "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines) + "\n")
    cfg = """CONSTANTS
    Readers <- TReaders
    ByteReaders <- TByteReaders
    WaitCallers <- TWaitCallers
    Bytes <- TBytes
    ChunkLen <- TChunkLen
    ReadLen <- TReadLen
    NW = 1
    NC = 1
    WriterName <- TWriterName
    CloserName <- TCloserName
    TraceLog <- TEmpty
    GInit <- TInit
    GEdge <- TEdge
    GOut <- TOut
    K = 6
    Spurious = 3
    Protocol = "condition"
    ReCheck = TRUE
    AtomicRead = TRUE
    CountOnce = TRUE
    CheckedReturn = TRUE
INIT GraphInit
NEXT GraphNext
CHECK_DEADLOCK FALSE
"""
    with open(os.path.join(outdir, module + ".cfg"), "w", encoding="utf-8", newline="\n") as out:
        out.write(cfg)
    print("module %s: %d states, %d edges" % (module, nblocks, len(edges)))
