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

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

@JCStressTest(Mode.Termination)
@Description("A reader blocked in read() must be unblocked when a writer publishes a byte.")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "write() unblocked the reader")
@Outcome(id = "STALE",      expect = Expect.FORBIDDEN,  desc = "Reader stuck after write()")
@State
public class WriteUnblocksReadRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

    @Actor
    public void reader() {
        try {
            is.read();
        } catch (IOException ignored) {
            // not expected on this path, but tolerated
        }
    }

    @Signal
    public void writer() throws IOException {
        os.write(0x42);
    }
}
