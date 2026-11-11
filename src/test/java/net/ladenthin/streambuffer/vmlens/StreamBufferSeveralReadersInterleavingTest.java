// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.vmlens;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;

import com.vmlens.api.AllInterleavings;
import com.vmlens.api.AllInterleavingsBuilder;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicReference;
import net.ladenthin.streambuffer.StreamBuffer;
import org.junit.jupiter.api.Test;

/**
 * vmlens interleaving analysis of the scenarios the reader/writer test does not reach: several
 * readers, a close racing them, a trim with a trim start signal, and {@code safeWrite} with a
 * concurrent single-byte write (TODO roadmap A3).
 *
 * <p>vmlens runs every scenario through all interleavings and fails the build on any data race
 * it finds by the Java memory model's happens-before (the {@code vmlens} profile; this is the
 * race gate of roadmap A4). The scenarios with several readers were red before bug-hunt finding
 * F278, the record one before {@code read(b, off, len)} took its bytes in one step.
 */
public class StreamBufferSeveralReadersInterleavingTest {

    /**
     * The iteration limit: vmlens stops at 100 by default ("Maximum Iterations Reached"). With 1000
     * the record, trim and {@code safeWrite} scenarios run out of interleavings first (98, 765 and 4
     * on 2026-11-11), so vmlens explores all of them. The two-readers-and-close scenario reaches even
     * 1000 and keeps the default: its full space is checked exhaustively by JPF
     * ({@code TwoReaders.jpf}, {@code WaitAndRead.jpf}), and the extra iterations would cost the
     * per-pull-request vmlens job minutes.
     */
    private static final int MAXIMUM_ITERATIONS = 1000;

    private static AllInterleavings interleavings(final String name) {
        return new AllInterleavingsBuilder()
                .withMaximumIterations(MAXIMUM_ITERATIONS)
                .build(name);
    }

    private static Thread thread(final AtomicReference<Throwable> failure, final ThrowingRunnable body) {
        return new Thread(() -> {
            try {
                body.run();
            } catch (Throwable t) {
                failure.compareAndSet(null, t);
            }
        });
    }

    @FunctionalInterface
    private interface ThrowingRunnable {
        void run() throws Exception;
    }

    private static void joinAll(final Thread... threads) throws InterruptedException {
        for (Thread t : threads) {
            t.start();
        }
        for (Thread t : threads) {
            t.join();
        }
    }

