// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness for what {@code waitForAtLeast} returns next to a reader: one thread
 * waits for two bytes, another reads one, and a writer writes both bytes in one write and closes.
 * Not a JUnit test; compiled with {@code javac --release 8} and run under JPF, see
 * {@code src/test/jpf/README.md}.
 *
 * <p>Over every interleaving: the waiter's result is fewer than two only on a buffer that was
 * closed when it returned (its JML postcondition). The close is observed through
 * {@code closedBefore}, set by the writer before it closes, so a later close cannot excuse a short
 * result. Before 2026-11-12 the waiting branch read {@code availableBytes} again after its check,
 * and the reader could take a byte in between: the waiter returned 1 on an open buffer.
 */
public final class JpfWaitSnapshotHarness {

    private JpfWaitSnapshotHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final boolean[] closing = {false};

        final Thread writer = new Thread(() -> {
            try {
                os.write(new byte[] {7, 8});
                closing[0] = true;
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("writer must not fail", e);
            }
        });
        final Thread waiter = new Thread(() -> {
            try {
                final long waited = sb.waitForAtLeast(2);
                if (waited < 2 && !closing[0]) {
                    throw new AssertionError("waitForAtLeast(2) returned " + waited + " before the close began");
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

        if (read[0] != 7) {
            throw new AssertionError("reader got " + read[0] + ", expected the byte 7");
        }
    }
}
