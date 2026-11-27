// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * One scenario of the TLA+ model {@code src/test/tla/StreamBuffer.tla}, run on an instrumented
 * {@code StreamBuffer} (roadmap A6): the writers write {@code bytes} bytes in writes of
 * {@code chunkLen} bytes (one FIFO entry each), the k-th write by writer k mod {@code writers};
 * the closers close; the readers {@code r1}, {@code r2}, ...: first those calling {@code read()}
 * until -1, then those calling {@code read(b, 0, readLen)} until -1, then those calling
 * {@code waitForAtLeast(readLen)} once. One writer is {@code w}, several are {@code w1},
 * {@code w2}, ... (the closers {@code c} or {@code c1}, ...). The model numbers the bytes in the
 * order the writes commit, the code's writers choose theirs before they write, so {@link #run}
 * renumbers the bytes of the trace by the order of the commits (a write's store to
 * {@code availableBytes} under {@code bufferLock}); with one writer that changes nothing. The
 * trim is not modeled, so {@code maxBufferElements} stays above the number of writes.
 */
public final class TraceScenario {

    /** The scenario's name, used for the file names. */
    public final String name;
    /** The bytes the writer writes (at most 255, the values are bytes). */
    public final int bytes;
    /** The bytes per write. */
    public final int chunkLen;
    /** The bytes a record read asks for, and the bytes a wait waits for. */
    public final int readLen;
    /** The readers calling {@code read()}. */
    public final int byteReaders;
    /** The readers calling {@code read(b, 0, readLen)}. */
    public final int recordReaders;
    /** The threads calling {@code waitForAtLeast(readLen)} once. */
    public final int waitCallers;
    /** The writers. */
    public final int writers;
    /** The closers. */
    public final int closers;

    /** The site of a write's commit: its store to {@code availableBytes} under {@code bufferLock}. */
    static final String COMMIT = "writeFromArray.putAvail#0";

    /**
     * Creates a scenario.
     *
     * @param name the name
     * @param bytes the bytes the writer writes
     * @param chunkLen the bytes per write
     * @param readLen the bytes of a record read and of a wait
     * @param byteReaders the readers calling {@code read()}
     * @param recordReaders the readers calling {@code read(b, 0, readLen)}
     * @param waitCallers the threads calling {@code waitForAtLeast(readLen)}
     */
    public TraceScenario(
            String name, int bytes, int chunkLen, int readLen, int byteReaders, int recordReaders, int waitCallers) {
        this(name, bytes, chunkLen, readLen, byteReaders, recordReaders, waitCallers, 1, 1);
    }

    /**
     * Creates a scenario with several writers or closers. With several writers every write has
     * {@code chunkLen} bytes ({@code bytes} a multiple of it), as in the model, whose writes in
     * commit order are all full but the last.
     *
     * @param name the name
     * @param bytes the bytes the writers write together
     * @param chunkLen the bytes per write
     * @param readLen the bytes of a record read and of a wait
     * @param byteReaders the readers calling {@code read()}
     * @param recordReaders the readers calling {@code read(b, 0, readLen)}
     * @param waitCallers the threads calling {@code waitForAtLeast(readLen)}
     * @param writers the writers
     * @param closers the closers
     */
    public TraceScenario(
            String name,
            int bytes,
            int chunkLen,
            int readLen,
            int byteReaders,
            int recordReaders,
            int waitCallers,
            int writers,
            int closers) {
        if (bytes > 255
                || chunkLen < 1
                || readLen < 1
                || byteReaders + recordReaders + waitCallers < 1
                || writers < 1
                || closers < 1
                || (writers > 1 && bytes % chunkLen != 0)) {
            throw new IllegalArgumentException(name);
        }
        this.name = name;
        this.bytes = bytes;
        this.chunkLen = chunkLen;
        this.readLen = readLen;
        this.byteReaders = byteReaders;
        this.recordReaders = recordReaders;
        this.waitCallers = waitCallers;
        this.writers = writers;
        this.closers = closers;
    }

    /** @return the names of the writers, by their ids in the model */
    public List<String> writerNames() {
        return names("w", writers);
    }

    /** @return the names of the closers, by their ids in the model */
    public List<String> closerNames() {
        return names("c", closers);
    }

