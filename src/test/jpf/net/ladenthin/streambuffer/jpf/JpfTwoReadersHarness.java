// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness with two readers on the same input stream (bug-hunt finding F278): a
 * writer writes two bytes and closes, two readers call {@code read()} until the end of the stream.
 * Not a JUnit test; compiled with {@code javac --release 8} and run under JPF, see
 * {@code src/test/jpf/README.md}.
 *
 * <p>Over every interleaving JPF checks that no reader blocks forever (deadlock), that no thread
 * dies with an uncaught exception, and the explicit oracle below: each written byte reaches exactly
 * one reader, and a reader that got both got them in order. Before F278 JPF reports a deadlock
 * here (the close wakes one of two waiting readers) or the {@code NoSuchElementException} of a
 * reader that found the FIFO empty under the lock, which is also the proof that the harness can
 * fail.
 */
public final class JpfTwoReadersHarness {

    private JpfTwoReadersHarness() {}

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

        // got[r][i]: the i-th byte reader r received; count[r]: how many it received
        final int[][] got = new int[2][payload.length];
        final int[] count = new int[2];
        final Thread[] readers = new Thread[2];
        for (int r = 0; r < readers.length; r++) {
            final int reader = r;
            readers[r] = new Thread(() -> {
                try {
                    int c;
                    while ((c = is.read()) != -1) {
                        if (count[reader] < payload.length) {
                            got[reader][count[reader]] = c;
                        }
                        count[reader]++;
                    }
                } catch (IOException e) {
                    throw new AssertionError("reader must not fail", e);
                }
            });
        }

        writer.start();
        readers[0].start();
        readers[1].start();
        writer.join();
        readers[0].join();
        readers[1].join();

        // Explicit throws, not `assert` (see JpfStreamBufferHarness).
        if (count[0] + count[1] != payload.length) {
            throw new AssertionError("readers got " + count[0] + " + " + count[1] + " bytes, expected "
                    + payload.length);
        }
        boolean sawFirst = false;
        boolean sawSecond = false;
        for (int r = 0; r < readers.length; r++) {
            for (int i = 0; i < count[r]; i++) {
                if (got[r][i] == payload[0]) {
                    sawFirst = true;
                } else if (got[r][i] == payload[1]) {
                    sawSecond = true;
                } else {
                    throw new AssertionError("reader " + r + " got a byte that was never written: " + got[r][i]);
                }
            }
            if (count[r] == 2 && (got[r][0] != payload[0] || got[r][1] != payload[1])) {
                throw new AssertionError("reader " + r + " got both bytes out of order");
            }
        }
        if (!sawFirst || !sawSecond) {
            throw new AssertionError("a byte was delivered twice and another one never");
        }
    }
}
