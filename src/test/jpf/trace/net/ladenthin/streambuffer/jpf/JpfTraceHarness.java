// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import net.ladenthin.streambuffer.StreamBuffer;
import net.ladenthin.streambuffer.trace.TraceRecorder;

/**
 * Roadmap A18: every interleaving JPF explores of the instrumented {@code StreamBuffer} (the class
 * files of A6's {@code TracingClassLoader}) prints its trace, in the threads and harness events of
 * A6's {@code TraceScenario}: a writer {@code w}, a closer {@code c} that closes at any point, and
 * readers {@code r1}... Each path that ends prints {@code @@TRACE}, one {@code @@E} line per event
 * (thread, site, value, bytes) and {@code @@END}.
 *
 * <p>Arguments: bytes, chunk length, read length, the numbers of {@code read()} readers, of record
 * readers and of {@code waitForAtLeast} callers, and optionally {@code false} to run without a
 * recording (then JPF can match states, which gives the size of the state graph), and {@code after}
 * to close only once the writer is done.
 */
public final class JpfTraceHarness {

    private JpfTraceHarness() {}

    public static void main(String[] args) throws Exception {
        final int bytes = Integer.parseInt(args[0]);
        final int chunkLen = Integer.parseInt(args[1]);
        final int readLen = Integer.parseInt(args[2]);
        final int byteReaders = Integer.parseInt(args[3]);
        final int recordReaders = Integer.parseInt(args[4]);
        final int waitCallers = Integer.parseInt(args[5]);
        // without a recording the events are not kept, so JPF can match states (the graph's size)
        final boolean record = args.length < 7 || Boolean.parseBoolean(args[6]);
        // "after": the closer closes once the writer is done (as in StreamBuffer.jpf), else at any point
        final boolean closeAfterWrites = args.length >= 8 && args[7].equals("after");

        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(bytes + 10);
        final OutputStream out = sb.getOutputStream();
        final InputStream in = sb.getInputStream();
        final List<Thread> threads = new ArrayList<>();

        threads.add(new Thread(() -> {
            int next = 1;
            while (next <= bytes) {
                final int n = Math.min(chunkLen, bytes - next + 1);
                final byte[] chunk = new byte[n];
                for (int i = 0; i < n; i++) {
                    chunk[i] = (byte) (next + i);
                }
                try {
                    out.write(chunk);
                } catch (IOException e) {
                    TraceRecorder.harness("wfail", 0, Collections.<Integer>emptyList());
                    return;
                }
                TraceRecorder.harness("wret", next + n - 1, Collections.<Integer>emptyList());
                next += n;
            }
        }, "w"));
        final Thread writer = threads.get(0);
        threads.add(new Thread(() -> {
            try {
                if (closeAfterWrites) {
                    writer.join();
                }
                sb.close();
            } catch (IOException | InterruptedException e) {
                throw new AssertionError("close must not fail", e);
            }
            TraceRecorder.harness("cret", 0, Collections.<Integer>emptyList());
        }, "c"));
        final int readers = byteReaders + recordReaders + waitCallers;
        for (int i = 0; i < readers; i++) {
            final int kind = i < byteReaders ? 0 : i < byteReaders + recordReaders ? 1 : 2;
            threads.add(new Thread(() -> {
                try {
                    if (kind == 2) {
                        final long v = sb.waitForAtLeast(readLen);
                        TraceRecorder.harness("wfa", v, Collections.<Integer>emptyList());
                        return;
                    }
                    final byte[] b = new byte[readLen];
                    for (; ; ) {
                        final int n = kind == 0 ? in.read() : in.read(b, 0, readLen);
                        if (n < 0) {
                            TraceRecorder.harness("eof", -1, Collections.<Integer>emptyList());
                            return;
                        }
                        final List<Integer> got = new ArrayList<>();
                        if (kind == 0) {
                            got.add(n);
                        } else {
                            for (int j = 0; j < n; j++) {
                                got.add(b[j] & 0xff);
                            }
                        }
                        TraceRecorder.harness("ret", got.size(), got);
                    }
                } catch (IOException | InterruptedException e) {
                    throw new AssertionError("reader must not fail", e);
                }
            }, "r" + (i + 1)));
        }

        if (record) {
            TraceRecorder.start(0, 0);
        } else {
            TraceRecorder.startGraph();
        }
        for (Thread t : threads) {
            t.start();
        }
        for (Thread t : threads) {
            t.join();
        }
        if (!record) {
            return;
        }
        final List<TraceRecorder.Event> events = TraceRecorder.stop();
        final StringBuilder b = new StringBuilder("@@TRACE\n");
        for (TraceRecorder.Event e : events) {
            b.append("@@E\t").append(e.thread).append('\t').append(e.site).append('\t').append(e.value)
                    .append('\t');
            for (int i = 0; i < e.bytes.size(); i++) {
                b.append(i == 0 ? "" : ",").append(e.bytes.get(i));
            }
            b.append('\n');
        }
        b.append("@@END");
        System.out.println(b);
    }
}
