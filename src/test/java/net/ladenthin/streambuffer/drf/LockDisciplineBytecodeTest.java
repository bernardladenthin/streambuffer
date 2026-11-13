// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.drf;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasItem;
import static org.junit.jupiter.api.Assumptions.assumeFalse;

import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import net.ladenthin.streambuffer.StreamBuffer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;

/**
 * Roadmap A17: the lock discipline of {@link StreamBuffer} holds on its bytecode for every
 * execution (see {@link LockDiscipline}), and the field table of the README's "Data-Race Freedom"
 * section lists every instance field with its kind. The negative controls mutate the class files
 * in memory: each kind of violation must be reported.
 */
class LockDisciplineBytecodeTest {

    private static final String OUTER = "net/ladenthin/streambuffer/StreamBuffer";
    private Map<String, ClassNode> classes;

    @BeforeEach
    void load() throws IOException {
        // under -Pjml-rac the class file is RAC's, whose checks read the fields without the lock
        assumeFalse(Boolean.getBoolean("streambuffer.test.rac"), "RAC-instrumented StreamBuffer");
        classes = LockDiscipline.load(StreamBuffer.class);
    }

    @Test
    void everyGuardedAccessHoldsItsLockOnEveryPath() throws Exception {
        assertThat(classes.keySet(), hasItem(OUTER + "$SBInputStream"));
        assertThat(LockDiscipline.check(classes), empty());
    }

    @Test
    void theFieldTableOfTheReadmeListsEveryFieldWithItsKind() throws IOException {
        assertThat(FieldTable.differences(FieldTable.parse(readme()), StreamBuffer.class), empty());
    }

    // ---------------------------------------------------------------------------------------------
    // negative controls

