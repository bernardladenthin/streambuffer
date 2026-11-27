// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Proxy;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtensionContext;

/** The negative control of {@link UncaughtExceptionsExtension}: a dying thread fails the test. */
class UncaughtExceptionsExtensionTest {

    private static ExtensionContext context() {
        return (ExtensionContext) Proxy.newProxyInstance(
                ExtensionContext.class.getClassLoader(),
                new Class<?>[] {ExtensionContext.class},
                (proxy, method, args) -> {
                    if (method.getName().equals("getDisplayName")) {
                        return "the test";
                    }
                    throw new UnsupportedOperationException(method.getName());
                });
    }

    @Test
    void anErrorOfABackgroundThreadFailsTheTest() throws InterruptedException {
        final UncaughtExceptionsExtension extension = new UncaughtExceptionsExtension();
        final Thread t = new Thread(
                () -> {
                    throw new AssertionError("a contract of the writer");
                },
                "writer");
        t.start();
        t.join();
        final AssertionError failure = assertThrows(AssertionError.class, () -> extension.afterEach(context()));
        assertTrue(failure.getMessage().contains("the test"), failure.getMessage());
        assertTrue(failure.getCause().getMessage().contains("uncaught in thread writer"));
        assertEquals("a contract of the writer", failure.getCause().getCause().getMessage());
        // collected once: the next test is not failed by it
        assertDoesNotThrow(() -> extension.afterEach(context()));
    }

    @Test
    void aTestWithoutADyingThreadPasses() {
        assertDoesNotThrow(() -> new UncaughtExceptionsExtension().afterEach(context()));
    }
}
