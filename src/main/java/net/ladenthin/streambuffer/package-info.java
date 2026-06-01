// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

/**
 * Stream buffer that pipes bytes written to an {@link java.io.OutputStream}
 * back out through an {@link java.io.InputStream}.
 *
 * <p>The package is JSpecify {@code @NullMarked}: every parameter, return
 * value, and field is non-null unless explicitly annotated {@code @Nullable}.
 * NullAway enforces this at compile time via the configured Error Prone
 * compiler plugin (see {@code pom.xml}).
 */
@NullMarked
package net.ladenthin.streambuffer;

import org.jspecify.annotations.NullMarked;
