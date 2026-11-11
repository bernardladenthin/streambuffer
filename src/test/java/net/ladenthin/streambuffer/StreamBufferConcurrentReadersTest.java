// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.junit.jupiter.api.Assertions.fail;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Several threads reading from the same {@link StreamBuffer} (bug-hunt finding F278).
 *
 * <p>Until F278 the buffer was correct for one reader only: a write or a {@code close()} woke at
 * most one waiting reader (the internal semaphore held at most one permit), and a reader checked
 * the buffered byte count outside the lock and then took the first FIFO entry under it without
 * checking again. Every test here was red before the fix. The contract now: each byte is delivered
 * to exactly one reader, in FIFO order, no reader blocks while bytes are buffered or after the
 * close, and {@code read()} throws no unchecked exception. There is no fairness between readers.
 */
public class StreamBufferConcurrentReadersTest {

    /** How long a reader that should return may take; generous, a correct run needs microseconds. */
    private static final long RETURN_TIMEOUT_SECONDS = 10;

    /** Result of a reader thread: the values it read, or the throwable it died with. */
    private static final class ReaderResult {
        final List<Integer> values = Collections.synchronizedList(new ArrayList<>());
        volatile Throwable failure;
    }

    private static Thread daemon(final Runnable body) {
        final Thread thread = new Thread(body);
        thread.setDaemon(true);
        return thread;
    }

    /** Runs {@code body}, records an unexpected throwable and counts the latch down either way. */
    private static Thread reader(final ReaderResult result, final CountDownLatch done, final ThrowingRunnable body) {
        return daemon(() -> {
            try {
                body.run();
            } catch (Throwable t) {
                result.failure = t;
            } finally {
                done.countDown();
            }
        });
    }

    @FunctionalInterface
    private interface ThrowingRunnable {
        void run() throws Exception;
    }

    private static void awaitState(final Thread thread, final Thread.State state) {
        final long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(RETURN_TIMEOUT_SECONDS);
        while (thread.getState() != state) {
            if (System.nanoTime() > deadline) {
                fail("thread did not reach " + state + ", it is " + thread.getState());
            }
            Thread.yield();
        }
    }

    private static void assertNoFailure(final ReaderResult... results) {
        for (ReaderResult result : results) {
            if (result.failure != null) {
                throw new AssertionError("a reader failed: " + result.failure, result.failure);
            }
        }
    }

    private static List<Integer> allValues(final ReaderResult... results) {
        final List<Integer> all = new ArrayList<>();
        for (ReaderResult result : results) {
            all.addAll(result.values);
        }
        Collections.sort(all);
        return all;
    }

    @DisplayName("two readers parked in read(), then two single-byte writes — both readers return")
    @Test
    public void read_twoParkedReadersTwoWrites_bothReturn() throws Exception {
        for (int run = 0; run < StreamBufferTest.iterations(100, 10); run++) {
            // arrange
            final StreamBuffer sb = new StreamBuffer();
            final InputStream is = sb.getInputStream();
            final OutputStream os = sb.getOutputStream();
            final CountDownLatch done = new CountDownLatch(2);
            final ReaderResult a = new ReaderResult();
            final ReaderResult b = new ReaderResult();
            final Thread readerA = reader(a, done, () -> a.values.add(is.read()));
            final Thread readerB = reader(b, done, () -> b.values.add(is.read()));
            readerA.start();
            readerB.start();
            awaitState(readerA, Thread.State.WAITING);
            awaitState(readerB, Thread.State.WAITING);

            // act
            os.write(1);
            os.write(2);

            // assert
            final boolean bothReturned = done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            sb.close();
            assertThat("run " + run + ": both readers returned although 2 bytes were buffered", bothReturned, is(true));
            assertNoFailure(a, b);
            assertThat(allValues(a, b), is(java.util.Arrays.asList(1, 2)));
        }
    }