    @Test
    void anUnguardedReadOfAGuardedFieldIsReported() throws Exception {
        final MethodNode m = method(OUTER, "isClosed", "()Z");
        final InsnList read = new InsnList();
        read.add(new VarInsnNode(Opcodes.ALOAD, 0));
        read.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "buffer", "Ljava/util/Deque;"));
        read.add(new InsnNode(Opcodes.POP));
        m.instructions.insert(read);
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString("isClosed()Z: access to " + OUTER + ".buffer without bufferLock held")));
    }

    @Test
    void anUnguardedReadOfAFieldOfTheSignalLockIsReported() throws Exception {
        final MethodNode m = method(OUTER, "isClosed", "()Z");
        final InsnList read = new InsnList();
        read.add(new VarInsnNode(Opcodes.ALOAD, 0));
        read.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "releasingSignals", "Ljava/util/ArrayDeque;"));
        read.add(new InsnNode(Opcodes.POP));
        m.instructions.insert(read);
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString(
                        "isClosed()Z: access to " + OUTER + ".releasingSignals without signalLock held")));
    }

    @Test
    void theWrongLockIsReported() throws Exception {
        // toString takes bufferLock; a read of a field of signalLock there is still unguarded
        final MethodNode m = method(OUTER, "toString", "()Ljava/lang/String;");
        for (int i = 0; i < m.instructions.size(); i++) {
            if (m.instructions.get(i).getOpcode() == Opcodes.MONITORENTER) {
                final InsnList read = new InsnList();
                read.add(new VarInsnNode(Opcodes.ALOAD, 0));
                read.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "releasingSignals", "Ljava/util/ArrayDeque;"));
                read.add(new InsnNode(Opcodes.POP));
                m.instructions.insert(m.instructions.get(i), read);
                break;
            }
        }
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString("toString()Ljava/lang/String;: access to " + OUTER
                        + ".releasingSignals without signalLock held")));
    }

    @Test
    void anUnguardedCallOfAGuardedMethodIsReported() throws Exception {
        final MethodNode m = method(OUTER, "isClosed", "()Z");
        final InsnList call = new InsnList();
        call.add(new VarInsnNode(Opcodes.ALOAD, 0));
        call.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, OUTER, "pollHead", "()V", false));
        m.instructions.insert(call);
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString("isClosed()Z: call of " + OUTER + ".pollHead()V without bufferLock held")));
    }

    @Test
    void aGuardedMethodWithoutItsAnnotationIsReported() throws Exception {
        final MethodNode m = method(OUTER, "pollHead", "()V");
        m.invisibleAnnotations.removeIf(a -> LockDiscipline.GUARDED_BY.equals(a.desc));
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString("pollHead()V: access to " + OUTER + ".buffer without bufferLock held")));
    }

    @Test
    void aLockNoLongerTakenIsReported() throws Exception {
        // the monitorenter of toString's synchronized block becomes a POP: the lock is no longer
        // taken, so the reads inside the block are unguarded on every path
        final MethodNode m = method(OUTER, "toString", "()Ljava/lang/String;");
        for (int i = 0; i < m.instructions.size(); i++) {
            if (m.instructions.get(i).getOpcode() == Opcodes.MONITORENTER) {
                m.instructions.set(m.instructions.get(i), new InsnNode(Opcodes.POP));
                break;
            }
        }
        assertThat(
                LockDiscipline.check(classes),
                hasItem(containsString(
                        "toString()Ljava/lang/String;: access to " + OUTER + ".buffer without bufferLock held")));
    }

    @Test
    void aPlainFieldWithoutGuardedByIsReported() throws Exception {
        classes.get(OUTER).fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "unguarded", "I", null, null));
        assertThat(LockDiscipline.check(classes), hasItem("plain field without @GuardedBy: " + OUTER + ".unguarded"));
    }

    @Test
    void aFieldMissingFromTheTableIsReported() throws IOException {
        final Map<String, String> table = FieldTable.parse(readme());
        table.remove("availableBytes");
        assertThat(
                FieldTable.differences(table, StreamBuffer.class),
                hasItem("field not in the README table: availableBytes"));
    }

    @Test
    void aWrongKindInTheTableIsReported() throws IOException {
        final Map<String, String> table = FieldTable.parse(readme());
        table.put("streamClosed", "`final boolean`");
        assertThat(
                FieldTable.differences(table, StreamBuffer.class), hasItem(containsString("streamClosed is volatile")));
    }

    @Test
    void theMutatedClassesStillVerify() throws Exception {
        // the controls above change the tree only; this shows the tree is a real class file
        final ClassWriter w = new ClassWriter(0);
        classes.get(OUTER).accept(w);
        new ClassReader(w.toByteArray()).accept(new ClassNode(), 0);
    }

    private MethodNode method(final String owner, final String name, final String desc) {
        for (final MethodNode m : classes.get(owner).methods) {
            if (m.name.equals(name) && m.desc.equals(desc)) {
                return m;
            }
        }
        throw new AssertionError("no method " + owner + "." + name + desc);
    }

    private static String readme() throws IOException {
        return Files.readString(Path.of("README.md"), StandardCharsets.UTF_8);
    }

    /** The field table of the README's "Data-Race Freedom" section: field name -> its kind cell. */
    static final class FieldTable {

        private static final Pattern NAME = Pattern.compile("`([a-z][A-Za-z0-9]*)`");

        static Map<String, String> parse(final String readme) {
            final int start = readme.indexOf("| Field | Kind | Written | Read |");
            if (start < 0) {
                throw new AssertionError("no field table in the README");
            }
            final Map<String, String> table = new LinkedHashMap<>();
            for (final String line : readme.substring(start).split("\n")) {
                if (!line.startsWith("|")) {
                    break;
                }
                final String[] cells = line.split("\\|");
                if (cells.length < 3 || cells[1].contains("Field") || cells[1].contains("---")) {
                    continue;
                }
                // the names before a type in parentheses: `buffer` (`ArrayDeque<byte[]>`)
                final String names = cells[1].replaceAll("\\(.*?\\)", "");
                final Matcher matcher = NAME.matcher(names);
                while (matcher.find()) {
                    table.put(matcher.group(1), cells[2].trim());
                }
            }
            return table;
        }

        /** What the table and the class disagree on, as messages; empty if they agree. */
        static List<String> differences(final Map<String, String> table, final Class<?> c) {
            final List<String> out = new ArrayList<>();
            final Map<String, Field> fields = new TreeMap<>();
            for (final Field f : c.getDeclaredFields()) {
                if (!f.isSynthetic() && !(Modifier.isStatic(f.getModifiers()) && Modifier.isFinal(f.getModifiers()))) {
                    fields.put(f.getName(), f);
                }
            }
            for (final Map.Entry<String, Field> e : fields.entrySet()) {
                final String kind = table.get(e.getKey());
                if (kind == null) {
                    out.add("field not in the README table: " + e.getKey());
                    continue;
                }
                final int mod = e.getValue().getModifiers();
                if (Modifier.isVolatile(mod) && !kind.contains("volatile")) {
                    out.add(e.getKey() + " is volatile, the table says " + kind);
                } else if (Modifier.isFinal(mod) && !kind.contains("final")) {
                    out.add(e.getKey() + " is final, the table says " + kind);
                } else if (!Modifier.isFinal(mod) && !Modifier.isVolatile(mod) && !kind.contains("@GuardedBy")) {
                    out.add(e.getKey() + " is plain (guarded by a lock), the table says " + kind);
                } else if (!Modifier.isFinal(mod) && kind.contains("final")) {
                    out.add(e.getKey() + " is not final, the table says " + kind);
                }
            }
            for (final String name : table.keySet()) {
                if (!fields.containsKey(name)) {
                    out.add("not a field of " + c.getSimpleName() + ": " + name);
                }
            }
            return out;
        }
    }
}
