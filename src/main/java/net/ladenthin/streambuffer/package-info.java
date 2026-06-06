// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

/**
 * Stream buffer that pipes bytes written to an {@link java.io.OutputStream}
 * back out through an {@link java.io.InputStream}.
 *
 * <p>JSpecify {@code @NullMarked} is declared at module level in
 * {@code module-info.java} and applies transitively to every package:
 * every parameter, return value, and field is non-null unless it carries
 * an explicit JSpecify nullable-marker annotation. NullAway and the
 * Checker Framework Nullness Checker both enforce this at compile time
 * via the configured Error Prone compiler plugin (see {@code pom.xml}).
 * The annotation lives only in {@code module-info.java} so that
 * {@code @NullMarked} is not referenced from any source compiled at
 * {@code --release 8}, which avoids the unsuppressible {@code unknown
 * enum constant ElementType.MODULE} classfile-read warning that javac
 * emits for any source at release 8 that resolves the JSpecify
 * {@code @NullMarked} annotation type. Production code currently
 * declares no nullable members of its own — every annotation appears in
 * the test sources only.
 */
package net.ladenthin.streambuffer;
