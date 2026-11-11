// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

import java.io.IOException;
import java.io.InputStream;
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
 * Two readers blocked in {@code read()} must both be released by {@code close()} (bug-hunt finding
 * F278: the close released one permit of a semaphore that held at most one, so one of two waiting
 * readers stayed blocked forever).
 *
 * <p>{@code Mode.Termination} has one actor; it starts the second reader itself and joins it, so
 * the actor terminates only once both readers returned.
 */
@JCStressTest(Mode.Termination)
@Description("Two readers blocked in read() must both be unblocked by close().")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "close() unblocked both readers")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "A reader stuck after close()")
@State
public class TwoReadersCloseRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();

    @Actor
    public void readers() throws InterruptedException {
        final Thread second = new Thread(this::readOnce);
        second.start();
        readOnce();
        second.join();
    }

    private void readOnce() {
        try {
            is.read();
        } catch (IOException ignored) {
            // an interrupted read; the outcome is the termination, not the value
        }
    }

    @Signal
    public void closer() throws IOException {
        sb.close();
    }
}
