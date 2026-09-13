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
 * Deadlock-freedom of the SECOND wait phase of the array read when the stream is closed.
 *
 * <p>Companion to {@link WriteUnblocksArrayReadRace}: the reader clears phase 1 on the pre-loaded
 * byte and parks in {@code waitForAtLeast(1)}; {@code close()} must release it (the array read then
 * returns the one byte it already copied — a partial read — rather than hanging forever).
 */
@JCStressTest(Mode.Termination)
@Description("A reader blocked in the second wait phase of read(byte[],off,len) must be unblocked by close().")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "close() unblocked the array reader")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "Array reader stuck after close()")
@State
public class CloseUnblocksArrayReadRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

    public CloseUnblocksArrayReadRace() {
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
            is.read(new byte[2], 0, 2);
        } catch (IOException ignored) {
            // acceptable: close races may surface as IOException in some paths
        }
    }

    @Signal
    public void closer() throws IOException {
        sb.close();
    }
}
