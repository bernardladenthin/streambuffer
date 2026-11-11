// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.Semaphore;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Java PathFinder harness for trim re-entrancy: with {@code maxBufferElements} 1 the writer's second
 * write trims, and the trim start signal writes a third byte from inside the trim, on the writer
 * thread, which already holds the buffer lock (the lock is re-entrant; {@code isTrimRunning} keeps
 * that write from starting a nested trim). A reader reads concurrently until the end of the
 * stream. Not a JUnit test; compiled with {@code javac --release 8} and run under JPF, see
 * {@code src/test/jpf/README.md}.
 *
 * <p>Over every interleaving: no deadlock, no uncaught exception, and the reader gets {@code 1, 2, 9}
 * in that order if the trim ran (the signal's write lands after the write that triggered it, before
 * the close), or {@code 1, 2} if the reader took the first byte before the second write, which then
 * found a single entry and did not trim. The byte 9 arrives exactly when the signal fired.
 *
 * <p>Named static classes instead of lambdas and an anonymous class: with the anonymous
 * {@code Semaphore} subclass next to lambdas, jpf-core's {@code Thread.start} peer failed to find
 * the thread's {@code run()} (NullPointerException in {@code JPF_java_lang_Thread.start}).
 */
public final class JpfTrimReentrancyHarness {

    private JpfTrimReentrancyHarness() {}

    /** A trim start signal that writes one byte the first time it is released. */
    static final class WritingSignal extends Semaphore {
        private static final long serialVersionUID = 1L;

        private final OutputStream os;
        boolean signalled;

        WritingSignal(final OutputStream os) {
            super(0);
            this.os = os;
        }

        @Override
        public void release() {
            if (!signalled) {
                signalled = true;
                try {
                    os.write(9); // re-entrant: this thread holds the buffer lock
                } catch (IOException e) {
                    throw new AssertionError("the write from the trim signal must not fail", e);
                }
            }
            super.release();
        }
    }

    static final class Writer implements Runnable {
        private final StreamBuffer sb;

        Writer(final StreamBuffer sb) {
            this.sb = sb;
        }

        @Override
        public void run() {
            try {
                sb.getOutputStream().write(1);
                sb.getOutputStream().write(2); // two entries > maxBufferElements: trims, the signal writes 9
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("writer must not fail", e);
            }
        }
    }

    static final class Reader implements Runnable {
        private final InputStream is;
        final int[] got = new int[4];
        int count;

        Reader(final InputStream is) {
            this.is = is;
        }

        @Override
        public void run() {
            try {
                int c;
                while ((c = is.read()) != -1) {
                    if (count < got.length) {
                        got[count] = c;
                    }
                    count++;
                }
            } catch (IOException e) {
                throw new AssertionError("reader must not fail", e);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        final WritingSignal signal = new WritingSignal(sb.getOutputStream());
        sb.addTrimStartSignal(signal);

        final Reader reader = new Reader(sb.getInputStream());
        final Thread writerThread = new Thread(new Writer(sb));
        final Thread readerThread = new Thread(reader);
        writerThread.start();
        readerThread.start();
        writerThread.join();
        readerThread.join();

        // Explicit throws, not `assert` (see JpfStreamBufferHarness).
        final int expected = signal.signalled ? 3 : 2;
        if (reader.count != expected
                || reader.got[0] != 1
                || reader.got[1] != 2
                || (expected == 3 && reader.got[2] != 9)) {
            throw new AssertionError("reader got " + reader.count + " bytes: " + reader.got[0] + ", " + reader.got[1]
                    + ", " + reader.got[2] + "; expected 1, 2" + (expected == 3 ? ", 9 (the trim ran)" : " (no trim)"));
        }
    }
}
