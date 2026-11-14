// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import gov.nasa.jpf.Config;
import gov.nasa.jpf.ListenerAdapter;
import gov.nasa.jpf.search.Search;
import gov.nasa.jpf.vm.ElementInfo;
import gov.nasa.jpf.vm.MethodInfo;
import gov.nasa.jpf.vm.StackFrame;
import gov.nasa.jpf.vm.ThreadInfo;
import gov.nasa.jpf.vm.VM;
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.UncheckedIOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/**
 * Roadmap A18: writes the state graph JPF explores, each transition labelled with the events the
 * tracer reported during it ({@code TraceRecorder.emit}). Lines: {@code I <state>} (the initial
 * state), {@code E <from> <to> <events>} (the events separated by {@code |}, empty for none),
 * {@code F <state>} (an end state). With state matching the graph is finite; its paths are all the
 * interleavings JPF explores.
 */
public final class GraphExport extends ListenerAdapter {

    private static final String EMIT = "net.ladenthin.streambuffer.trace.TraceRecorder.emit(Ljava/lang/String;)V";

    private final PrintWriter out;
    private final Deque<Integer> path = new ArrayDeque<>();
    private final List<String> pending = new ArrayList<>();
    private long edges;

    public GraphExport(Config conf) {
        try {
            out = new PrintWriter(new BufferedWriter(new FileWriter(conf.getString("graph.out", "graph.txt"))));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public void searchStarted(Search search) {
        path.push(search.getStateId());
        out.println("I " + search.getStateId());
    }

    @Override
    public void methodEntered(VM vm, ThreadInfo ti, MethodInfo mi) {
        if (mi.getFullName().equals(EMIT)) {
            final StackFrame frame = ti.getTopFrame();
            final ElementInfo line = vm.getHeap().get(frame.getLocalVariable(0));
            pending.add(line.asString());
        }
    }

    @Override
    public void stateAdvanced(Search search) {
        final int to = search.getStateId();
        out.println("E " + path.peek() + " " + to + " " + String.join("|", pending));
        edges++;
        pending.clear();
        if (search.isEndState()) {
            out.println("F " + to);
        }
        path.push(to);
    }

    @Override
    public void stateBacktracked(Search search) {
        path.pop();
        pending.clear();
    }

    @Override
    public void searchFinished(Search search) {
        out.println("# edges " + edges);
        out.close();
    }
}
