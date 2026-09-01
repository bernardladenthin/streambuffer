// SPDX-FileCopyrightText: 2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Post-{@code package} smoke for the PACKAGED jar, run by {@code .github/smoke-jar.sh} via the JDK
 * single-file source launcher ({@code java -cp <jar> StreamBufferSmoke.java}) — no Maven, no test
 * framework.
 *
 * <p>Why this exists: every other check in the pipeline (unit tests, jqwik, Lincheck, PIT, SpotBugs)
 * runs off {@code target/classes}. Nothing ever loads the assembled jar, yet the assembled jar is
 * what is attached to the GitHub release and deployed to Central. This is the streambuffer member of
 * the cross-repo "no release asset is attached that CI has not run" convention
 * (workspace/policies/fat-jar-release-assets.md). streambuffer ships no fat jar — it is a library
 * with no {@code Main-Class} — so the packaged artifact cannot be launched with {@code java -jar};
 * the equivalent real use is a consumer putting the jar on its classpath and calling the API, which
 * is exactly what this file does.</p>
 *
 * <p>Deliberately tiny (~1 s, no network): it catches the failure class a green Maven build cannot
 * see — a jar that is missing classes, carries a broken {@code module-info.class}, or was assembled
 * from the wrong {@code target/} — not the library's behaviour, which the real suite covers.</p>
 */
public final class StreamBufferSmoke {

    /** Payload written through the buffer; the tail byte is non-ASCII on purpose. */
    private static final byte[] PAYLOAD = {0x73, 0x62, 0x2D, 0x73, 0x6D, 0x6F, 0x6B, 0x65, (byte) 0xFF};

    private StreamBufferSmoke() {}

    public static void main(String[] args) throws Exception {
        try (StreamBuffer buffer = new StreamBuffer()) {
            final OutputStream out = buffer.getOutputStream();
            final InputStream in = buffer.getInputStream();

            out.write(PAYLOAD);
            out.flush();

            if (in.available() != PAYLOAD.length) {
                throw new IllegalStateException(
                        "available() reported " + in.available() + " bytes, expected " + PAYLOAD.length);
            }

            final byte[] read = new byte[PAYLOAD.length];
            int off = 0;
            while (off < read.length) {
                final int n = in.read(read, off, read.length - off);
                if (n < 0) {
                    throw new IllegalStateException("stream ended after " + off + " of " + read.length + " bytes");
                }
                off += n;
            }
            if (!Arrays.equals(PAYLOAD, read)) {
                throw new IllegalStateException(
                        "round-trip mismatch: wrote " + Arrays.toString(PAYLOAD) + ", read " + Arrays.toString(read));
            }

            out.close();
            if (in.read() != -1) {
                throw new IllegalStateException("stream did not report EOF after the writer closed");
            }
        }
        System.out.println("packaged-jar smoke OK: " + PAYLOAD.length + " bytes round-tripped");
    }
}