    /**
     * One byte, then the close, and two readers: one gets the byte, the other the end of the
     * stream. Before F278 a reader could find the FIFO empty under the lock
     * ({@code NoSuchElementException}), or the close woke only one of two waiting readers.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void twoReadersOneByteThenClose_oneGetsTheByteTheOtherTheEnd() throws InterruptedException {
        try (AllInterleavings all = new AllInterleavings("StreamBuffer.twoReadersOneByteThenClose")) {
            while (all.hasNext()) {
                final StreamBuffer sb = new StreamBuffer();
                final OutputStream out = sb.getOutputStream();
                final InputStream in = sb.getInputStream();
                final AtomicReference<Throwable> failure = new AtomicReference<>();
                final int[] got = new int[2];

                final Thread writer = thread(failure, () -> {
                    out.write(7);
                    sb.close();
                });
                final Thread readerA = thread(failure, () -> got[0] = in.read());
                final Thread readerB = thread(failure, () -> got[1] = in.read());
                joinAll(writer, readerA, readerB);

                assertThat(failure.get(), is(nullValue()));
                assertThat(Arrays.asList(got[0], got[1]), containsInAnyOrder(7, -1));
                assertThat(sb.getTotalBytesRead(), is(1L));
            }
        }
    }

    /**
     * Two 2-byte records buffered fragmented across the record boundary ({@code [1]}, then
     * {@code [2, 3, 4]}), two readers of {@code read(b, 0, 2)}: each gets a whole record. Before
     * {@code read(b, off, len)} took its bytes in one step, a reader took the first byte, released
     * the lock and waited for the rest, so it could get {@code {1, 4}}. The bytes are written
     * before the readers start: with a third, writing thread vmlens spent its time computing
     * interleavings (more than 7 minutes without reaching its iteration limit, 2026-11-11), and two
     * readers are enough for the tear.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void twoRecordReaders_eachGetsAWholeRecord() throws InterruptedException {
        try (AllInterleavings all = interleavings("StreamBuffer.twoRecordReaders")) {
            while (all.hasNext()) {
                final StreamBuffer sb = new StreamBuffer();
                final OutputStream out = sb.getOutputStream();
                final InputStream in = sb.getInputStream();
                final AtomicReference<Throwable> failure = new AtomicReference<>();
                final byte[] recordA = new byte[2];
                final byte[] recordB = new byte[2];

                try {
                    out.write(new byte[] {1});
                    out.write(new byte[] {2, 3, 4});
                } catch (java.io.IOException e) {
                    throw new AssertionError(e);
                }
                final int[] counts = new int[2];
                final Thread readerA = thread(failure, () -> counts[0] = in.read(recordA, 0, 2));
                final Thread readerB = thread(failure, () -> counts[1] = in.read(recordB, 0, 2));
                joinAll(readerA, readerB);

                assertThat(failure.get(), is(nullValue()));
                assertThat(Arrays.asList(counts[0], counts[1]), containsInAnyOrder(2, 2));
                assertThat(
                        Arrays.asList(Arrays.toString(recordA), Arrays.toString(recordB)),
                        containsInAnyOrder("[1, 2]", "[3, 4]"));
            }
        }
    }

    /**
     * A write that trims ({@code maxBufferElements} 1) with a trim start signal registered, against
     * a reader: every byte arrives once and in order, and the signal was released.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void trimWithSignalAgainstAReader_bytesInOrder() throws InterruptedException {
        try (AllInterleavings all = interleavings("StreamBuffer.trimWithSignal")) {
            while (all.hasNext()) {
                final StreamBuffer sb = new StreamBuffer();
                sb.setMaxBufferElements(1);
                final Semaphore trimStarted = new Semaphore(0);
                sb.addTrimStartSignal(trimStarted);
                final OutputStream out = sb.getOutputStream();
                final InputStream in = sb.getInputStream();
                final AtomicReference<Throwable> failure = new AtomicReference<>();
                final byte[] sink = new byte[2];

                final Thread writer = thread(failure, () -> {
                    out.write(1);
                    out.write(2); // two entries > maxBufferElements: trims, unless the reader took 1
                });
                final int[] count = new int[1];
                final Thread reader = thread(failure, () -> count[0] = in.read(sink, 0, 2));
                joinAll(writer, reader);

                assertThat(failure.get(), is(nullValue()));
                assertThat(count[0], is(2));
                assertThat(Arrays.toString(sink), is("[1, 2]"));
                assertThat(sb.getTotalBytesWritten(), is(sb.getTotalBytesRead() + sb.getAvailableBytesExact()));
            }
        }
    }

    /**
     * {@code safeWrite} with a concurrent {@code write(int)} (bug-hunt finding F02): the array
     * write is cloned, so the writer changing its array afterwards does not reach the reader.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void safeWriteWithAConcurrentSingleByteWrite_arrayCloned() throws InterruptedException {
        try (AllInterleavings all = interleavings("StreamBuffer.safeWrite")) {
            while (all.hasNext()) {
                final StreamBuffer sb = new StreamBuffer();
                sb.setSafeWrite(true);
                final OutputStream out = sb.getOutputStream();
                final InputStream in = sb.getInputStream();
                final AtomicReference<Throwable> failure = new AtomicReference<>();
                final byte[] array = {10, 20};

                final Thread arrayWriter = thread(failure, () -> {
                    out.write(array);
                    array[0] = 99; // after the write: must not reach the buffer
                });
                final Thread byteWriter = thread(failure, () -> out.write(5));
                joinAll(arrayWriter, byteWriter);

                final byte[] sink = new byte[3];
                assertThat(in.read(sink, 0, 3), is(3));
                assertThat(failure.get(), is(nullValue()));
                assertThat(Arrays.toString(sink), org.hamcrest.Matchers.anyOf(is("[10, 20, 5]"), is("[5, 10, 20]")));
            }
        } catch (java.io.IOException e) {
            throw new AssertionError(e);
        }
    }
}
