// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness for fixed-size records with two competing readers: a writer writes the
 * two 2-byte records {@code {1, 2}} and {@code {3, 4}} fragmented across the record boundary (as
 * {@code [1]} and {@code [2, 3, 4]}) and closes; two readers each call {@code read(b, 0, 2)} until
 * the end of the stream. Not a JUnit test; compiled with {@code javac --release 8} and run under JPF,
 * see {@code src/test/jpf/README.md}.
 *
 * <p>Over every interleaving JPF checks for deadlocks, uncaught exceptions and the explicit oracle
 * below: every read returns a whole record, and both records arrive exactly once. Before
 * {@code read(b, off, len)} took its bytes in one step, a reader took the first byte, released the
 * lock and waited for the rest, so the other reader could take bytes in between and a reader got
 * {@code {1, 3}}; that is also the proof that the harness can fail.
 */
public final class JpfRecordReadersHarness {

    private JpfRecordReadersHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final Thread writer = new Thread(() -> {
            try {
                os.write(new byte[] {1});
                os.write(new byte[] {2, 3, 4});
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("writer must not fail", e);
            }
        });

        // first[r]: the first byte of each record reader r got (1 or 3); count[r]: how many
        final int[][] first = new int[2][2];
        final int[] count = new int[2];
        final Thread[] readers = new Thread[2];
        for (int r = 0; r < readers.length; r++) {
            final int reader = r;
            readers[r] = new Thread(() -> {
                try {
                    final byte[] rec = new byte[2];
                    int n;
                    while ((n = is.read(rec, 0, 2)) != -1) {
                        if (n != 2 || rec[1] != rec[0] + 1 || (rec[0] != 1 && rec[0] != 3)) {
                            throw new AssertionError(
                                    "reader " + reader + " got a torn record: n=" + n + ", " + rec[0] + ", " + rec[1]);
                        }
                        if (count[reader] < 2) {
                            first[reader][count[reader]] = rec[0];
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
        if (count[0] + count[1] != 2) {
            throw new AssertionError("readers got " + count[0] + " + " + count[1] + " records, expected 2");
        }
        int sum = 0;
        for (int r = 0; r < readers.length; r++) {
            for (int i = 0; i < count[r]; i++) {
                sum += first[r][i];
            }
        }
        if (sum != 1 + 3) {
            throw new AssertionError("a record was delivered twice and another one never");
        }
    }
}
