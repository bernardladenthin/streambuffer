// SPDX-FileCopyrightText: 2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

/**
 * JPMS module descriptor for the streambuffer library.
 *
 * <p>The module exports the single public package {@code net.ladenthin.streambuffer}.
 * Only {@code java.base} is required at runtime; the Error Prone {@code @GuardedBy}
 * annotation has {@code RetentionPolicy.CLASS} so it is not visible at runtime and
 * does not need a {@code requires}. JSpecify and the Checker Framework qualifiers
 * are likewise compile-time only.</p>
 *
 * <p>This descriptor compiles at {@code --release 9}; the rest of the source compiles
 * at {@code --release 8} (see the {@code maven-compiler-plugin} configuration in
 * {@code pom.xml}). Java 8 runtimes silently ignore {@code module-info.class} at the
 * JAR root, so the resulting artifact is backward-compatible with Java 8 classpath
 * consumers while exposing a proper module descriptor to Java 9+ module-path consumers.</p>
 */
module net.ladenthin.streambuffer {
    exports net.ladenthin.streambuffer;
}
