// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

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
 * Deadlock-freedom of {@link StreamBuffer#waitForAtLeast(long)} against close().
 *
 * <p>Companion to {@link WriteUnblocksWaitForAtLeastRace}: a thread parked in
 * {@code waitForAtLeast(2)} with no data must be released by {@code close()} — the method returns
 * the bytes available at close (here {@code 0}) instead of hanging. This is the shutdown path for a
 * blocked consumer.
 */
@JCStressTest(Mode.Termination)
@Description("A thread blocked in waitForAtLeast(2) must be unblocked by close().")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "close() unblocked waitForAtLeast")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "waitForAtLeast stuck after close()")
@State
public class CloseUnblocksWaitForAtLeastRace {

    private final StreamBuffer sb = new StreamBuffer();

    @Actor
    public void waiter() {
        try {
            sb.waitForAtLeast(2L);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    @Signal
    public void closer() throws java.io.IOException {
        sb.close();
    }
}
