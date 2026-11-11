// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.Semaphore;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * After a trim, the buffer references no array the caller still holds: without {@code safeWrite} a
 * write stores the caller's array, and a trim is the point from which overwriting that array no
 * longer changes what is read. A trim that keeps some entries as they are (merging only the newest
 * ones) must keep only arrays it allocated itself.
 */
class StreamBufferTrimOwnershipTest {

    @ParameterizedTest(name = "maxBufferElements={0}")
    @ValueSource(ints = {8, 16, 64})
    void callerArraysWrittenBeforeATrimCanBeOverwritten(final int maxBufferElements) throws IOException {
        final StreamBuffer sb = new StreamBuffer();
        sb.setSafeWrite(false);
        sb.setMaxBufferElements(maxBufferElements);
        final Semaphore trimmed = new Semaphore(0);
        sb.addTrimEndSignal(trimmed);
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final ByteArrayOutputStream expected = new ByteArrayOutputStream();
        final ByteArrayOutputStream actual = new ByteArrayOutputStream();
        final List<byte[]> heldByCaller = new ArrayList<>();
        int trims = 0;
        byte value = 0;
        for (int i = 0; i < 2000; i++) {
            // one long write per maxBufferElements writes, the others short: a trim then merges the
            // short ones at the tail and could stop at the long caller array before them
            final byte[] b = new byte[i % maxBufferElements == 0 ? 100 : 1 + i % 3];
            for (int k = 0; k < b.length; k++) {
                b[k] = value++;
            }
            expected.write(b);
            os.write(b);
            heldByCaller.add(b);
            if (trimmed.tryAcquire()) {
                trims++;
                // every array written so far went through this trim: overwrite them all
                for (final byte[] held : heldByCaller) {
                    Arrays.fill(held, (byte) 0x5A);
                }
                heldByCaller.clear();
            }
            if (i % 7 == 6) {
                // read a little in between: partly read head entries, a shrinking prefix
                final byte[] part = new byte[1 + i % 5];
                final int n = is.read(part, 0, Math.min(part.length, is.available()));
                if (n > 0) {
                    actual.write(part, 0, n);
                }
            }
        }
        sb.close();
        final byte[] rest = new byte[64];
        int n;
        while ((n = is.read(rest)) > 0) {
            actual.write(rest, 0, n);
        }
        assertTrue(trims > 10, "trims ran: " + trims);
        assertArrayEquals(expected.toByteArray(), actual.toByteArray());
    }
}
