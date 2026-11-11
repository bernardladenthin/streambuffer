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
 * Two readers blocked in {@code read()} must both be released by two single-byte writes (bug-hunt
 * finding F278: two writes before the first wake-up left one permit for two waiting readers, so
 * one stayed blocked although a byte was buffered).
 *
 * <p>As in {@link TwoReadersCloseRace}, the one actor starts the second reader and joins it.
 */
@JCStressTest(Mode.Termination)
@Description("Two readers blocked in read() must both be unblocked by two single-byte writes.")
@Outcome(id = "TERMINATED", expect = Expect.ACCEPTABLE, desc = "two writes unblocked both readers")
@Outcome(id = "STALE", expect = Expect.FORBIDDEN, desc = "A reader stuck with a byte buffered")
@State
public class TwoReadersTwoWritesRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

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
    public void writer() throws IOException {
        os.write(1);
        os.write(2);
    }
}
