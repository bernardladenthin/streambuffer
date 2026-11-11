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
 * Fixed-size records with two competing readers: the writer writes the 2-byte records {@code {1, 2}}
 * and {@code {3, 4}} fragmented across the record boundary ({@code [1]}, then {@code [2, 3, 4]}),
 * two readers each call {@code read(b, 0, 2)}. Each must get a whole record (reported as
 * {@code 10 * b[0] + b[1]}). Before {@code read(b, off, len)} took its bytes in one step, a reader
 * took the first byte, released the lock and waited for the rest, so {@code 13, 24} or
 * {@code 14, 23} were possible. Every actor terminates in every interleaving: four bytes are
 * written, two readers take two each.
 */
@JCStressTest
@Description("Two readers of 2-byte records each get a whole record, also when the records are written fragmented.")
@Outcome(id = "12, 34", expect = Expect.ACCEPTABLE, desc = "reader 1 got the first record")
@Outcome(id = "34, 12", expect = Expect.ACCEPTABLE, desc = "reader 2 got the first record")
@Outcome(expect = Expect.FORBIDDEN, desc = "a torn record")
@State
public class RecordReadersRace {

    private final StreamBuffer sb = new StreamBuffer();
    private final InputStream is = sb.getInputStream();
    private final OutputStream os = sb.getOutputStream();

    @Actor
    public void writer() {
        try {
            os.write(new byte[] {1});
            os.write(new byte[] {2, 3, 4});
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    @Actor
    public void reader1(final II_Result r) {
        r.r1 = readRecord();
    }

    @Actor
    public void reader2(final II_Result r) {
        r.r2 = readRecord();
    }

    private int readRecord() {
        final byte[] record = new byte[2];
        try {
            final int n = is.read(record, 0, 2);
            return n == 2 ? 10 * record[0] + record[1] : -n;
        } catch (IOException e) {
            return -100;
        }
    }
}
