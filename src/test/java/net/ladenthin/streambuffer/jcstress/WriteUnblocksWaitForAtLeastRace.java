// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

import java.io.IOException;
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
 * Deadlock-freedom of the public blocking API {@link StreamBuffer#waitForAtLeast(long)}.
 *
 * <p>{@code waitForAtLeast(2)} parks on the internal semaphore until at least two bytes are
 * buffered (or the stream closes). A writer publishing the two bytes must release it — this is the
 * lost-wakeup guard for the observer/consumer API, which no other termination test exercises (the
 * read* tests drive the semaphore indirectly through the stream, this drives it directly).
 */
@JCStressTest(Mode.Termination)
@Description("A thread blocked in waitForAtLeast(2) must be unblocked when a writer publishes enough bytes.")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "write() unblocked waitForAtLeast")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "waitForAtLeast stuck after write()")
@State
public class WriteUnblocksWaitForAtLeastRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final OutputStream os = sb.getOutputStream();

    @Actor
    public void waiter() {
        try {
            sb.waitForAtLeast(2L);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    @Signal
    public void writer() throws IOException {
        // One write of two bytes lifts availableBytes to 2 in a single modification signal.
        os.write(new byte[] {0x42, 0x43});
    }
}
