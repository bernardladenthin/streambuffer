// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.verification;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasItem;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/**
 * Roadmap A16: every verification claim of the READMEs names its row of {@code
 * VERIFICATION-ASSUMPTIONS.md} as {@code [V<n>]}, and every row is named somewhere, so a new
 * result without a row, or a row nothing refers to, fails here.
 */
class VerificationAssumptionsTest {

    static final Path TABLE = Path.of("VERIFICATION-ASSUMPTIONS.md");
    static final List<Path> READMES =
            List.of(Path.of("README.md"), Path.of("src/test/tla/README.md"), Path.of("src/test/jpf/README.md"));

    private static final Pattern ROW = Pattern.compile("(?m)^\\| (V\\d+) \\|");
    private static final Pattern REF = Pattern.compile("\\[(V\\d+)\\]");

    @Test
    void everyClaimNamesARowAndEveryRowIsNamed() throws IOException {
        assertThat(differences(rows(read(TABLE)), references(readmes())), empty());
    }

    @Test
    void theRowsAreNumberedOneByOne() throws IOException {
        final List<String> ids = rows(read(TABLE));
        final List<String> expected = new ArrayList<>();
        for (int i = 1; i <= ids.size(); i++) {
            expected.add("V" + i);
        }
        assertThat(ids, contains(expected.toArray(new String[0])));
    }

    @Test
    void aClaimNamingAnUnknownRowIsReported() throws IOException {
        final Map<String, String> texts = readmes();
        texts.put("extra.md", "a claim [V99]");
        assertThat(
                differences(rows(read(TABLE)), references(texts)),
                hasItem("extra.md names V99, which is no row of " + TABLE));
    }

    @Test
    void aRowNamedNowhereIsReported() throws IOException {
        final List<String> ids = new ArrayList<>(rows(read(TABLE)));
        ids.add("V99");
        assertThat(differences(ids, references(readmes())), hasItem("V99 is named in no README"));
    }

    /** The ids of the table's rows, in order. */
    static List<String> rows(final String table) {
        final List<String> ids = new ArrayList<>();
        final Matcher m = ROW.matcher(table);
        while (m.find()) {
            ids.add(m.group(1));
        }
        return ids;
    }

    /** For each README, the ids it names. */
    static Map<String, Set<String>> references(final Map<String, String> texts) {
        final Map<String, Set<String>> refs = new LinkedHashMap<>();
        for (final Map.Entry<String, String> e : texts.entrySet()) {
            final Set<String> ids = new TreeSet<>();
            final Matcher m = REF.matcher(e.getValue());
            while (m.find()) {
                ids.add(m.group(1));
            }
            refs.put(e.getKey(), ids);
        }
        return refs;
    }

    static List<String> differences(final List<String> rows, final Map<String, Set<String>> refs) {
        final List<String> out = new ArrayList<>();
        final Set<String> named = new TreeSet<>();
        for (final Map.Entry<String, Set<String>> e : refs.entrySet()) {
            for (final String id : e.getValue()) {
                named.add(id);
                if (!rows.contains(id)) {
                    out.add(e.getKey() + " names " + id + ", which is no row of " + TABLE);
                }
            }
        }
        for (final String id : rows) {
            if (!named.contains(id)) {
                out.add(id + " is named in no README");
            }
        }
        return out;
    }

    private static Map<String, String> readmes() throws IOException {
        final Map<String, String> texts = new LinkedHashMap<>();
        for (final Path p : READMES) {
            texts.put(p.toString().replace('\\', '/'), read(p));
        }
        return texts;
    }

    private static String read(final Path p) throws IOException {
        return Files.readString(p, StandardCharsets.UTF_8);
    }
}
