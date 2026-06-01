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
                    "org.jspecify.annotations..");

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
}
