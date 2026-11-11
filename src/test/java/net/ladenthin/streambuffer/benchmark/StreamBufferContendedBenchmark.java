// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.benchmark;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import net.ladenthin.streambuffer.StreamBuffer;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;

/**
 * Contended producer/consumer benchmark (TODO roadmap A7): {@code writers} threads write
 * {@code RECORDS} records of {@code RECORD} bytes in total into one {@link StreamBuffer} while
 * {@code readers} threads read them with {@code read(b, 0, RECORD)}, on platform or virtual threads.
 * One invocation is one complete transfer; the score is its average time, so lower is better and
 * {@code RECORDS * RECORD / score} is the throughput.
 *
 * <p>A report, not a gate: shared CI runners are too noisy for a threshold. It is the baseline for
 * roadmap A8 (one {@code ReentrantLock} instead of {@code synchronized (bufferLock)}).
 *
 * <p>Run locally (JMH forks need the test classpath, see CLAUDE.md "Run JMH benchmarks"):
 * <pre>
 * java -cp "target/test-classes;target/classes;&lt;test classpath&gt;" org.openjdk.jmh.Main StreamBufferContended
 * </pre>
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MILLISECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 2)
@Measurement(iterations = 5, time = 2)
@Fork(1)
public class StreamBufferContendedBenchmark {

    /** Record size: an Ethernet-sized payload, as in the record tests. */
    static final int RECORD = 1429;

    /** Records per transfer, about 11 MiB. */
    static final int RECORDS = 8192;

    /** Thread kind of the writers and readers. */
    @Param({"platform", "virtual"})
    public String kind;

    /** Number of writer threads. */
    @Param({"1", "4"})
    public int writers;

    /** Number of reader threads. */
    @Param({"1", "4"})
    public int readers;

    /**
     * The trim threshold ({@link StreamBuffer#setMaxBufferElements(int)}): 100 is the default, 0
     * turns trimming off, so the difference is what {@code trim()} costs under contention.
     */
    @Param({"100", "0", "1000"})
    public int maxBufferElements;

    @Benchmark
    public long transfer() throws InterruptedException {
        final ThreadFactory factory = "virtual".equals(kind)
                ? Thread.ofVirtual().factory()
                : Thread.ofPlatform().factory();
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(maxBufferElements);
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final AtomicLong received = new AtomicLong();
        final List<Thread> threads = new ArrayList<>();
        final List<Thread> writerThreads = new ArrayList<>();
        for (int w = 0; w < writers; w++) {
            final int share = RECORDS / writers + (w < RECORDS % writers ? 1 : 0);
            final Thread t = factory.newThread(() -> {
                final byte[] record = new byte[RECORD];
                try {
                    for (int i = 0; i < share; i++) {
                        os.write(record);
                    }
                } catch (IOException e) {
                    throw new IllegalStateException(e);
                }
            });
            writerThreads.add(t);
            threads.add(t);
        }
        final List<Thread> readerThreads = new ArrayList<>();
        for (int r = 0; r < readers; r++) {
            final Thread t = factory.newThread(() -> {
                final byte[] record = new byte[RECORD];
                try {
                    int n;
                    while ((n = is.read(record, 0, RECORD)) > 0) {
                        received.addAndGet(n);
                    }
                } catch (IOException e) {
                    throw new IllegalStateException(e);
                }
            });
            readerThreads.add(t);
            threads.add(t);
        }
        threads.forEach(Thread::start);
        for (Thread t : writerThreads) {
            t.join();
        }
        try {
            sb.close();
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        for (Thread t : readerThreads) {
            t.join();
        }
        if (received.get() != (long) RECORDS * RECORD) {
            throw new IllegalStateException("received " + received.get() + " of " + (long) RECORDS * RECORD + " bytes");
        }
        return received.get();
    }
}
