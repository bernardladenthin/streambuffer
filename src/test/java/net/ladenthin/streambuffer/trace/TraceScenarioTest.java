// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.junit.jupiter.api.Test;

/** The renumbering of the bytes of a trace in commit order (roadmap A6, several writers). */
class TraceScenarioTest {

    private static TraceRecorder.Event commit(String writer) {
        return new TraceRecorder.Event(writer, TraceScenario.COMMIT, 0, Collections.emptyList());
    }

    private static TraceRecorder.Event wret(String writer, long mine) {
        return new TraceRecorder.Event(writer, "wret", mine, Collections.emptyList());
    }

    private static TraceRecorder.Event ret(String reader, Integer... bytes) {
        return new TraceRecorder.Event(reader, "ret", bytes.length, Arrays.asList(bytes));
    }

    private static List<String> lines(List<TraceRecorder.Event> events) {
        final List<String> r = new ArrayList<>();
        for (TraceRecorder.Event e : events) {
            r.add(e.toString());
        }
        return r;
    }

    @Test
    void oneWriterChangesNothing() {
        final List<List<byte[]>> plan = Collections.singletonList(Arrays.asList(new byte[] {1, 2}, new byte[] {3}));
        final List<TraceRecorder.Event> events =
                Arrays.asList(commit("w"), wret("w", 2), ret("r1", 1), commit("w"), ret("r1", 2, 3), wret("w", 3));

        assertThat(lines(TraceScenario.renumber(events, plan)), is(lines(events)));
    }

    @Test
    void severalWritersAreNumberedInCommitOrder() {
        // w1 plans the bytes 1, 2, w2 the byte 3; w2 commits first, so its byte is the model's 1
        final List<List<byte[]>> plan =
                Arrays.asList(Collections.singletonList(new byte[] {1, 2}), Collections.singletonList(new byte[] {3}));
        final List<TraceRecorder.Event> events =
                Arrays.asList(commit("w2"), commit("w1"), wret("w2", 1), ret("r1", 3), ret("r2", 1, 2), wret("w1", 2));

        assertThat(
                lines(TraceScenario.renumber(events, plan)),
                is(lines(Arrays.asList(
                        commit("w2"), commit("w1"), wret("w2", 1), ret("r1", 1), ret("r2", 2, 3), wret("w1", 3)))));
    }

    @Test
    void aByteReadBeforeItsCommitIsAnError() {
        final List<List<byte[]>> plan = Collections.singletonList(Collections.singletonList(new byte[] {1}));

        assertThrows(
                IllegalStateException.class,
                () -> TraceScenario.renumber(Arrays.asList(ret("r1", 1), commit("w")), plan));
    }

    @Test
    void moreCommitsThanWritesIsAnError() {
        final List<List<byte[]>> plan = Collections.singletonList(Collections.singletonList(new byte[] {1}));

        assertThrows(
                IllegalStateException.class,
                () -> TraceScenario.renumber(Arrays.asList(commit("w"), commit("w")), plan));
    }

    @Test
    void severalWritesNeedFullChunks() {
        assertThrows(IllegalArgumentException.class, () -> new TraceScenario("x", 5, 2, 1, 1, 0, 0, 2, 1));
    }
}
