// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

import java.io.IOException;
import java.io.OutputStream;
import java.util.concurrent.Semaphore;
import net.ladenthin.streambuffer.StreamBuffer;
import org.openjdk.jcstress.annotations.Actor;
import org.openjdk.jcstress.annotations.Arbiter;
import org.openjdk.jcstress.annotations.Description;
import org.openjdk.jcstress.annotations.Expect;
import org.openjdk.jcstress.annotations.JCStressTest;
import org.openjdk.jcstress.annotations.Outcome;
import org.openjdk.jcstress.annotations.State;
import org.openjdk.jcstress.infra.results.I_Result;

/**
 * Two writers and a closer signal a registered semaphore at the same time: it must end with
 * exactly one permit ("max 1 permit" of {@code addSignal}, bug-hunt finding F280). Before F280
 * the check for no permit and the release were two steps, so two or three permits were possible.
 */
@JCStressTest
@Description("Concurrent writes and a close must leave a registered signal with at most one permit.")
@Outcome(id = "1", expect = Expect.ACCEPTABLE, desc = "One permit, however the signals interleave")
@Outcome(id = "0", expect = Expect.FORBIDDEN, desc = "A modification was not signaled")
@Outcome(
        id = {"2", "3"},
        expect = Expect.FORBIDDEN,
        desc = "More than one permit (F280)")
@State
public class SignalMaxOnePermitRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final OutputStream os = sb.getOutputStream();
    private final Semaphore signal = new Semaphore(0);

    public SignalMaxOnePermitRace() {
        sb.addSignal(signal);
    }

    @Actor
    public void writerA() {
        try {
            os.write(1);
        } catch (IOException ignored) {
            // a write racing the close may fail; the close signals then
        }
    }

    @Actor
    public void writerB() {
        try {
            os.write(2);
        } catch (IOException ignored) {
            // see writerA()
        }
    }

    @Actor
    public void closer() {
        try {
            sb.close();
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @Arbiter
    public void check(I_Result r) {
        r.r1 = signal.availablePermits();
    }
}
