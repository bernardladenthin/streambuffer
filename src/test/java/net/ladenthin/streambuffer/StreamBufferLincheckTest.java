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
 * Linearizability check of the StreamBuffer API: write, close, available, and reads.
 *
 * <p>Lincheck's model checker enumerates thread schedules and cannot make progress over a thread
 * parked in a blocking read, so the reads only read what is buffered: {@code readIfAvailable}
 * reads one byte and {@code readPairIfAvailable} a 2-byte {@code read(b, 0, 2)}, each only when
 * {@code available()} reports enough, and both sit in one {@code nonParallelGroup}: only one read
 * runs at a time, so no other reader can take the bytes between the check and the read, and the
 * read never blocks. Writes and the close still run in parallel with them. The parallel readers
 * themselves (a reader that loses the race and waits) are covered by
 * {@code StreamBufferConcurrentReadersTest}, the vmlens and jcstress suites and the JPF harnesses.
 *
 * <p>The blocking paths are covered by the jcstress {@code Mode.Termination} tests in the
 * {@code jcstress} package (run under {@code -Pjcstress}): every blocking entry point is paired with
 * both wakeup sources — {@code WriteUnblocksReadRace}/{@code CloseDuringReadRace} for
 * {@code read()}, {@code WriteUnblocksArrayReadRace}/{@code CloseUnblocksArrayReadRace} for
 * {@code read(byte[],off,len)} waiting for the rest of its bytes,
 * {@code WriteUnblocksWaitForAtLeastRace}/{@code CloseUnblocksWaitForAtLeastRace} for
 * {@code waitForAtLeast}/{@code waitForAnyData}, and {@code TwoReadersTwoWritesRace}/
 * {@code TwoReadersCloseRace} for two readers.
 *
 * <p>{@link StreamBufferTrimLincheckTest} runs the same operations with a small
 * {@code maxBufferElements}, so writes trim.
 */
public class StreamBufferLincheckTest {

    /** The buffer under test; subclasses configure it in their constructor. */
    protected final StreamBuffer sb = new StreamBuffer();

    private final OutputStream os = sb.getOutputStream();
    private final InputStream is = sb.getInputStream();

    @Operation
    public void writeByte(int b) throws IOException {
        os.write(b);
    }

    @Operation
    public void writePair(int b) throws IOException {
        os.write(new byte[] {(byte) b, (byte) (b + 1)});
    }

    @Operation
    public int available() throws IOException {
        return is.available();
    }

    @Operation(nonParallelGroup = "consumer")
    public int readIfAvailable() throws IOException {
        return is.available() > 0 ? is.read() : -2;
    }

    @Operation(nonParallelGroup = "consumer")
    public int readPairIfAvailable() throws IOException {
        if (is.available() < 2) {
            return -2;
        }
        final byte[] pair = new byte[2];
        final int n = is.read(pair, 0, 2);
        return n == 2 ? (pair[0] & 0xff) * 256 + (pair[1] & 0xff) : -3;
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
        LinChecker.check(getClass(), options);
    }
}
