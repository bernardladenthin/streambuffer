// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/**
 * Writes the class files of {@code StreamBuffer} as {@link TracingClassLoader} rewrites them (roadmap
 * A18), so that Java PathFinder can run the instrumented class from a directory: JPF has its own class
 * loading and does not run the tracing loader.
 */
public final class TracedClassDump {

    private TracedClassDump() {}

    /**
     * Writes the instrumented class files.
     *
     * @param args the output directory (the class files go below it in their package directories), and
     *     optionally {@code no-decrement}: a negative control, {@code readSingleByte} no longer lowers
     *     {@code availableBytes} (a defect the model must reject)
     * @throws IOException if a class file cannot be read or written
     */
    public static void main(String[] args) throws IOException {
        final Path out = Paths.get(args[0]);
        final List<String> names = new ArrayList<>();
        names.add("net/ladenthin/streambuffer/StreamBuffer");
        for (Class<?> inner : net.ladenthin.streambuffer.StreamBuffer.class.getDeclaredClasses()) {
            names.add(inner.getName().replace('.', '/'));
        }
        for (int i = 1; resource("net/ladenthin/streambuffer/StreamBuffer$" + i + ".class") != null; i++) {
            names.add("net/ladenthin/streambuffer/StreamBuffer$" + i);
        }
        for (String name : names) {
            byte[] original = read(name + ".class");
            if (args.length > 1 && args[1].equals("no-decrement") && name.endsWith("/StreamBuffer")) {
                original = noDecrement(original);
            }
            final Path file = out.resolve(name + ".class");
            Files.createDirectories(file.getParent());
            Files.write(file, TracingClassLoader.instrument(original));
            System.out.println("instrumented " + name);
        }
    }

    /** In {@code readSingleByte}, the first {@code lconst_1; lsub} becomes {@code lconst_0; lsub}. */
    private static byte[] noDecrement(byte[] classFile) {
        final org.objectweb.asm.tree.ClassNode node = new org.objectweb.asm.tree.ClassNode();
        new org.objectweb.asm.ClassReader(classFile).accept(node, 0);
        boolean done = false;
        for (org.objectweb.asm.tree.MethodNode m : node.methods) {
            if (!m.name.equals("readSingleByte")) {
                continue;
            }
            for (org.objectweb.asm.tree.AbstractInsnNode insn : m.instructions) {
                if (!done
                        && insn.getOpcode() == org.objectweb.asm.Opcodes.LCONST_1
                        && insn.getNext() != null
                        && insn.getNext().getOpcode() == org.objectweb.asm.Opcodes.LSUB) {
                    m.instructions.set(insn, new org.objectweb.asm.tree.InsnNode(org.objectweb.asm.Opcodes.LCONST_0));
                    done = true;
                    break;
                }
            }
        }
        if (!done) {
            throw new IllegalStateException("no lconst_1; lsub in readSingleByte");
        }
        final org.objectweb.asm.ClassWriter w = new org.objectweb.asm.ClassWriter(0);
        node.accept(w);
        return w.toByteArray();
    }

    private static InputStream resource(String name) {
        return TracedClassDump.class.getClassLoader().getResourceAsStream(name);
    }

    private static byte[] read(String name) throws IOException {
        try (InputStream in = resource(name)) {
            if (in == null) {
                throw new IOException("not found: " + name);
            }
            final ByteArrayOutputStream b = new ByteArrayOutputStream();
            final byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                b.write(buf, 0, n);
            }
            return b.toByteArray();
        }
    }
}
