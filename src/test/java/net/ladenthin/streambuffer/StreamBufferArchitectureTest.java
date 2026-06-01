// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.fields;

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
}
