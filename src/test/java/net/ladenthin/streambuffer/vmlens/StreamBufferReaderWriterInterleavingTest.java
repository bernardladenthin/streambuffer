// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.vmlens;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;

import com.vmlens.api.AllInterleavings;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.atomic.AtomicReference;
import net.ladenthin.streambuffer.StreamBuffer;
import org.junit.jupiter.api.Test;

/**
 * vmlens interleaving analysis of a concurrent reader and writer on a
 * {@link StreamBuffer}.
 *
 * <p>A writer thread writes a fixed payload while a reader thread drains it. The
 * reader's blocking path ({@code waitForAtLeast}) reads {@code availableBytes} and
 * {@code streamClosed} <em>outside</em> {@code bufferLock}, while the writer
 * mutates {@code availableBytes} and the byte counters under the lock and only
 * then releases the wakeup semaphore. The byte-accounting invariant
 * {@code totalBytesWritten == totalBytesRead + availableBytes} must therefore hold
 * at quiescence for <em>every</em> interleaving — no byte may be lost or
 * double-counted in the hand-off between the lock-free wait gate and the
 * lock-protected mutation.</p>
 *
 * <p>This is the interleaving class that the existing coverage does not reach: the
 * Lincheck test deliberately omits {@code read} (a model checker cannot progress
 * past a parked reader) and the jcstress close/unblock races assert only
 * <em>termination</em>, not the resulting accounting. Like the rest of the
 * package it runs only under the vmlens agent (see the {@code vmlens} profile and
 * the {@code maven-surefire-plugin} {@code <excludes>} in {@code pom.xml}).</p>
 */
public class StreamBufferReaderWriterInterleavingTest {

    /**
     * Drives a writer against a reader through every interleaving and asserts the
     * write/read/buffered byte-accounting invariant after both threads finish.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void readerWriterAccountingHoldsUnderAllInterleavings() throws InterruptedException {
        try (AllInterleavings allInterleavings = new AllInterleavings("StreamBuffer.readerWriterAccounting")) {
            while (allInterleavings.hasNext()) {
                final StreamBuffer streamBuffer = new StreamBuffer();
                final OutputStream out = streamBuffer.getOutputStream();
                final InputStream in = streamBuffer.getInputStream();
                final byte[] payload = {10, 20, 30, 40};
                final byte[] sink = new byte[payload.length];
                final AtomicReference<Throwable> failure = new AtomicReference<>();

                final Thread writer = new Thread(() -> {
                    try {
                        out.write(payload);
                    } catch (Throwable t) {
                        failure.compareAndSet(null, t);
                    }
                });
                final Thread reader = new Thread(() -> {
                    try {
                        in.read(sink, 0, sink.length);
                    } catch (Throwable t) {
                        failure.compareAndSet(null, t);
                    }
                });

                writer.start();
                reader.start();
                writer.join();
                reader.join();

                assertThat(failure.get(), is(nullValue()));
                assertThat(streamBuffer.getTotalBytesWritten(), is((long) payload.length));
                assertThat(
                        streamBuffer.getTotalBytesWritten(),
                        is(streamBuffer.getTotalBytesRead() + streamBuffer.getAvailableBytesExact()));
            }
        }
    }
}
