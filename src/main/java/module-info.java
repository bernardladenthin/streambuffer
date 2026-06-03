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
 * <p>JSpecify {@code @NullMarked} is declared at the module level here (rather than
 * on {@code package-info.java}) for two reasons: (1) it applies transitively to every
 * package in the module, removing the need to repeat the annotation per package; and
 * (2) at {@code --release 8} javac emits an unsuppressible {@code unknown enum
 * constant ElementType.MODULE} classfile-read warning for any source file that
 * resolves the JSpecify {@code @NullMarked} annotation type ({@code @NullMarked}
 * carries {@code @Target({MODULE, PACKAGE, TYPE})} and Java 8 does not know about
 * {@code ElementType.MODULE}). Confining the reference to {@code module-info.java}
 * — which compiles at {@code --release 9} in the dedicated execution — keeps that
 * warning out of the build entirely.</p>
 *
 * <p>This descriptor compiles at {@code --release 9}; the rest of the source compiles
 * at {@code --release 8} (see the {@code maven-compiler-plugin} configuration in
 * {@code pom.xml}). Java 8 runtimes silently ignore {@code module-info.class} at the
 * JAR root, so the resulting artifact is backward-compatible with Java 8 classpath
 * consumers while exposing a proper module descriptor to Java 9+ module-path consumers.</p>
 */
@org.jspecify.annotations.NullMarked
module net.ladenthin.streambuffer {
    // requires static — JSpecify @NullMarked is @Retention(CLASS) so the
    // org.jspecify module is only needed at compile time; module-path
    // consumers do not need to put jspecify on their runtime path.
    requires static org.jspecify;

    exports net.ladenthin.streambuffer;
}
