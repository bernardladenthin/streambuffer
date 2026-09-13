// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness: exhaustively model-checks the concurrent read/write/close protocol of
 * {@link StreamBuffer} over ALL thread interleavings JPF can enumerate — a stronger guarantee than
 * the jcstress termination tests (which sample hardware-driven schedules). This is deliberately NOT
 * a JUnit test: it is compiled with {@code javac --release 8} and run under JPF (JDK 11), never by
 * Maven surefire; see {@code src/test/jpf/README.md} and the {@code jpf-interleavings} job in
 * {@code .github/workflows/formal-verification.yml}.
 *
 * <p>Deliberately tiny (two bytes, two worker threads) so the state space stays tractable — the
 * last confirmed run explored ~14k states, maxDepth 130. JPF flags three failure classes: deadlocks
 * (a thread parked forever on the semaphore), uncaught exceptions, and the explicit oracle throws
 * below (byte fidelity). Keep the payload minimal; the state space explodes fast.
 */
public final class JpfStreamBufferHarness {

    private JpfStreamBufferHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final byte[] payload = {0x41, 0x42};

        final Thread writer = new Thread(() -> {
            try {
                os.write(payload[0]);
                os.write(payload[1]);
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("writer must not fail", e);
            }
        });

        final byte[] got = new byte[payload.length];
        final int[] count = {0};

        final Thread reader = new Thread(() -> {
            try {
                int c;
                while ((c = is.read()) != -1) {
                    if (count[0] < got.length) {
                        got[count[0]] = (byte) c;
                    }
                    count[0]++;
                }
            } catch (IOException e) {
                throw new AssertionError("reader must not fail", e);
            }
        });

        writer.start();
        reader.start();
        writer.join();
        reader.join();

        // Every interleaving must deliver exactly the two written bytes, in order, then EOF.
        // Explicit throws, NOT `assert`: JPF does not reliably enable Java assertions for the SUT
        // (a disabled assert would make this oracle vacuous — verified with a negative control),
        // whereas a thrown Throwable is always caught by JPF's NoUncaughtExceptionsProperty.
        if (count[0] != payload.length) {
            throw new AssertionError("read " + count[0] + " bytes, expected " + payload.length);
        }
        if (got[0] != payload[0] || got[1] != payload[1]) {
            throw new AssertionError("byte order/content corrupted");
        }
    }
}
