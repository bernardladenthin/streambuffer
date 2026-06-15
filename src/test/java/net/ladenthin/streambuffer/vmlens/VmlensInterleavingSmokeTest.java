// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.vmlens;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.is;

import com.vmlens.api.AllInterleavings;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;

/**
 * Minimal vmlens interleaving-analysis smoke test demonstrating the setup.
 *
 * <p>Two threads each increment a shared {@link AtomicLong}; because
 * {@link AtomicLong#incrementAndGet()} is atomic, the final value must always be
 * {@code 2} regardless of how the two threads interleave. vmlens drives the body
 * of the {@link AllInterleavings} loop through every possible interleaving and
 * fails if any ordering violates the invariant.</p>
 *
 * <p>This test is meaningful only when executed under the vmlens java agent,
 * which is wired up by the {@code vmlens} Maven profile ({@code mvn -Pvmlens
 * test}). Without the agent {@link AllInterleavings#hasNext()} returns
 * {@code false} and the loop body is skipped, so the ordinary surefire run
 * excludes this class (see the {@code maven-surefire-plugin} {@code <excludes>}
 * in {@code pom.xml}). It is kept in sync with the sibling repos as a shared,
 * deterministic baseline for the vmlens setup; the real interleaving coverage for
 * this repo is the {@code StreamBuffer} reader/writer suite.</p>
 */
public class VmlensInterleavingSmokeTest {

    /**
     * Verifies that two concurrent atomic increments always sum to two under
     * every thread interleaving explored by vmlens.
     *
     * @throws InterruptedException if joining a worker thread is interrupted
     */
    @Test
    public void atomicIncrementsAreLinearizable() throws InterruptedException {
        try (AllInterleavings allInterleavings = new AllInterleavings("VmlensInterleavingSmokeTest.atomicIncrements")) {
            while (allInterleavings.hasNext()) {
                final AtomicLong counter = new AtomicLong();

                final Thread first = new Thread(counter::incrementAndGet);
                final Thread second = new Thread(counter::incrementAndGet);

                first.start();
                second.start();
                first.join();
                second.join();

                assertThat(counter.get(), is(2L));
            }
        }
    }
}
