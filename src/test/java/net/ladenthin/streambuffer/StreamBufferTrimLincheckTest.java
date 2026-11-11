// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

/**
 * {@link StreamBufferLincheckTest} with {@code maxBufferElements} 2: the third buffered entry makes
 * a write trim, so the model checker also schedules the other threads' operations around a trim
 * that consolidates the FIFO under the lock (TODO roadmap A3).
 */
public class StreamBufferTrimLincheckTest extends StreamBufferLincheckTest {

    public StreamBufferTrimLincheckTest() {
        sb.setMaxBufferElements(2);
    }
}
