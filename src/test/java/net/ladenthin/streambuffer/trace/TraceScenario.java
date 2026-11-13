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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * One scenario of the TLA+ model {@code src/test/tla/StreamBuffer.tla}, run on an instrumented
 * {@code StreamBuffer} (roadmap A6): one writer {@code w} of the bytes 1, 2, ... {@code bytes} in
 * writes of {@code chunkLen} bytes (one FIFO entry each), one closer {@code c}, the readers
 * {@code r1}, {@code r2}, ...: first those calling {@code read()} until -1, then those calling
 * {@code read(b, 0, readLen)} until -1, then those calling {@code waitForAtLeast(readLen)} once.
 * The trim is not modeled, so {@code maxBufferElements} stays above the number of writes.
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
        if (bytes > 255 || chunkLen < 1 || readLen < 1 || byteReaders + recordReaders + waitCallers < 1) {
            throw new IllegalArgumentException(name);
        }
        this.name = name;
        this.bytes = bytes;
        this.chunkLen = chunkLen;
        this.readLen = readLen;
        this.byteReaders = byteReaders;
        this.recordReaders = recordReaders;
        this.waitCallers = waitCallers;
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
        final Class<?> c = new TracingClassLoader().loadClass("net.ladenthin.streambuffer.StreamBuffer");
        final Object sb = c.getConstructor().newInstance();
        c.getMethod("setMaxBufferElements", int.class).invoke(sb, bytes + 10);
        final InputStream in = (InputStream) c.getMethod("getInputStream").invoke(sb);
        final OutputStream out = (OutputStream) c.getMethod("getOutputStream").invoke(sb);
        final Method waitForAtLeast = c.getMethod("waitForAtLeast", long.class);
        final Random random = new Random(seed);
        // the closer closes once the writer has written this many bytes (or has ended), so the
        // close falls anywhere in the run, not only right at its start
        final int closeAfter = random.nextInt(bytes + 1);
        final int closerDelay = random.nextInt(4);
        final AtomicInteger progress = new AtomicInteger();
        final List<Throwable> failures = Collections.synchronizedList(new ArrayList<>());
        final CountDownLatch go = new CountDownLatch(1);
        final List<Thread> threads = new ArrayList<>();

        threads.add(new Thread(
                () -> {
                    await(go);
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
                            TraceRecorder.harness("wfail", 0, Collections.emptyList());
                            progress.set(Integer.MAX_VALUE);
                            return;
                        }
                        // the bytes written so far
                        TraceRecorder.harness("wret", next + n - 1, Collections.emptyList());
                        next += n;
                        progress.set(next - 1);
                    }
                    progress.set(Integer.MAX_VALUE);
                },
                "w"));
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
                "c"));
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
        return events;
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
        return name + Arrays.asList(bytes, chunkLen, readLen, byteReaders, recordReaders, waitCallers);
    }
}