    private static List<String> names(String prefix, int n) {
        final List<String> r = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            r.add(n == 1 ? prefix : prefix + i);
        }
        return r;
    }

    /** @return the names of all reading and waiting threads */
    public List<String> readers() {
        final List<String> r = new ArrayList<>();
        for (int i = 1; i <= byteReaders + recordReaders + waitCallers; i++) {
            r.add("r" + i);
        }
        return r;
    }

    /** @return the names of the threads calling {@code read()} */
    public List<String> byteReaderNames() {
        return readers().subList(0, byteReaders);
    }

    /** @return the names of the threads calling {@code waitForAtLeast} */
    public List<String> waitCallerNames() {
        return readers().subList(byteReaders + recordReaders, byteReaders + recordReaders + waitCallers);
    }

    /**
     * Runs the scenario once on a freshly loaded, instrumented {@code StreamBuffer}.
     *
     * @param seed the seed of the yields and of the closer's delay
     * @param yieldPer256 the probability of a yield before each access, in 1/256
     * @return the events in the order they happened
     * @throws Exception if the class cannot be loaded or a thread does not end within 30 s
     */
    public List<TraceRecorder.Event> run(long seed, int yieldPer256) throws Exception {
        return run(seed, yieldPer256, null);
    }

    /**
     * Runs the scenario once on a freshly loaded, instrumented {@code StreamBuffer} with a defect of
     * {@link TraceMutants} (a negative control; {@code null}: none).
     *
     * @param seed the seed of the yields and of the closer's delay
     * @param yieldPer256 the probability of a yield before each access, in 1/256
     * @param mutant the defect, or {@code null}
     * @return the events in the order they happened
     * @throws Exception if the class cannot be loaded or a thread does not end within 30 s
     */
    public List<TraceRecorder.Event> run(long seed, int yieldPer256, String mutant) throws Exception {
        final Class<?> c = new TracingClassLoader(mutant).loadClass("net.ladenthin.streambuffer.StreamBuffer");
        final Object sb = c.getConstructor().newInstance();
        c.getMethod("setMaxBufferElements", int.class).invoke(sb, bytes + 10);
        final InputStream in = (InputStream) c.getMethod("getInputStream").invoke(sb);
        final OutputStream out = (OutputStream) c.getMethod("getOutputStream").invoke(sb);
        final Method waitForAtLeast = c.getMethod("waitForAtLeast", long.class);
        final Random random = new Random(seed);
        // the closer closes once the writer has written this many bytes (or has ended), so the
        // close falls anywhere in the run, not only right at its start
        final int closeAfter = random.nextInt(bytes + 1);
        final AtomicInteger progress = new AtomicInteger();
        final List<Throwable> failures = Collections.synchronizedList(new ArrayList<>());
        final CountDownLatch go = new CountDownLatch(1);
        final List<Thread> threads = new ArrayList<>();

        // the writes: the k-th (from 0) has the bytes k * chunkLen + 1, ... and is writer k mod writers'
        final List<List<byte[]>> plan = new ArrayList<>();
        for (int w = 0; w < writers; w++) {
            plan.add(new ArrayList<>());
        }
        for (int next = 1, k = 0; next <= bytes; next += chunkLen, k++) {
            final int n = Math.min(chunkLen, bytes - next + 1);
            final byte[] chunk = new byte[n];
            for (int i = 0; i < n; i++) {
                chunk[i] = (byte) (next + i);
            }
            plan.get(k % writers).add(chunk);
        }
        final AtomicInteger writersLeft = new AtomicInteger(writers);
        final List<String> writerNames = writerNames();
        for (int w = 0; w < writers; w++) {
            final List<byte[]> mine = plan.get(w);
            threads.add(new Thread(
                    () -> {
                        await(go);
                        int mineWritten = 0;
                        for (byte[] chunk : mine) {
                            try {
                                out.write(chunk);
                            } catch (IOException e) {
                                TraceRecorder.harness("wfail", 0, Collections.emptyList());
                                progress.set(Integer.MAX_VALUE);
                                return;
                            }
                            // the bytes this writer has written; run() makes it the bytes all have
                            mineWritten += chunk.length;
                            TraceRecorder.harness("wret", mineWritten, Collections.emptyList());
                            progress.addAndGet(chunk.length);
                        }
                        if (writersLeft.decrementAndGet() == 0) {
                            progress.set(Integer.MAX_VALUE);
                        }
                    },
                    writerNames.get(w)));
        }
        final List<String> closerNames = closerNames();
        for (int k = 0; k < closers; k++) {
            final int closerDelay = random.nextInt(4);
            threads.add(new Thread(
                    () -> {
                        await(go);
                        while (progress.get() < closeAfter) {
                            Thread.yield();
                        }
                        for (int i = 0; i < closerDelay; i++) {
                            Thread.yield();
                        }
                        try {
                            ((Closeable) sb).close();
                        } catch (IOException e) {
                            failures.add(e);
                        }
                        TraceRecorder.harness("cret", 0, Collections.emptyList());
                    },
                    closerNames.get(k)));
        }
        final List<String> names = readers();
        for (int i = 0; i < names.size(); i++) {
            final int kind = i < byteReaders ? 0 : i < byteReaders + recordReaders ? 1 : 2;
            threads.add(new Thread(
                    () -> {
                        await(go);
                        try {
                            if (kind == 2) {
                                final long v = (Long) waitForAtLeast.invoke(sb, (long) readLen);
                                TraceRecorder.harness("wfa", v, Collections.emptyList());
                                return;
                            }
                            final byte[] b = new byte[readLen];
                            for (; ; ) {
                                final int n = kind == 0 ? in.read() : in.read(b, 0, readLen);
                                if (n < 0) {
                                    TraceRecorder.harness("eof", -1, Collections.emptyList());
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
                        } catch (IOException
                                | IllegalAccessException
                                | InvocationTargetException
                                | RuntimeException e) {
                            failures.add(e);
                        }
                    },
                    names.get(i)));
        }

        TraceRecorder.start(seed, yieldPer256);
        for (Thread t : threads) {
            t.start();
        }
        go.countDown();
        for (Thread t : threads) {
            t.join(TimeUnit.SECONDS.toMillis(30));
            if (t.isAlive()) {
                TraceRecorder.stop();
                throw new IllegalStateException(name + " seed " + seed + ": thread " + t.getName() + " hangs");
            }
        }
        final List<TraceRecorder.Event> events = TraceRecorder.stop();
        if (!failures.isEmpty()) {
            throw new IllegalStateException(name + " seed " + seed + ": " + failures);
        }
        return renumber(events, plan);
    }

    /**
     * Numbers the bytes of a trace in the order the writes commit, as the model does: the j-th
     * commit of writer w is its j-th write of the plan, its bytes get the next numbers; a
     * {@code wret} line gets the bytes of all writers up to its writer's last commit (the model's
     * {@code Len(written)} then, which can only grow until the line).
     */
    static List<TraceRecorder.Event> renumber(List<TraceRecorder.Event> events, List<List<byte[]>> plan) {
        final Map<String, Deque<byte[]>> left = new HashMap<>();
        // the writer's name is its index in the plan, as in writerNames()
        for (int w = 0; w < plan.size(); w++) {
            left.put(plan.size() == 1 ? "w" : "w" + (w + 1), new ArrayDeque<>(plan.get(w)));
        }
        final Map<Integer, Integer> number = new HashMap<>();
        final Map<String, Integer> upTo = new HashMap<>();
        int next = 1;
        final List<TraceRecorder.Event> out = new ArrayList<>();
        for (TraceRecorder.Event e : events) {
            if (e.site.equals(COMMIT) && left.containsKey(e.thread)) {
                final byte[] chunk = left.get(e.thread).poll();
                if (chunk == null) {
                    throw new IllegalStateException("more commits than writes: " + e);
                }
                for (byte b : chunk) {
                    number.put(b & 0xff, next++);
                }
                upTo.put(e.thread, next - 1);
                out.add(e);
            } else if (e.site.equals("wret")) {
                out.add(new TraceRecorder.Event(e.thread, e.site, upTo.get(e.thread), e.bytes));
            } else if (!e.bytes.isEmpty()) {
                final List<Integer> b = new ArrayList<>();
                for (int v : e.bytes) {
                    final Integer m = number.get(v);
                    if (m == null) {
                        throw new IllegalStateException("a byte read before its write committed: " + e);
                    }
                    b.add(m);
                }
                out.add(new TraceRecorder.Event(e.thread, e.site, e.value, b));
            } else {
                out.add(e);
            }
        }
        return out;
    }

    private static void await(CountDownLatch go) {
        try {
            go.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    @Override
    public String toString() {
        return name
                + Arrays.asList(bytes, chunkLen, readLen, byteReaders, recordReaders, waitCallers)
                + (writers == 1 && closers == 1 ? "" : " writers " + writers + ", closers " + closers);
    }
}
