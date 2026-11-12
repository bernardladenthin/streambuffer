// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.MatcherAssert.assertThat;

import java.io.Closeable;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * The instrumentation of roadmap A6 logs every access to shared state, with its value, in the
 * order of a run; a single thread gives a fixed list.
 */
class TraceRecorderTest {

    @Test
    void singleThreadedWriteReadCloseGivesTheExpectedEvents() throws Exception {
        final Class<?> c = new TracingClassLoader().loadClass("net.ladenthin.streambuffer.StreamBuffer");
        final Object sb = c.getConstructor().newInstance();
        final InputStream in = (InputStream) c.getMethod("getInputStream").invoke(sb);
        final OutputStream out = (OutputStream) c.getMethod("getOutputStream").invoke(sb);

        TraceRecorder.start(0, 0);
        out.write(new byte[] {7, 8});
        assertThat(in.read(), is(7));
        ((Closeable) sb).close();
        assertThat(in.read(), is(8));
        assertThat(in.read(), is(-1));
        final List<TraceRecorder.Event> events = TraceRecorder.stop();

        final List<String> got = new ArrayList<>();
        for (TraceRecorder.Event e : events) {
            got.add(e.site + "=" + e.value);
        }
        assertThat(
                String.join("\n", got),
                is(String.join(
                        "\n",
                        Arrays.asList(
                                // write(b): the count goes up under bufferLock; nobody waits, so no signal
                                "writeFromArray.enter#0=0",
                                "requireNonClosed.getClosed#0=0",
                                "writeFromArray.getAvail#0=0",
                                "writeFromArray.putAvail#0=2",
                                "writeFromArray.getAvail#2=2",
                                "shouldTrim.getAvail#0=2",
                                "writeFromArray.exit#0=0",
                                "signalModification.waitersGet#0=0",
                                // read(): the fast path of the wait, the re-check and the take under bufferLock
                                "waitForAtLeast.getAvail#0=2",
                                "readSingleByte.enter#0=0",
                                "readSingleByte.getAvail#0=2",
                                "readSingleByte.getAvail#1=2",
                                "readSingleByte.putAvail#0=1",
                                "readSingleByte.exit#0=0",
                                // close()
                                "closeAll.enter#0=0",
                                "closeAll.putClosed#0=1",
                                "closeAll.exit#0=0",
                                "signalModification.waitersGet#0=0",
                                // read() of the last byte, then -1: closed and empty
                                "waitForAtLeast.getAvail#0=1",
                                "readSingleByte.enter#0=0",
                                "readSingleByte.getAvail#0=1",
                                "readSingleByte.getAvail#1=1",
                                "readSingleByte.putAvail#0=0",
                                "readSingleByte.exit#0=0",
                                "waitForAtLeast.getAvail#0=0",
                                "waitForAtLeast.getClosed#0=1",
                                "waitForAtLeast.getAvail#1=0"))));
    }
}
