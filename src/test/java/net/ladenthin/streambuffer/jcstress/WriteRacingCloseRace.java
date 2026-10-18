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
import org.openjdk.jcstress.annotations.Outcome;
import org.openjdk.jcstress.annotations.State;
import org.openjdk.jcstress.infra.results.II_Result;

/**
 * A write racing a close() from another thread, observed by a reader.
 *
 * <p>The write is either ordered before the close, so the reader gets its byte, or it fails with
 * "Stream closed". A write that returns normally while the reader has already reported the end of
 * the stream would lose that byte for the reader. The deterministic counterpart is
 * {@code StreamBufferTest.ConcurrentWriteAndCloseTests}.
 *
 * <p>{@code r1}: 1 when the write returned normally, 0 when it threw. {@code r2}: the reader's
 * {@code read()} result.
 */
@JCStressTest
@Description("A write racing close() is either delivered to the reader or fails; never both lost and successful.")
@Outcome(id = "1, 7", expect = Expect.ACCEPTABLE, desc = "write before close, reader got the byte")
@Outcome(id = "0, -1", expect = Expect.ACCEPTABLE, desc = "close before write, the write failed")
@Outcome(id = "1, -1", expect = Expect.FORBIDDEN, desc = "write succeeded but the reader already saw the end")
@State
public class WriteRacingCloseRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

    @Actor
    public void writer(II_Result r) {
        try {
            os.write(7);
            r.r1 = 1;
        } catch (IOException e) {
            r.r1 = 0;
        }
    }

    @Actor
    public void closer() {
        try {
            sb.close();
        } catch (IOException e) {
            throw new IllegalStateException("close failed", e);
        }
    }

    @Actor
    public void reader(II_Result r) {
        try {
            r.r2 = is.read();
        } catch (IOException e) {
            r.r2 = -2;
        }
    }
}
