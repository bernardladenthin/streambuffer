// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * A18: is every word of the automaton (every interleaving JPF explored) a run of the model? The
 * same check as {@code graphcheck.py}, with the same output and exit codes, in at most about 70
 * bytes per product state instead of about 700, and five times faster (S6A, 3,837,985 states: a
 * heap of 256 MB, 0.38 GB resident and 25 s; graphcheck.py 2.73 GB and 128 s). The Python dicts
 * would not fit a product of about 240 million states (S3N, estimated) into 125 GB.
 *
 * <p>Reads the state graph TLC dumped of TraceGraph.tla's product ({@code -dump dot,actionlabels},
 * plain or zstd-compressed, {@code .zst}) and the automaton's module, and runs a subset
 * construction over the words: for a word w, X(w) is the set of product states with no edge chosen
 * that some run reaches by consuming w; X(w e) is reached from X(w) by Choose of e, any number of
 * GSilent and GConsume. Every word is accepted exactly when no reachable X(w e) is empty for an
 * edge e of the automaton's state after w; an empty one is a counterexample, printed as its word.
 *
 * <p>Usage: {@code java GraphCheck.java <product.dot[.zst]> <automaton module .tla>}. Exit codes: 0
 * every word accepted, 3 a word rejected, anything else the check could not run.
 */
public final class GraphCheck {

    private static final byte CHOOSE = 1;
    private static final byte SILENT = 2;
    private static final byte CONSUME = 3;

    private static final long T0 = System.nanoTime();

    /** The product: states by index (sorted by TLC's fingerprint), edges in compressed rows. */
    private static int[] pend;
    private static int[] offset;
    private static int[] target;
    private static byte[] action;

    private GraphCheck() {}

    public static void main(String[] args) throws IOException, InterruptedException {
        if (args.length != 2) {
            fail("usage: java GraphCheck.java <product.dot[.zst]> <automaton module .tla>");
        }
        int[] initial = readProduct(args[0]);
        Automaton a = readAutomaton(args[1]);
        for (int p : initial) {
            if (gOf[p] != a.init || pend[p] != -1) {
                fail("FAIL: the product's initial states are not at the automaton's initial state");
            }
        }
        gOf = null;
        search(a, initial);
    }

    private static int[] gOf;

    // ---------------------------------------------------------------- reading the product dump

    /** Grows a primitive array as it is filled. */
    private static final class Longs {
        long[] a = new long[1 << 16];
        int n;

        void add(long v) {
            if (n == a.length) {
                a = Arrays.copyOf(a, grow(a.length));
            }
            a[n++] = v;
        }
    }

    private static final class Ints {
        int[] a;
        int n;

        Ints() {
            this(1 << 16);
        }

        /** With room for {@code capacity} values first: an automaton state has few edges out. */
        Ints(int capacity) {
            a = new int[capacity];
        }

        void add(int v) {
            if (n == a.length) {
                a = Arrays.copyOf(a, grow(a.length));
            }
            a[n++] = v;
        }
    }

    private static final class Bytes {
        byte[] a = new byte[1 << 16];
        int n;

        void add(byte v) {
            if (n == a.length) {
                a = Arrays.copyOf(a, grow(a.length));
            }
            a[n++] = v;
        }
    }

    private static int grow(int length) {
        long next = Math.min((long) Integer.MAX_VALUE - 8, length + (long) (length >> 1) + 16);
        if (next <= length) {
            fail("FAIL: more than 2^31 states or edges in the product");
        }
        return (int) next;
    }

