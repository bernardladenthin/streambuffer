// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.MatcherAssert.assertThat;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.Semaphore;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Many readers and writers on virtual threads, and a pinning check (TODO roadmap A7).
 *
 * <p>The wait for data uses a {@code java.util.concurrent} condition, so a waiting virtual reader
 * unmounts from its carrier. The FIFO is still guarded by {@code synchronized (bufferLock)}: since
 * JDK 24 (JEP 491) a virtual thread no longer pins its carrier there, on JDK 21 to 23 it does when
 * it blocks or parks inside the monitor. The pinning report runs this class on JDK 21 under JFR
 * ({@code jdk.VirtualThreadPinned} at threshold 0) and lists the events with a {@code StreamBuffer}
 * frame: the {@code virtual-threads-jdk21} job of {@code formal-verification.yml}, or locally
 * {@code -Djvm=<jdk-21>/bin/java -Dstreambuffer.test.jvmArgs=-XX:StartFlightRecording:...}. It is a report, not a
 * gate, and kept out of the test code so the test runs on the module path without JFR flags.
 */
public class StreamBufferVirtualThreadsTest {

    private static final int RECORD = 1429;

    private static final ThreadFactory VIRTUAL =
            Thread.ofVirtual().name("sb-virtual-", 0).factory();

    /**
     * Four virtual writers of whole records, 64 virtual readers of {@code read(b, 0, RECORD)}:
     * every record arrives once and whole.
     */
    private static void manyVirtualReadersAndWriters(final StreamBuffer sb, final int perWriter) throws Exception {
        final int writers = 4;
        final int readers = 64;
        final InputStream is = sb.getInputStream();
        final OutputStream os = sb.getOutputStream();
        final Set<Integer> seen = ConcurrentHashMap.newKeySet();
        final ConcurrentLinkedQueue<Throwable> failures = new ConcurrentLinkedQueue<>();
        final List<Thread> readerThreads = new ArrayList<>();
        for (int r = 0; r < readers; r++) {
            readerThreads.add(VIRTUAL.newThread(() -> {
                final byte[] record = new byte[RECORD];
                try {
                    while (is.read(record, 0, RECORD) == RECORD) {
                        final int id = (record[0] & 0xff) << 16 | (record[1] & 0xff) << 8 | (record[2] & 0xff);
                        for (int i = 3; i < RECORD; i++) {
                            if (record[i] != (byte) (id + i)) {
                                failures.add(new AssertionError("torn record " + id));
                                return;
                            }
                        }
                        if (!seen.add(id)) {
                            failures.add(new AssertionError("record " + id + " twice"));
                        }
                    }
                } catch (IOException e) {
                    failures.add(e);
                }
            }));
        }
        final List<Thread> writerThreads = new ArrayList<>();
        for (int w = 0; w < writers; w++) {
            final int writer = w;
            writerThreads.add(VIRTUAL.newThread(() -> {
                try {
                    for (int s = 0; s < perWriter; s++) {
                        final int id = writer * perWriter + s;
                        final byte[] record = new byte[RECORD];
                        record[0] = (byte) (id >>> 16);
                        record[1] = (byte) (id >>> 8);
                        record[2] = (byte) id;
                        for (int i = 3; i < RECORD; i++) {
                            record[i] = (byte) (id + i);
                        }
                        os.write(record);
                    }
                } catch (IOException e) {
                    failures.add(e);
                }
            }));
        }
        readerThreads.forEach(Thread::start);
        writerThreads.forEach(Thread::start);
        for (Thread t : writerThreads) {
            t.join(TimeUnit.SECONDS.toMillis(60));
        }
        sb.close();
        for (Thread t : readerThreads) {
            t.join(TimeUnit.SECONDS.toMillis(60));
            assertThat("a virtual reader returned", t.isAlive(), is(false));
        }
        if (!failures.isEmpty()) {
            throw new AssertionError("a virtual thread failed", failures.peek());
        }
        assertThat("every record arrived once", seen.size(), is(writers * perWriter));
    }

    @DisplayName("64 virtual readers, 4 virtual writers of 1429-byte records — every record whole and once")
    @Test
    public void virtualThreads_manyReadersAndWriters_everyRecordOnce() throws Exception {
        manyVirtualReadersAndWriters(new StreamBuffer(), StreamBufferTest.iterations(500, 10));
    }

    @DisplayName("virtual threads with trim and a re-entrant write from the trim signal — every record once")
    @Test
    public void virtualThreads_trimAndSignal_everyRecordOnce() throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(4);
        sb.addTrimStartSignal(new Semaphore(0));
        manyVirtualReadersAndWriters(sb, StreamBufferTest.iterations(200, 5));
    }

    @DisplayName("virtual threads with a trim signal that spins while the writer holds the lock — every record once")
    @Test
    public void virtualThreads_slowTrimSignal_everyRecordOnce() throws Exception {
        // a trim signal that takes a moment: the writer holds the monitor while other virtual
        // threads queue for it, the case that pins carriers on JDK 21 to 23 (see the class comment)
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(2);
        sb.addTrimStartSignal(new Semaphore(0) {
            private static final long serialVersionUID = 1L;

            @Override
            public void release() {
                for (int i = 0; i < 100; i++) {
                    Thread.onSpinWait();
                }
                super.release();
            }
        });
        manyVirtualReadersAndWriters(sb, StreamBufferTest.iterations(200, 5));
    }
}