    @DisplayName("two readers parked in read(), then close() — both readers report the end of the stream")
    @Test
    public void read_twoParkedReadersClose_bothReturnEndOfStream() throws Exception {
        for (int run = 0; run < StreamBufferTest.iterations(20, 5); run++) {
            // arrange
            final StreamBuffer sb = new StreamBuffer();
            final InputStream is = sb.getInputStream();
            final CountDownLatch done = new CountDownLatch(2);
            final ReaderResult a = new ReaderResult();
            final ReaderResult b = new ReaderResult();
            final Thread readerA = reader(a, done, () -> a.values.add(is.read()));
            final Thread readerB = reader(b, done, () -> b.values.add(is.read()));
            readerA.start();
            readerB.start();
            awaitState(readerA, Thread.State.WAITING);
            awaitState(readerB, Thread.State.WAITING);

            // act
            sb.close();

            // assert
            assertThat(
                    "run " + run + ": both readers returned after close()",
                    done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS),
                    is(true));
            assertNoFailure(a, b);
            assertThat(allValues(a, b), is(java.util.Arrays.asList(-1, -1)));
        }
    }

    @DisplayName("three readers past the wait, two bytes buffered — no exception, the third waits for the close")
    @Test
    public void read_threeReadersAtTheLockTwoBytes_noExceptionEachByteOnce() throws Exception {
        // arrange: a trim start signal that blocks holds the writer inside trim(), i.e. under the
        // buffer lock, after the write has already counted its byte. The readers then pass the wait
        // (2 bytes buffered) and queue up at the lock, so all three are between the wait and the
        // removal from the FIFO at the same time; before F278 the third called getFirst() on an
        // empty deque and died with NoSuchElementException.
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();
        final OutputStream os = sb.getOutputStream();
        sb.setMaxBufferElements(1);
        os.write(1); // one entry, no trim yet
        final CountDownLatch inTrim = new CountDownLatch(1);
        final CountDownLatch leaveTrim = new CountDownLatch(1);
        sb.addTrimStartSignal(new Semaphore(0) {
            private static final long serialVersionUID = 1L;

            @Override
            public void release() {
                inTrim.countDown();
                try {
                    leaveTrim.await();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                super.release();
            }
        });
        final Thread writer = daemon(() -> {
            try {
                os.write(2); // two entries > maxBufferElements: trims, blocks in the start signal
            } catch (IOException e) {
                throw new AssertionError(e);
            }
        });
        writer.start();
        assertThat(inTrim.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS), is(true));

        final CountDownLatch done = new CountDownLatch(3);
        final ReaderResult[] results = {new ReaderResult(), new ReaderResult(), new ReaderResult()};
        final Thread[] readers = new Thread[3];
        for (int i = 0; i < readers.length; i++) {
            final ReaderResult result = results[i];
            readers[i] = reader(result, done, () -> result.values.add(is.read()));
            readers[i].start();
        }
        for (Thread reader : readers) {
            awaitState(reader, Thread.State.BLOCKED);
        }

        // act
        leaveTrim.countDown();
        writer.join(TimeUnit.SECONDS.toMillis(RETURN_TIMEOUT_SECONDS));
        final long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(RETURN_TIMEOUT_SECONDS);
        while (done.getCount() > 1 && System.nanoTime() < deadline) {
            Thread.yield();
        }
        sb.close();

        // assert
        assertThat(done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS), is(true));
        assertNoFailure(results);
        assertThat(allValues(results), is(java.util.Arrays.asList(-1, 1, 2)));
    }

    @DisplayName("read(byte[]) and read() race for two buffered bytes — no exception, no byte lost")
    @Test
    public void read_arrayReaderAndByteReaderRace_noExceptionNoByteLost() throws Exception {
        for (int run = 0; run < StreamBufferTest.iterations(3000, 50); run++) {
            // arrange
            final StreamBuffer sb = new StreamBuffer();
            final InputStream is = sb.getInputStream();
            sb.getOutputStream().write(new byte[] {1, 2});
            final CyclicBarrier start = new CyclicBarrier(2);
            final CountDownLatch done = new CountDownLatch(2);
            final ReaderResult a = new ReaderResult();
            final ReaderResult b = new ReaderResult();
            final Thread readerA = reader(a, done, () -> {
                final byte[] dest = new byte[2];
                start.await();
                final int n = is.read(dest, 0, 2);
                for (int i = 0; i < n; i++) {
                    a.values.add((int) dest[i]);
                }
            });
            final Thread readerB = reader(b, done, () -> {
                start.await();
                final int value = is.read();
                if (value != -1) {
                    b.values.add(value);
                }
            });

            // act
            readerA.start();
            readerB.start();
            final long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(RETURN_TIMEOUT_SECONDS);
            while (sb.getAvailableBytesExact() > 0 && System.nanoTime() < deadline) {
                Thread.yield();
            }
            sb.close();

            // assert
            assertThat(
                    "run " + run + ": both readers returned",
                    done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS),
                    is(true));
            assertNoFailure(a, b);
            assertThat("run " + run, allValues(a, b), is(java.util.Arrays.asList(1, 2)));
        }
    }

    @DisplayName("waitForAtLeast(10) and read() parked, then a one-byte write — read() returns the byte")
    @Test
    public void read_parkedNextToALargerWait_oneByteWrite_readReturns() throws Exception {
        // A semaphore with at most one permit wakes one of the two waiters; when that is the one
        // waiting for ten bytes, it goes back to waiting and the byte reader stays blocked although
        // a byte is buffered. Passing the permit on when a waiter returns does not fix that, since
        // the woken waiter does not return; every waiter has to be woken.
        for (int run = 0; run < StreamBufferTest.iterations(100, 10); run++) {
            // arrange
            final StreamBuffer sb = new StreamBuffer();
            final InputStream is = sb.getInputStream();
            final CountDownLatch byteRead = new CountDownLatch(1);
            final CountDownLatch done = new CountDownLatch(2);
            final ReaderResult waiter = new ReaderResult();
            final ReaderResult byteReader = new ReaderResult();
            final Thread waitingThread = reader(waiter, done, () -> sb.waitForAtLeast(10));
            final Thread readingThread = reader(byteReader, done, () -> {
                byteReader.values.add(is.read());
                byteRead.countDown();
            });
            waitingThread.start();
            readingThread.start();
            awaitState(waitingThread, Thread.State.WAITING);
            awaitState(readingThread, Thread.State.WAITING);

            // act
            sb.getOutputStream().write(7);

            // assert
            final boolean returned = byteRead.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            sb.close();
            assertThat("run " + run + ": read() returned the buffered byte", returned, is(true));
            assertThat(done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS), is(true));
            assertNoFailure(waiter, byteReader);
            assertThat(byteReader.values, is(java.util.Collections.singletonList(7)));
        }
    }

    @DisplayName("three writers, three readers — every byte arrives exactly once, each writer's bytes in order")
    @Test
    public void readWrite_threeWritersThreeReaders_everyByteOnceInWriterOrder() throws Exception {
        final int writers = 3;
        final int perWriter = 80; // values w * perWriter + i stay below 256
        for (int run = 0; run < StreamBufferTest.iterations(50, 3); run++) {
            // arrange
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4); // let trim run while the readers read
            final InputStream is = sb.getInputStream();
            final OutputStream os = sb.getOutputStream();
            final CyclicBarrier start = new CyclicBarrier(2 * writers);
            final ConcurrentLinkedQueue<Throwable> failures = new ConcurrentLinkedQueue<>();
            final List<Thread> writerThreads = new ArrayList<>();
            for (int w = 0; w < writers; w++) {
                final int writer = w;
                writerThreads.add(daemon(() -> {
                    try {
                        start.await();
                        for (int i = 0; i < perWriter; i += 2) {
                            if (i % 4 == 0) {
                                os.write(writer * perWriter + i);
                                os.write(writer * perWriter + i + 1);
                            } else {
                                os.write(
                                        new byte[] {(byte) (writer * perWriter + i), (byte) (writer * perWriter + i + 1)
                                        });
                            }
                        }
                    } catch (Throwable t) {
                        failures.add(t);
                    }
                }));
            }
            final CountDownLatch done = new CountDownLatch(writers);
            final ReaderResult[] results = new ReaderResult[writers];
            final List<Thread> readerThreads = new ArrayList<>();
            for (int r = 0; r < writers; r++) {
                final ReaderResult result = new ReaderResult();
                results[r] = result;
                final boolean arrays = r % 2 == 0;
                readerThreads.add(reader(result, done, () -> {
                    start.await();
                    final byte[] dest = new byte[3];
                    while (true) {
                        if (arrays) {
                            final int n = is.read(dest, 0, dest.length);
                            if (n == -1) {
                                return;
                            }
                            for (int i = 0; i < n; i++) {
                                result.values.add(dest[i] & 0xff);
                            }
                        } else {
                            final int value = is.read();
                            if (value == -1) {
                                return;
                            }
                            result.values.add(value);
                        }
                    }
                }));
            }

            // act
            writerThreads.forEach(Thread::start);
            readerThreads.forEach(Thread::start);
            for (Thread writerThread : writerThreads) {
                writerThread.join(TimeUnit.SECONDS.toMillis(RETURN_TIMEOUT_SECONDS));
            }
            sb.close();

            // assert
            assertThat(
                    "run " + run + ": every reader saw the end",
                    done.await(RETURN_TIMEOUT_SECONDS, TimeUnit.SECONDS),
                    is(true));
            if (!failures.isEmpty()) {
                throw new AssertionError("a writer failed", failures.peek());
            }
            assertNoFailure(results);
            final List<Integer> expected = new ArrayList<>();
            for (int v = 0; v < writers * perWriter; v++) {
                expected.add(v);
            }
            assertThat("run " + run + ": every byte exactly once", allValues(results), is(expected));
            for (ReaderResult result : results) {
                final int[] last = new int[writers];
                java.util.Arrays.fill(last, -1);
                for (int value : result.values) {
                    final int writer = value / perWriter;
                    assertThat(
                            "run " + run + ": a reader sees each writer's bytes in order",
                            value > last[writer],
                            is(true));
                    last[writer] = value;
                }
            }
        }
    }
}
