// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness for the order of {@code write} and {@code close()} (bug hunt F149): a
 * writer, a closer and a reader in three separate threads over one {@link StreamBuffer}. Like
 * {@link JpfStreamBufferHarness} it is compiled with {@code javac --release 8} and run under JPF
 * (JDK 11), never by Maven surefire; see {@code src/test/jpf/README.md}.
 *
 * <p>{@link JpfStreamBufferHarness} writes and closes from one thread, so a write can never race the
 * close there, and it could not see F149: {@code writeFromArray} checked {@code streamClosed} outside
 * {@code bufferLock}, so a write could pass the check, lose the lock to {@code close()}, and then add
 * its bytes after the reader had already seen the end of the stream -- the write returned normally
 * and its bytes were lost. Here the writer writes two single bytes, each of which either succeeds or
 * fails with "Stream closed", and the reader reads until {@code -1}. Over every interleaving JPF
 * enumerates:
 *
 * <ul>
 *   <li>no deadlock and no uncaught exception (JPF's own properties);
 *   <li>once a write failed, every later write fails too (close is sticky);
 *   <li>the reader receives exactly the bytes whose write returned normally, in order: a successful
 *       write is ordered before the close and never lost for the reader.
 * </ul>
 *
 * <p>Measured with the pinned jpf-core: with the F149 fix no errors over 75,438 states (about 15 s);
 * against the production classes before the fix ({@code 1529d3b^}) JPF finds the race after 3,956
 * states: "reader got 1 bytes, but 2 writes returned normally". Keep the payload at two bytes; the
 * state space grows fast.
 */
public final class JpfWriteCloseHarness {

    private JpfWriteCloseHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final byte[] payload = {0x41, 0x42};
        final boolean[] ok = new boolean[payload.length];

        final Thread writer = new Thread(() -> {
            for (int i = 0; i < payload.length; i++) {
                try {
                    os.write(payload[i]);
                    ok[i] = true;
                } catch (IOException e) {
                    ok[i] = false;
                }
            }
        });

        final Thread closer = new Thread(() -> {
            try {
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("close must not fail", e);
            }
        });

        // One slot more than the payload, so a reader that sees a byte too many is caught too.
        final byte[] got = new byte[payload.length + 1];
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
        closer.start();
        reader.start();
        writer.join();
        closer.join();
        reader.join();

        // Explicit throws rather than `assert`, as in JpfStreamBufferHarness: JPF reports an uncaught
        // AssertionError regardless of whether assertions are enabled for the system under test.
        int succeeded = 0;
        for (int i = 0; i < payload.length; i++) {
            if (ok[i]) {
                if (i != succeeded) {
                    throw new AssertionError("write " + i + " succeeded after an earlier write failed");
                }
                succeeded++;
            }
        }
        if (count[0] != succeeded) {
            throw new AssertionError("reader got " + count[0] + " bytes, but " + succeeded
                    + " writes returned normally (F149: write succeeded after the reader saw EOF)");
        }
        for (int i = 0; i < succeeded; i++) {
            if (got[i] != payload[i]) {
                throw new AssertionError("byte " + i + " corrupted");
            }
        }
    }
}