    /** One pass over the dump: the nodes (fingerprint, g, pend, initial) and the edges. */
    private static int[] readProduct(String path) throws IOException, InterruptedException {
        Longs nodeFp = new Longs();
        Ints nodeG = new Ints();
        Ints nodePend = new Ints();
        Longs initialFp = new Longs();
        Longs edgeFrom = new Longs();
        Longs edgeTo = new Longs();
        Bytes edgeAct = new Bytes();
        Process zstd = null;
        InputStream in;
        if (path.endsWith(".zst")) {
            zstd = new ProcessBuilder("zstd", "-dcq", path).redirectErrorStream(false).start();
            in = zstd.getInputStream();
        } else {
            in = new FileInputStream(path);
        }
        try (BufferedReader r =
                new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8), 1 << 20)) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.isEmpty() || !(line.charAt(0) == '-' || Character.isDigit(line.charAt(0)))) {
                    continue;
                }
                int arrow = line.indexOf(" -> ");
                if (arrow > 0) {
                    // <from> -> <to> [label="<action>"...
                    int sp = line.indexOf(' ', arrow + 4);
                    int lb = line.indexOf("[label=\"", arrow + 4);
                    if (sp < 0 || lb != sp + 1) {
                        continue;
                    }
                    int end = lb + 8;
                    while (end < line.length() && isWordChar(line.charAt(end))) {
                        end++;
                    }
                    if (end >= line.length() || line.charAt(end) != '"') {
                        continue;
                    }
                    String act = line.substring(lb + 8, end);
                    byte code = "Choose".equals(act) ? CHOOSE
                            : "GSilent".equals(act) ? SILENT
                            : "GConsume".equals(act) ? CONSUME : 0;
                    edgeFrom.add(parseLongStrict(line, 0, arrow));
                    edgeTo.add(parseLongStrict(line, arrow + 4, sp));
                    edgeAct.add(code);
                    continue;
                }
                // <fp> [label="..."(,style = filled)?];?
                int sp = line.indexOf(' ');
                if (sp <= 0 || !line.startsWith(" [label=\"", sp)) {
                    continue;
                }
                String rest = line;
                if (rest.endsWith(";")) {
                    rest = rest.substring(0, rest.length() - 1);
                }
                boolean filled = rest.endsWith("\",style = filled]");
                if (!filled && !rest.endsWith("\"]")) {
                    continue;
                }
                Long fp = parseLong(line, 0, sp);
                if (fp == null) {
                    continue;
                }
                nodeFp.add(fp);
                nodeG.add(intAfter(line, "/\\\\ g = "));
                nodePend.add(intAfter(line, "/\\\\ pend = "));
                if (filled) {
                    initialFp.add(fp);
                }
            }
        }
        if (zstd != null && zstd.waitFor() != 0) {
            fail("FAIL: zstd could not decompress " + path + " (exit " + zstd.exitValue() + ")");
        }
        // the states by fingerprint: a sorted copy, and each node's index found in it
        int n0 = nodeFp.n;
        long[] fp = Arrays.copyOf(nodeFp.a, n0);
        Arrays.parallelSort(fp);
        int n = 0;
        for (int k = 0; k < n0; k++) {
            if (n == 0 || fp[n - 1] != fp[k]) {
                fp[n++] = fp[k];
            }
        }
        fp = Arrays.copyOf(fp, n);
        pend = new int[n];
        gOf = new int[n];
        for (int k = 0; k < n0; k++) {
            int idx = Arrays.binarySearch(fp, nodeFp.a[k]);
            pend[idx] = nodePend.a[k];
            gOf[idx] = nodeG.a[k];
        }
        nodeFp.a = null;
        nodeG.a = null;
        nodePend.a = null;
        // the edges as compressed rows, in the dump's order per state; a state with an edge out is
        // a state of the dump, or the dump was not read whole
        int e = edgeAct.n;
        int[] from = new int[e];
        offset = new int[n + 1];
        for (int k = 0; k < e; k++) {
            int idx = Arrays.binarySearch(fp, edgeFrom.a[k]);
            if (idx < 0) {
                fail("FAIL: the product dump was not read whole (an edge from an unknown state)");
            }
            from[k] = idx;
            offset[idx + 1]++;
        }
        edgeFrom.a = null;
        for (int k = 0; k < n; k++) {
            offset[k + 1] += offset[k];
        }
        target = new int[e];
        action = new byte[e];
        int[] cursor = Arrays.copyOf(offset, n);
        for (int k = 0; k < e; k++) {
            int idx = Arrays.binarySearch(fp, edgeTo.a[k]);
            if (idx < 0) {
                fail("FAIL: the product dump was not read whole (an edge to an unknown state)");
            }
            int at = cursor[from[k]]++;
            target[at] = idx;
            action[at] = edgeAct.a[k];
        }
        edgeTo.a = null;
        edgeAct.a = null;
        int withSucc = 0;
        for (int k = 0; k < n; k++) {
            if (offset[k + 1] > offset[k]) {
                withSucc++;
            }
        }
        int[] initial = new int[initialFp.n];
        for (int k = 0; k < initialFp.n; k++) {
            initial[k] = Arrays.binarySearch(fp, initialFp.a[k]);
        }
        System.out.printf(Locale.ROOT, "product: %d states, %d with successors, %d initial (%.1fs)%n",
                n, withSucc, initial.length, seconds());
        if (n == 0) {
            fail("FAIL: the product dump was not read whole (0 states parsed)");
        }
        int[] sorted = initial.clone();
        Arrays.sort(sorted);
        return dedupe(sorted);
    }

    private static boolean isWordChar(char c) {
        return Character.isLetterOrDigit(c) || c == '_';
    }

    private static long parseLongStrict(String s, int from, int to) {
        Long v = parseLong(s, from, to);
        if (v == null) {
            fail("FAIL: a malformed edge in the product dump: " + s);
        }
        return v;
    }

    private static Long parseLong(String s, int from, int to) {
        if (to <= from) {
            return null;
        }
        try {
            return Long.parseLong(s.substring(from, to));
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private static int intAfter(String line, String key) {
        int k = line.indexOf(key);
        if (k < 0) {
            fail("FAIL: a state without " + key.substring(4).trim() + " in the product dump: " + line);
        }
        int start = k + key.length();
        int end = start;
        if (end < line.length() && line.charAt(end) == '-') {
            end++;
        }
        while (end < line.length() && Character.isDigit(line.charAt(end))) {
            end++;
        }
        return Integer.parseInt(line.substring(start, end));
    }

    // ---------------------------------------------------------------- reading the automaton

    private static final class Automaton {
        int init;
        /** The edges out of each automaton state in the module's order: [id, to] pairs. */
        Map<Integer, Ints> edgesFrom = new HashMap<>();
        Map<Integer, String> event = new HashMap<>();
    }

    private static Automaton readAutomaton(String path) throws IOException {
        Automaton a = new Automaton();
        Integer init = null;
        int edgeLines = 0;
        java.util.regex.Pattern def = java.util.regex.Pattern.compile(
                "\\[i \\|-> (\\d+), f \\|-> (\\d+), d \\|-> (\\d+), e \\|-> (\\[.*\\])\\]");
        try (BufferedReader r = new BufferedReader(new InputStreamReader(
                new FileInputStream(path), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                java.util.regex.Matcher m = def.matcher(line);
                if (m.find()) {
                    int i = Integer.parseInt(m.group(1));
                    int f = Integer.parseInt(m.group(2));
                    int d = Integer.parseInt(m.group(3));
                    Ints out = a.edgesFrom.computeIfAbsent(f, k -> new Ints(4));
                    out.add(i);
                    out.add(d);
                    a.event.put(i, m.group(4));
                } else if (line.startsWith("TInit == ")) {
                    init = Integer.parseInt(line.split("==")[1].trim());
                }
                String stripped = line.replaceFirst("^[, ]+", "");
                if (stripped.startsWith("[i |-> ")) {
                    edgeLines++;
                }
            }
        }
        System.out.printf(Locale.ROOT, "automaton: %d edges, initial state %s%n", a.event.size(),
                init == null ? "None" : init.toString());
        // the module must be read whole: its edges numbered 1.., and as many as TEdge has lines
        boolean numbered = true;
        for (int i = 1; i <= a.event.size(); i++) {
            numbered &= a.event.containsKey(i);
        }
        if (init == null || a.event.isEmpty() || !numbered || a.event.size() != edgeLines) {
            fail(String.format(Locale.ROOT,
                    "FAIL: the automaton module was not read whole (%d edges parsed, %d edge lines)",
                    a.event.size(), edgeLines));
        }
        a.init = init;
        return a;
    }

    // ---------------------------------------------------------------- the subset construction

    /** A subset of the product's states at an automaton state, as a sorted array. */
    private static final class Key {
        final int d;
        final int[] states;
        final int hash;

        Key(int d, int[] states) {
            this.d = d;
            this.states = states;
            this.hash = 31 * d + Arrays.hashCode(states);
        }

        @Override
        public boolean equals(Object o) {
            return o instanceof Key && ((Key) o).d == d && Arrays.equals(((Key) o).states, states);
        }

        @Override
        public int hashCode() {
            return hash;
        }
    }

    /**
     * Marks per product state, as bits. Not java.util.BitSet: its clear scans back for the highest
     * word still set, and the marks here are few and far apart (S6A: four times slower).
     */
    private static long[] seen;
    private static long[] outMark;

    private static boolean get(long[] bits, int k) {
        return (bits[k >>> 6] & (1L << k)) != 0;
    }

    private static void set(long[] bits, int k) {
        bits[k >>> 6] |= 1L << k;
    }

    private static void clear(long[] bits, int k) {
        bits[k >>> 6] &= ~(1L << k);
    }
    private static Ints touched;
    private static Ints out;
    private static Ints stack;

    /** The product states with no edge chosen after consuming edge i from states. */
    private static int[] step(int[] states, int i) {
        out.n = 0;
        for (int p : states) {
            for (int k = offset[p]; k < offset[p + 1]; k++) {
                int p1 = target[k];
                if (action[k] != CHOOSE || pend[p1] != i) {
                    continue;
                }
                // the GSilent closure of p1, and the GConsume edges out of it
                touched.n = 0;
                stack.n = 0;
                set(seen, p1);
                touched.add(p1);
                stack.add(p1);
                while (stack.n > 0) {
                    int q = stack.a[--stack.n];
                    for (int j = offset[q]; j < offset[q + 1]; j++) {
                        int r = target[j];
                        if (action[j] == SILENT) {
                            if (!get(seen, r)) {
                                set(seen, r);
                                touched.add(r);
                                stack.add(r);
                            }
                        } else if (action[j] == CONSUME && !get(outMark, r)) {
                            set(outMark, r);
                            out.add(r);
                        }
                    }
                }
                for (int t = 0; t < touched.n; t++) {
                    clear(seen, touched.a[t]);
                }
            }
        }
        int[] result = Arrays.copyOf(out.a, out.n);
        for (int r : result) {
            clear(outMark, r);
        }
        Arrays.sort(result);
        return result;
    }

    private static void search(Automaton a, int[] initial) {
        int n = pend.length;
        seen = new long[(n >> 6) + 1];
        outMark = new long[(n >> 6) + 1];
        touched = new Ints();
        out = new Ints();
        stack = new Ints();
        Map<Key, Integer> id = new HashMap<>();
        List<Key> keys = new ArrayList<>();
        Ints parent = new Ints();
        Ints parentEdge = new Ints();
        Key start = new Key(a.init, initial);
        id.put(start, 0);
        keys.add(start);
        parent.add(-1);
        parentEdge.add(-1);
        ArrayDeque<Integer> queue = new ArrayDeque<>();
        queue.add(0);
        List<int[]> violations = new ArrayList<>();
        while (!queue.isEmpty() && violations.size() < 5) {
            int cur = queue.poll();
            Key k = keys.get(cur);
            Ints edges = a.edgesFrom.get(k.d);
            if (edges == null) {
                continue;
            }
            for (int x = 0; x < edges.n; x += 2) {
                int i = edges.a[x];
                int d2 = edges.a[x + 1];
                int[] nxt = step(k.states, i);
                if (nxt.length == 0) {
                    Ints word = new Ints(64);
                    word.add(i);
                    int at = cur;
                    while (parent.a[at] >= 0) {
                        word.add(parentEdge.a[at]);
                        at = parent.a[at];
                    }
                    int[] w = new int[word.n];
                    for (int y = 0; y < word.n; y++) {
                        w[y] = word.a[word.n - 1 - y];
                    }
                    violations.add(w);
                    continue;
                }
                Key k2 = new Key(d2, nxt);
                if (!id.containsKey(k2)) {
                    id.put(k2, keys.size());
                    keys.add(k2);
                    parent.add(cur);
                    parentEdge.add(i);
                    queue.add(keys.size() - 1);
                }
            }
        }
        System.out.printf(Locale.ROOT, "subsets explored: %d (%.1fs)%n", id.size(), seconds());
        if (!violations.isEmpty()) {
            for (int[] w : violations) {
                System.out.printf(Locale.ROOT,
                        "REJECTED word of %d events, the last is the first the model cannot take:%n",
                        w.length);
                for (int i : w) {
                    System.out.println("  " + a.event.get(i));
                }
            }
            System.out.flush();
            System.exit(3);
        }
        System.out.printf(Locale.ROOT,
                "OK: every word of the automaton is a run of the model (%d words' states, %d edges)%n",
                id.size(), a.event.size());
    }

    private static int[] dedupe(int[] sorted) {
        int m = 0;
        for (int k = 0; k < sorted.length; k++) {
            if (m == 0 || sorted[m - 1] != sorted[k]) {
                sorted[m++] = sorted[k];
            }
        }
        return Arrays.copyOf(sorted, m);
    }

    private static double seconds() {
        return (System.nanoTime() - T0) / 1e9;
    }

    private static void fail(String message) {
        System.out.flush();
        System.err.println(message);
        System.exit(1);
    }
}
