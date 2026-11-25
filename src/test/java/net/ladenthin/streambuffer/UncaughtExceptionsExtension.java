// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.junit.jupiter.api.extension.AfterEachCallback;
import org.junit.jupiter.api.extension.ExtensionContext;

/**
 * Fails a test when a thread it started ended with an uncaught throwable. Registered for every
 * Jupiter test through {@code META-INF/services} and {@code junit-platform.properties}.
 *
 * <p>Without it, a background thread that dies on an exception or an error ends silently: the
 * test thread's assertions may still pass on what the thread did before. That matters most under
 * {@code -Pjml-rac}: a contract violation throws {@code JmlAssertionError}, an {@code Error} the
 * background threads' {@code catch (IOException e)} does not catch, so a broken postcondition of
 * {@code writeFromArray} or {@code close} on a writer or closer thread passed unnoticed (the vacuity
 * audit of 2026-11-25). The default handler collects the throwable, still prints it as the JVM's
 * would, and the test fails after it ran. A throwable of a thread that outlives its test fails the
 * next test that ends.
 */
public final class UncaughtExceptionsExtension implements AfterEachCallback {

    private static final Queue<Throwable> UNCAUGHT = new ConcurrentLinkedQueue<>();

    static {
        final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, e) -> {
            UNCAUGHT.add(new AssertionError("uncaught in thread " + thread.getName() + ": " + e, e));
            if (previous != null) {
                previous.uncaughtException(thread, e);
            } else {
                System.err.print("Exception in thread \"" + thread.getName() + "\" ");
                e.printStackTrace();
            }
        });
    }

    @Override
    public void afterEach(ExtensionContext context) {
        final Throwable first = UNCAUGHT.poll();
        if (first == null) {
            return;
        }
        final AssertionError failure = new AssertionError(
                "a thread of " + context.getDisplayName()
                        + " (or of a test before it) ended with an uncaught throwable",
                first);
        for (Throwable more = UNCAUGHT.poll(); more != null; more = UNCAUGHT.poll()) {
            failure.addSuppressed(more);
        }
        throw failure;
    }
}
