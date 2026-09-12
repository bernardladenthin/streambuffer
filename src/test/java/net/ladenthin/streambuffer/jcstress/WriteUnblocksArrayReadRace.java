// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;
import org.openjdk.jcstress.annotations.Actor;
import org.openjdk.jcstress.annotations.Description;
import org.openjdk.jcstress.annotations.Expect;
import org.openjdk.jcstress.annotations.JCStressTest;
import org.openjdk.jcstress.annotations.Mode;
import org.openjdk.jcstress.annotations.Outcome;
import org.openjdk.jcstress.annotations.Signal;
import org.openjdk.jcstress.annotations.State;

/**
 * Deadlock-freedom of the SECOND wait phase of the array read.
 *
 * <p>{@link InputStream#read(byte[], int, int)} first consumes one byte (phase 1, the same
 * {@code waitForAnyData()} path {@link WriteUnblocksReadRace} covers) and then blocks in
 * {@code waitForAtLeast(missingBytes)} for the rest (phase 2, distinct logic — the partial-copy
 * loop). The single-byte {@link WriteUnblocksReadRace} never reaches phase 2. Here the state
 * pre-writes exactly one byte, so the reader clears phase 1 without blocking and parks in phase 2
 * waiting for a second byte; the writer's byte must release it.
 */
@JCStressTest(Mode.Termination)
@Description("A reader blocked in the second wait phase of read(byte[],off,len) must be unblocked by a write.")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "write() unblocked the array reader")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "Array reader stuck after write()")
@State
public class WriteUnblocksArrayReadRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

    public WriteUnblocksArrayReadRace() {
        try {
            // Pre-load one byte so the reader clears phase 1 and blocks in phase 2.
            os.write(0x41);
        } catch (IOException e) {
            throw new IllegalStateException("priming write failed", e);
        }
    }

    @Actor
    public void reader() {
        try {
            // Wants two bytes; one is already buffered, so this parks in waitForAtLeast(1).
            is.read(new byte[2], 0, 2);
        } catch (IOException ignored) {
            // not expected on this path, but tolerated
        }
    }

    @Signal
    public void writer() throws IOException {
        os.write(0x42);
    }
}
