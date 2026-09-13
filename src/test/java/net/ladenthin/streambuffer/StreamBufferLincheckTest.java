// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import org.jetbrains.kotlinx.lincheck.LinChecker;
import org.jetbrains.lincheck.datastructures.ModelCheckingOptions;
import org.jetbrains.lincheck.datastructures.Operation;
import org.junit.jupiter.api.Test;

/**
 * Linearizability check for the non-blocking subset of the StreamBuffer API:
 * write, close, available. read() is blocking and therefore excluded - Lincheck's
 * model checker enumerates thread schedules and cannot make progress over a
 * thread parked in read().
 *
 * <p>The blocking paths are covered instead by the jcstress {@code Mode.Termination}
 * tests in the {@code jcstress} package (run under {@code -Pjcstress}), which is the
 * purpose-built tool for "a parked thread must always be released": every blocking
 * entry point is paired with both wakeup sources -
 * {@code WriteUnblocksReadRace}/{@code CloseDuringReadRace} for {@code read()},
 * {@code WriteUnblocksArrayReadRace}/{@code CloseUnblocksArrayReadRace} for the second
 * wait phase of {@code read(byte[],off,len)}, and
 * {@code WriteUnblocksWaitForAtLeastRace}/{@code CloseUnblocksWaitForAtLeastRace} for the
 * public {@code waitForAtLeast}/{@code waitForAnyData} API.
 */
public class StreamBufferLincheckTest {

    private final StreamBuffer sb = new StreamBuffer();
    private final OutputStream os = sb.getOutputStream();
    private final InputStream is = sb.getInputStream();

    @Operation
    public void writeByte(int b) throws IOException {
        os.write(b);
    }

    @Operation
    public int available() throws IOException {
        return is.available();
    }

    @Operation
    public boolean isClosed() {
        return sb.isClosed();
    }

    @Operation
    public void closeBuffer() throws IOException {
        sb.close();
    }

    @Test
    public void modelCheckingTest() {
        ModelCheckingOptions options = new ModelCheckingOptions()
                .iterations(20)
                .invocationsPerIteration(500)
                .threads(2)
                .actorsPerThread(3);
        LinChecker.check(StreamBufferLincheckTest.class, options);
    }
}
