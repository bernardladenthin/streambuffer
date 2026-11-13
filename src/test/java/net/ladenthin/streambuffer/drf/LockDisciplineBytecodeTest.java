// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.drf;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
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
import org.objectweb.asm.Handle;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.InvokeDynamicInsnNode;
import org.objectweb.asm.tree.JumpInsnNode;
import org.objectweb.asm.tree.LabelNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.TypeInsnNode;
import org.objectweb.asm.tree.VarInsnNode;
import org.objectweb.asm.tree.analysis.AnalyzerException;

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
        assertThat(check(), empty());
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
                check(),
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
                check(),
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
                check(),
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
                check(),
                hasItem(containsString("isClosed()Z: call of " + OUTER + ".pollHead()V without bufferLock held")));
    }

    @Test
    void aGuardedMethodWithoutItsAnnotationIsReported() throws Exception {
        final MethodNode m = method(OUTER, "pollHead", "()V");
        m.invisibleAnnotations.removeIf(a -> LockDiscipline.GUARDED_BY.equals(a.desc));
        assertThat(
                check(),
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
                check(),
                hasItem(containsString(
                        "toString()Ljava/lang/String;: access to " + OUTER + ".buffer without bufferLock held")));
    }

    @Test
    void anAccessorThatNeedsALockIsReportedAtItsCallInTheInnerClass() throws Exception {
        // an accessor an inner class calls, made to read buffer: the call has no lock
        MethodInsnNode call = null;
        String caller = null;
        for (final ClassNode c : classes.values()) {
            for (final MethodNode m : c.methods) {
                for (final AbstractInsnNode insn : m.instructions) {
                    if (call == null
                            && !c.name.equals(OUTER)
                            && insn instanceof MethodInsnNode mi
                            && mi.owner.equals(OUTER)
                            && mi.name.startsWith("access$")
                            && mi.desc.startsWith("(L" + OUTER + ";")) {
                        call = mi;
                        caller = c.name + "." + m.name + m.desc;
                    }
                }
            }
        }
        assertThat("an inner class calls an accessor", call != null);
        final MethodNode accessor = method(OUTER, call.name, call.desc);
        accessor.instructions.insert(readOf(0, "buffer", "Ljava/util/Deque;"));
        assertThat(
                check(),
                hasItem(caller + ": call of " + OUTER + "." + call.name + call.desc + " without bufferLock held"));
    }

    @Test
    void anAccessorGivenAnotherObjectIsReported() throws Exception {
        // static void access$999(StreamBuffer sb) { sb.buffer; } -- needs sb's bufferLock
        final InsnList body = readOf(0, "buffer", "Ljava/util/Deque;");
        body.add(new InsnNode(Opcodes.RETURN));
        final String desc = "(L" + OUTER + ";)V";
        addMethod("access$999", desc, Opcodes.ACC_STATIC | Opcodes.ACC_SYNTHETIC, body, 1, 1);
        // synchronized (bufferLock) { access$999(x); } with x = other, and with x = this
        for (final String name : List.of("viaOther", "viaThis")) {
            final InsnList code = new InsnList();
            code.add(new VarInsnNode(Opcodes.ALOAD, 0));
            code.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "bufferLock", "Ljava/lang/Object;"));
            code.add(new InsnNode(Opcodes.MONITORENTER));
            code.add(new VarInsnNode(Opcodes.ALOAD, name.equals("viaOther") ? 1 : 0));
            code.add(new MethodInsnNode(Opcodes.INVOKESTATIC, OUTER, "access$999", desc, false));
            code.add(new InsnNode(Opcodes.RETURN));
            addMethod(name, desc, Opcodes.ACC_PRIVATE, code, 1, 2);
        }
        final List<String> violations = check();
        assertThat(
                violations,
                hasItem(OUTER + ".viaOther" + desc + ": call of " + OUTER + ".access$999" + desc
                        + " with another object than this"));
        assertThat(violations, not(hasItem(containsString(".viaThis"))));
    }

    @Test
    void aLockTakenOnOneBranchOnlyIsReported() throws Exception {
        // if (flag) monitorenter(bufferLock); buffer; -- held on one path only
        final LabelNode skip = new LabelNode();
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ILOAD, 1));
        code.add(new JumpInsnNode(Opcodes.IFEQ, skip));
        code.add(readOf(0, "bufferLock", "Ljava/lang/Object;"));
        code.remove(code.getLast());
        code.add(new InsnNode(Opcodes.MONITORENTER));
        code.add(skip);
        code.add(readOf(0, "buffer", "Ljava/util/Deque;"));
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("oneBranch", "(Z)V", Opcodes.ACC_PRIVATE, code, 2, 2);
        assertThat(check(), hasItem(OUTER + ".oneBranch(Z)V: access to " + OUTER + ".buffer without bufferLock held"));
    }

    @Test
    void aMonitorThatIsTheLockOnOnePathOnlyIsReported() throws Exception {
        // Object l = flag ? bufferLock : new Object(); synchronized (l) { buffer; }
        final LabelNode other = new LabelNode();
        final LabelNode join = new LabelNode();
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ILOAD, 1));
        code.add(new JumpInsnNode(Opcodes.IFEQ, other));
        code.add(new VarInsnNode(Opcodes.ALOAD, 0));
        code.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "bufferLock", "Ljava/lang/Object;"));
        code.add(new VarInsnNode(Opcodes.ASTORE, 2));
        code.add(new JumpInsnNode(Opcodes.GOTO, join));
        code.add(other);
        code.add(new TypeInsnNode(Opcodes.NEW, "java/lang/Object"));
        code.add(new InsnNode(Opcodes.DUP));
        code.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false));
        code.add(new VarInsnNode(Opcodes.ASTORE, 2));
        code.add(join);
        code.add(new VarInsnNode(Opcodes.ALOAD, 2));
        code.add(new InsnNode(Opcodes.MONITORENTER));
        code.add(readOf(0, "buffer", "Ljava/util/Deque;"));
        code.add(new VarInsnNode(Opcodes.ALOAD, 2));
        code.add(new InsnNode(Opcodes.MONITOREXIT));
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("mixed", "(Z)V", Opcodes.ACC_PRIVATE, code, 2, 3);
        assertThat(check(), hasItem(OUTER + ".mixed(Z)V: access to " + OUTER + ".buffer without bufferLock held"));
    }

    @Test
    void anAccessInTheHandlerAfterTheMonitorexitIsReported() throws Exception {
        // javac's handler of a synchronized block releases the lock before it rethrows; the last
        // monitorexit of toString is that one, reached by the exception edges only
        final MethodNode m = method(OUTER, "toString", "()Ljava/lang/String;");
        AbstractInsnNode last = null;
        for (final AbstractInsnNode insn : m.instructions) {
            if (insn.getOpcode() == Opcodes.MONITOREXIT) {
                last = insn;
            }
        }
        assertThat("toString has a monitorexit", last != null);
        m.instructions.insert(last, readOf(0, "buffer", "Ljava/util/Deque;"));
        assertThat(
                check(),
                hasItem(containsString(
                        "toString()Ljava/lang/String;: access to " + OUTER + ".buffer without bufferLock held")));
    }

    @Test
    void anUnguardedAccessInALambdaBodyIsReported() throws Exception {
        final InsnList code = readOf(0, "buffer", "Ljava/util/Deque;");
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("lambda$isClosed$0", "()V", Opcodes.ACC_PRIVATE | Opcodes.ACC_SYNTHETIC, code, 1, 1);
        assertThat(
                check(),
                hasItem(OUTER + ".lambda$isClosed$0()V: access to " + OUTER + ".buffer without bufferLock held"));
    }

    @Test
    void aMethodReferenceToAGuardedMethodIsReported() throws Exception {
        // isClosed creates this::pollHead
        final Handle metafactory = new Handle(
                Opcodes.H_INVOKESTATIC,
                "java/lang/invoke/LambdaMetafactory",
                "metafactory",
                "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;"
                        + "Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)"
                        + "Ljava/lang/invoke/CallSite;",
                false);
        final Handle pollHead = new Handle(Opcodes.H_INVOKESPECIAL, OUTER, "pollHead", "()V", false);
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ALOAD, 0));
        code.add(new InvokeDynamicInsnNode(
                "run",
                "(L" + OUTER + ";)Ljava/lang/Runnable;",
                metafactory,
                Type.getType("()V"),
                pollHead,
                Type.getType("()V")));
        code.add(new InsnNode(Opcodes.POP));
        method(OUTER, "isClosed", "()Z").instructions.insert(code);
        assertThat(
                check(),
                hasItem(containsString("isClosed()Z: a method reference to the guarded " + OUTER + ".pollHead()V")));
    }

    @Test
    void theLockOfAnotherObjectIsReported() throws Exception {
        // synchronized (other.bufferLock) { buffer; }
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ALOAD, 1));
        code.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "bufferLock", "Ljava/lang/Object;"));
        code.add(new InsnNode(Opcodes.MONITORENTER));
        code.add(readOf(0, "buffer", "Ljava/util/Deque;"));
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("otherLock", "(L" + OUTER + ";)V", Opcodes.ACC_PRIVATE, code, 1, 2);
        assertThat(
                check(),
                hasItem(OUTER + ".otherLock(L" + OUTER + ";)V: access to " + OUTER
                        + ".buffer without bufferLock held"));
    }

    @Test
    void anAccessToAnotherObjectsGuardedFieldIsReported() throws Exception {
        // synchronized (bufferLock) { other.buffer; }
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ALOAD, 0));
        code.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, "bufferLock", "Ljava/lang/Object;"));
        code.add(new InsnNode(Opcodes.MONITORENTER));
        code.add(readOf(1, "buffer", "Ljava/util/Deque;"));
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("otherBuffer", "(L" + OUTER + ";)V", Opcodes.ACC_PRIVATE, code, 1, 2);
        assertThat(
                check(),
                hasItem(OUTER + ".otherBuffer(L" + OUTER + ";)V: access to " + OUTER
                        + ".buffer on another object than this"));
    }

    @Test
    void aConstructorReadingAnotherObjectIsReported() throws Exception {
        // a copy constructor reading src.buffer without src's lock
        final InsnList code = new InsnList();
        code.add(new VarInsnNode(Opcodes.ALOAD, 0));
        code.add(new MethodInsnNode(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false));
        code.add(readOf(1, "buffer", "Ljava/util/Deque;"));
        code.add(new InsnNode(Opcodes.RETURN));
        addMethod("<init>", "(L" + OUTER + ";)V", Opcodes.ACC_PRIVATE, code, 1, 2);
        assertThat(
                check(),
                hasItem(OUTER + ".<init>(L" + OUTER + ";)V: access to " + OUTER
                        + ".buffer on another object than this"));
    }

    @Test
    void aPlainFieldWithoutGuardedByIsReported() throws Exception {
        classes.get(OUTER).fields.add(new FieldNode(Opcodes.ACC_PRIVATE, "unguarded", "I", null, null));
        assertThat(check(), hasItem("plain field without @GuardedBy: " + OUTER + ".unguarded"));
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

    private List<String> check() throws AnalyzerException {
        return LockDiscipline.check(OUTER, classes);
    }

    /** aload local; getfield name; pop */
    private static InsnList readOf(final int local, final String name, final String desc) {
        final InsnList read = new InsnList();
        read.add(new VarInsnNode(Opcodes.ALOAD, local));
        read.add(new FieldInsnNode(Opcodes.GETFIELD, OUTER, name, desc));
        read.add(new InsnNode(Opcodes.POP));
        return read;
    }

    private void addMethod(
            final String name,
            final String desc,
            final int access,
            final InsnList code,
            final int maxStack,
            final int maxLocals) {
        final MethodNode m = new MethodNode(Opcodes.ASM9, access, name, desc, null, null);
        m.instructions.add(code);
        m.maxStack = maxStack;
        m.maxLocals = maxLocals;
        classes.get(OUTER).methods.add(m);
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
