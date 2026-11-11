// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness for a {@code waitForAtLeast} caller next to a reader: one thread waits
 * for two bytes, another reads one, and a writer writes a single byte and closes. Not a JUnit test;
 * compiled with {@code javac --release 8} and run under JPF, see {@code src/test/jpf/README.md}.
 *
 * <p>Over every interleaving: no deadlock, no uncaught exception, the reader gets the byte, and
 * the waiter returns fewer than two bytes only because the buffer is closed. Before bug-hunt
 * finding F278 the one permit of the write or the close could go to the waiter, which waits for
 * more and goes back to waiting, so the reader stayed blocked although a byte was buffered.
 */
public final class JpfWaitAndReadHarness {

    private JpfWaitAndReadHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final Thread writer = new Thread(() -> {
            try {
                os.write(7);
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("writer must not fail", e);
            }
        });
        final long[] waited = {-1};
        final Thread waiter = new Thread(() -> {
            try {
                waited[0] = sb.waitForAtLeast(2);
                // checked right after the return: closed stays closed, so this cannot flip later
                if (waited[0] < 2 && !sb.isClosed()) {
                    throw new AssertionError("waitForAtLeast(2) returned " + waited[0] + " on an open buffer");
                }
            } catch (InterruptedException e) {
                throw new AssertionError("waiter must not be interrupted", e);
            }
        });
        final int[] read = {-2};
        final Thread reader = new Thread(() -> {
            try {
                read[0] = is.read();
            } catch (IOException e) {
                throw new AssertionError("reader must not fail", e);
            }
        });

        writer.start();
        waiter.start();
        reader.start();
        writer.join();
        waiter.join();
        reader.join();

        // Explicit throws, not `assert` (see JpfStreamBufferHarness).
        if (read[0] != 7) {
            throw new AssertionError("reader got " + read[0] + ", expected the byte 7");
        }
        if (waited[0] < 0 || waited[0] > 1) {
            throw new AssertionError("waitForAtLeast(2) returned " + waited[0] + " with at most one byte written");
        }
    }
}
