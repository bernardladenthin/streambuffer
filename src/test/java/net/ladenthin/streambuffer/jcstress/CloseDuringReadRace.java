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

@JCStressTest(Mode.Termination)
@Description("A reader blocked in read() must be unblocked when close() is invoked.")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "close() unblocked the reader")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "Reader stuck after close()")
@State
public class CloseDuringReadRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();

    @Actor
    public void reader() {
        try {
            is.read();
        } catch (IOException ignored) {
            // acceptable: close races may surface as IOException in some paths
        }
    }

    @Signal
    public void closer() throws IOException {
        sb.close();
    }
}
