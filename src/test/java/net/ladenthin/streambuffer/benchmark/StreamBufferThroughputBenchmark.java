// @formatter:off
/**
 * Copyright 2014 Bernard Ladenthin bernard.ladenthin@gmail.com
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */
// @formatter:on
package net.ladenthin.streambuffer.benchmark;

import net.ladenthin.streambuffer.StreamBuffer;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.TearDown;
import org.openjdk.jmh.annotations.Warmup;
import org.openjdk.jmh.infra.Blackhole;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.TimeUnit;

/**
 * Throughput benchmark for {@link StreamBuffer}.
 *
 * <p>Replaces the removed {@code testMemory()} test (Wolfgang Fahl, 2017) with a
 * deterministic JMH measurement. Instead of asserting a GC-dependent memory
 * threshold, this benchmark reports ops/sec and — when run with {@code -prof gc}
 * — {@code gc.alloc.rate}, making memory pressure observable without being flaky.</p>
 *
 * <p>Run locally:</p>
 * <pre>
 * mvn test-compile exec:java \
 *   -Dexec.mainClass=org.openjdk.jmh.Main \
 *   -Dexec.classpathScope=test \
 *   -Dexec.args="StreamBufferThroughputBenchmark -prof gc"
 * </pre>
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Thread)
@Warmup(iterations = 3, time = 1)
@Measurement(iterations = 5, time = 2)
@Fork(1)
public class StreamBufferThroughputBenchmark {

    /** Block sizes: 128 B (small), 4 KB (typical), 40 KB (Wolfgang's original size: 10 * 2^12 bytes). */
    @Param({"128", "4096", "40960"})
    public int blockSize;

    /** Whether {@link StreamBuffer#setSafeWrite(boolean)} is enabled (clones arrays on write). */
    @Param({"false", "true"})
    public boolean safeWrite;

    private StreamBuffer sb;
    private OutputStream os;
    private InputStream is;
    private byte[] writeBlock;
    private byte[] readBlock;

    @Setup(Level.Invocation)
    public void setUp() throws IOException {
        sb = new StreamBuffer();
        sb.setSafeWrite(safeWrite);
        os = sb.getOutputStream();
        is = sb.getInputStream();
        writeBlock = new byte[blockSize];
        readBlock = new byte[blockSize];
        for (int i = 0; i < blockSize; i++) {
            writeBlock[i] = (byte) (i & 0xFF);
        }
    }

    @TearDown(Level.Invocation)
    public void tearDown() throws IOException {
        sb.close();
    }

    /**
     * Write one block then read it back in a loop.
     *
     * <p>Measures round-trip throughput. With {@code -prof gc} reveals allocation
     * rate and GC pressure — the non-flaky replacement for Wolfgang's 64&nbsp;MB
     * memory assertion.</p>
     */
    @Benchmark
    public void writeReadRoundTrip(Blackhole bh) throws IOException {
        os.write(writeBlock);
        int totalRead = 0;
        while (totalRead < blockSize) {
            int n = is.read(readBlock, totalRead, blockSize - totalRead);
            if (n < 0) {
                break;
            }
            totalRead += n;
        }
        bh.consume(totalRead);
    }

    /**
     * Write one block without reading.
     *
     * <p>Measures raw write-path throughput. With {@code -prof gc} shows whether
     * {@code trim()} consolidation causes unexpected allocation spikes as the
     * internal deque grows.</p>
     */
    @Benchmark
    public void writeOnly(Blackhole bh) throws IOException {
        os.write(writeBlock);
        bh.consume(sb.getBufferElementCount());
    }
}
