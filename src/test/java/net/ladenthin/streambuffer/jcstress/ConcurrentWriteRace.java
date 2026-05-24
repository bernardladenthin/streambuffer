// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jcstress;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import net.ladenthin.streambuffer.StreamBuffer;
import org.openjdk.jcstress.annotations.Actor;
import org.openjdk.jcstress.annotations.Arbiter;
import org.openjdk.jcstress.annotations.Description;
import org.openjdk.jcstress.annotations.Expect;
import org.openjdk.jcstress.annotations.JCStressTest;
import org.openjdk.jcstress.annotations.Outcome;
import org.openjdk.jcstress.annotations.State;
import org.openjdk.jcstress.infra.results.Z_Result;

@JCStressTest
@Description("Two concurrent writers must each appear contiguously in the FIFO; bytes must not interleave.")
@Outcome(id = "true", expect = Expect.ACCEPTABLE, desc = "Both payloads intact in some order")
@Outcome(id = "false", expect = Expect.FORBIDDEN, desc = "Torn / interleaved write")
@State
public class ConcurrentWriteRace {

    private static final byte[] A = new byte[] {1, 2};
    private static final byte[] B = new byte[] {3, 4};

    private final StreamBuffer sb = new StreamBuffer();
    private final OutputStream os = sb.getOutputStream();
    private final InputStream is = sb.getInputStream();

    @Actor
    public void writerA() {
        try {
            os.write(A);
        } catch (IOException ignored) {
        }
    }

    @Actor
    public void writerB() {
        try {
            os.write(B);
        } catch (IOException ignored) {
        }
    }

    @Arbiter
    public void check(Z_Result r) {
        try {
            int available = is.available();
            byte[] all = new byte[available];
            int n = (available == 0) ? 0 : is.read(all, 0, available);
            byte[] got = Arrays.copyOf(all, Math.max(n, 0));
            r.r1 = Arrays.equals(got, new byte[] {1, 2, 3, 4}) || Arrays.equals(got, new byte[] {3, 4, 1, 2});
        } catch (IOException e) {
            r.r1 = false;
        }
    }
}
