// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.fields;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import java.util.Random;

@AnalyzeClasses(packages = "net.ladenthin.streambuffer", importOptions = ImportOption.DoNotIncludeTests.class)
public class StreamBufferArchitectureTest {

    /**
     * Main code is a leaf: it must depend only on the JDK and the
     * Error Prone annotation used to mark lock invariants. Adding a
     * runtime dependency would change the published artifact's
     * dependency graph and is a deliberate decision; this rule makes
     * such a change visible as a test failure.
     */
    @ArchTest
    static final ArchRule mainCodeStaysLeaf = classes()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .onlyDependOnClassesThat()
            .resideInAnyPackage(
                    "net.ladenthin.streambuffer..",
                    "java..",
                    "com.google.errorprone.annotations..",
                    "org.jspecify.annotations..",
                    "org.checkerframework..");

    /**
     * The internal buffer Deque is an implementation detail; no static
     * field of that type should escape the class boundary.
     */
    @ArchTest
    static final ArchRule dequeFieldsArePrivate =
            fields().that().haveRawType(java.util.Deque.class).should().bePrivate();

    /**
     * Production code must not use {@code java.util.logging} directly; logging
     * is delegated to SLF4J. The rule currently has no violations because the
     * production code has no logging at all (the module is library code with
     * no built-in tracing); this acts as a regression guard.
     */
    @ArchTest
    static final ArchRule noJavaUtilLogging = noClasses()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .dependOnClassesThat()
            .resideInAPackage("java.util.logging..");

    /**
     * Production code must not import unsupported / internal JDK packages.
     * These are not part of the Java SE API and may change or disappear without notice.
     */
    @ArchTest
    static final ArchRule noInternalJdkImports = noClasses()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .dependOnClassesThat()
            .resideInAnyPackage("sun..", "com.sun..", "jdk.internal..");

    /**
     * Public mutable state forbidden: any non-static field declared
     * {@code public} must also be {@code final}. Static finals are constants
     * and are allowed; instance fields exposed publicly without {@code final}
     * are an encapsulation leak and should use accessors instead.
     */
    @ArchTest
    static final ArchRule noPublicMutableFields = fields()
            .that()
            .arePublic()
            .and()
            .areNotStatic()
            .should()
            .beFinal()
            .allowEmptyShould(true); // regression guard; passes vacuously today

    /**
     * Production code must not call {@link System#exit(int)}; throw or return non-zero from main instead.
     */
    @ArchTest
    static final ArchRule noSystemExit = noClasses()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .callMethod(System.class, "exit", int.class)
            .allowEmptyShould(true);

    /**
     * Production code must not construct {@link java.util.Random}; {@code Random} is a non-cryptographic
     * PRNG (CWE-338). Use {@link java.security.SecureRandom} or {@link java.util.concurrent.ThreadLocalRandom}
     * depending on whether cryptographic strength or thread-local fast jitter is needed.
     */
    @ArchTest
    static final ArchRule noNewRandom = noClasses()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .callConstructor(Random.class)
            .orShould()
            .callConstructor(Random.class, long.class)
            .allowEmptyShould(true);

    /**
     * Production code must not call {@link Thread#sleep(long)} / {@link Thread#sleep(long, int)};
     * prefer {@link java.util.concurrent.BlockingQueue#poll(long, java.util.concurrent.TimeUnit)} or
     * {@link java.util.concurrent.locks.Condition#await(long, java.util.concurrent.TimeUnit)} which
     * compose with cancellation and produce intent-clear stack traces.
     */
    @ArchTest
    static final ArchRule noThreadSleep = noClasses()
            .that()
            .resideInAPackage("net.ladenthin.streambuffer..")
            .should()
            .callMethod(Thread.class, "sleep", long.class)
            .orShould()
            .callMethod(Thread.class, "sleep", long.class, int.class)
            .allowEmptyShould(true);
}
