// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Roadmap A18: reads the traces the JPF harness {@code JpfTraceHarness} printed for every path it
 * explored, and writes each distinct one as an A6 trace module ({@link TraceGenerator#write}), so
 * that {@code trace.sh} checks them against the model.
 */
public final class JpfTraceImport {

    private JpfTraceImport() {}

    /**
     * Imports the traces.
     *
     * @param args the JPF output, the scenario's name, bytes, chunk length, read length, the numbers of
     *     {@code read()} readers, record readers and {@code waitForAtLeast} callers (as the harness got
     *     them), and the output directory
     * @throws IOException if a file cannot be read or written
     */
    public static void main(String[] args) throws IOException {
        final Path jpfOut = Paths.get(args[0]);
        final TraceScenario s = new TraceScenario(
                args[1],
                Integer.parseInt(args[2]),
                Integer.parseInt(args[3]),
                Integer.parseInt(args[4]),
                Integer.parseInt(args[5]),
                Integer.parseInt(args[6]),
                Integer.parseInt(args[7]));
        final Path dir = Paths.get(args[8]);
        Files.createDirectories(dir);
        final Set<List<String>> distinct = new LinkedHashSet<>();
        List<String> current = null;
        int printed = 0;
        for (String line : Files.readAllLines(jpfOut, StandardCharsets.UTF_8)) {
            if (line.equals("@@TRACE")) {
                current = new ArrayList<>();
            } else if (line.equals("@@END") && current != null) {
                distinct.add(current);
                current = null;
                printed++;
            } else if (line.startsWith("@@E\t") && current != null) {
                current.add(line);
            }
        }
        int index = 0;
        for (List<String> trace : distinct) {
            TraceGenerator.write(dir, s, ++index, events(trace));
        }
        System.out.println(
                s.name + ": " + printed + " traces printed, " + distinct.size() + " distinct, written to " + dir);
    }

    private static List<TraceRecorder.Event> events(List<String> lines) {
        final List<TraceRecorder.Event> events = new ArrayList<>();
        for (String line : lines) {
            final String[] f = line.split("\t", -1);
            final List<Integer> bytes = new ArrayList<>();
            if (!f[4].isEmpty()) {
                for (String b : f[4].split(",")) {
                    bytes.add(Integer.parseInt(b));
                }
            }
            events.add(new TraceRecorder.Event(f[1], f[2], Long.parseLong(f[3]), Collections.unmodifiableList(bytes)));
        }
        return events;
    }
}
