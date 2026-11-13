// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.drf;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.AnnotationNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.InnerClassNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.analysis.Analyzer;
import org.objectweb.asm.tree.analysis.AnalyzerException;
import org.objectweb.asm.tree.analysis.BasicInterpreter;
import org.objectweb.asm.tree.analysis.BasicValue;
import org.objectweb.asm.tree.analysis.Frame;
import org.objectweb.asm.tree.analysis.Interpreter;
import org.objectweb.asm.tree.analysis.Value;

/**
 * The lock discipline of a class, checked on its bytecode (roadmap A17): every access to a field
 * annotated {@code @GuardedBy(L)}, and every call of a method annotated so, happens with the
 * monitor of the field {@code L} held, on every path of the method; a field that is neither final,
 * volatile nor atomic must be annotated. Unlike a scenario-based race detector this covers every
 * execution: the locks held at an instruction are a property of the control flow, not of a run.
 *
 * <p>The analysis per method is a forward data flow over the control-flow graph (ASM's {@link
 * Analyzer}): {@code monitorenter} of a value loaded from the field {@code L} adds L, {@code
 * monitorexit} removes it, and where paths meet only what every path holds is held. A method
 * annotated {@code @GuardedBy(L)} starts with L held. Synthetic accessors ({@code access$NNN}: Java 8
 * bytecode has no nestmates, so an inner class reaches the outer class's private members through
 * them) pass what they need on to their callers. Constructors may touch their own class's fields
 * unguarded (the object is not published yet); nothing else is exempt.
 */
final class LockDiscipline {

    static final String GUARDED_BY = "Lcom/google/errorprone/annotations/concurrent/GuardedBy;";

    private final Map<String, ClassNode> classes;
    /** owner.name -> the lock field guarding it */
    private final Map<String, String> guardedFields = new HashMap<>();
    /** owner.name+desc -> the lock the method expects held */
    private final Map<String, String> guardedMethods = new HashMap<>();

    private final List<String> violations = new ArrayList<>();

    private LockDiscipline(final Map<String, ClassNode> classes) {
        this.classes = classes;
    }

    /** The class files of {@code outer} and its nested classes, as the class loader has them. */
    static Map<String, ClassNode> load(final Class<?> outer) throws IOException {
        final Map<String, ClassNode> classes = new LinkedHashMap<>();
        final Deque<String> todo = new ArrayDeque<>();
        todo.add(Type.getInternalName(outer));
        while (!todo.isEmpty()) {
            final String name = todo.poll();
            if (classes.containsKey(name)) {
                continue;
            }
            final ClassNode node = read(outer.getClassLoader(), name);
            classes.put(name, node);
            for (final InnerClassNode inner : node.innerClasses) {
                if (inner.name.startsWith(Type.getInternalName(outer) + "$")) {
                    todo.add(inner.name);
                }
            }
        }
        return classes;
    }

    private static ClassNode read(final ClassLoader loader, final String internalName) throws IOException {
        try (InputStream in = loader.getResourceAsStream(internalName + ".class")) {
            if (in == null) {
                throw new IOException("class file not found: " + internalName);
            }
            final ClassNode node = new ClassNode();
            new ClassReader(in).accept(node, 0);
            return node;
        }
    }

    /** The violations of the lock discipline in these classes; empty if it holds. */
    static List<String> check(final Map<String, ClassNode> classes) throws AnalyzerException {
        final LockDiscipline d = new LockDiscipline(classes);
        d.collectAnnotations();
        d.checkFieldKinds();
        d.checkMethods();
        return Collections.unmodifiableList(d.violations);
    }

    // -------------------------------------------------------------------------------------------
    // annotations and field kinds

    private void collectAnnotations() {
        for (final ClassNode c : classes.values()) {
            for (final FieldNode f : c.fields) {
                final String lock = guardOf(f.visibleAnnotations, f.invisibleAnnotations);
                if (lock != null) {
                    guardedFields.put(c.name + "." + f.name, lock);
                }
            }
            for (final MethodNode m : c.methods) {
                final String lock = guardOf(m.visibleAnnotations, m.invisibleAnnotations);
                if (lock != null) {
                    guardedMethods.put(c.name + "." + m.name + m.desc, lock);
                }
            }
        }
    }

    private static String guardOf(final List<AnnotationNode> visible, final List<AnnotationNode> invisible) {
        for (final List<AnnotationNode> list : List.of(
                visible == null ? List.<AnnotationNode>of() : visible,
                invisible == null ? List.<AnnotationNode>of() : invisible)) {
            for (final AnnotationNode a : list) {
                if (GUARDED_BY.equals(a.desc) && a.values != null) {
                    for (int i = 0; i + 1 < a.values.size(); i += 2) {
                        if ("value".equals(a.values.get(i))) {
                            return (String) a.values.get(i + 1);
                        }
                    }
                }
            }
        }
        return null;
    }

    /** A field that is shared and mutable without being final, volatile or atomic. */
    static boolean isPlain(final FieldNode f) {
        if ((f.access & (Opcodes.ACC_FINAL | Opcodes.ACC_VOLATILE)) != 0) {
            return false;
        }
        return !Type.getType(f.desc).getClassName().startsWith("java.util.concurrent.atomic.");
    }

    private void checkFieldKinds() {
        for (final ClassNode c : classes.values()) {
            for (final FieldNode f : c.fields) {
                if (isPlain(f) && !guardedFields.containsKey(c.name + "." + f.name)) {
                    violations.add("plain field without @GuardedBy: " + c.name + "." + f.name);
                }
            }
        }
        for (final Map.Entry<String, String> e : guardedFields.entrySet()) {
            final String owner = e.getKey().substring(0, e.getKey().indexOf('.'));
            if (field(owner, e.getValue()) == null) {
                violations.add("@GuardedBy names no field of " + owner + ": " + e.getKey() + " by " + e.getValue());
            }
        }
    }

    private FieldNode field(final String owner, final String name) {
        final ClassNode c = classes.get(owner);
        if (c != null) {
            for (final FieldNode f : c.fields) {
                if (f.name.equals(name)) {
                    return f;
                }
            }
        }
        return null;
    }

    // -------------------------------------------------------------------------------------------
    // the methods

    private void checkMethods() throws AnalyzerException {
        // what each synthetic accessor needs held at its call, to a fixpoint (an accessor may call
        // another); then every method, the accessors' needs at their call sites included
        final Map<String, Set<String>> needs = new HashMap<>();
        boolean changed = true;
        while (changed) {
            changed = false;
            for (final ClassNode c : classes.values()) {
                for (final MethodNode m : c.methods) {
                    if ((m.access & Opcodes.ACC_SYNTHETIC) == 0 || m.instructions.size() == 0) {
                        continue;
                    }
                    final Set<String> need = new HashSet<>();
                    analyze(c, m, needs, need::add);
                    final String key = c.name + "." + m.name + m.desc;
                    if (!need.equals(needs.getOrDefault(key, Set.of()))) {
                        needs.put(key, need);
                        changed = true;
                    }
                }
            }
        }
        for (final ClassNode c : classes.values()) {
            for (final MethodNode m : c.methods) {
                if ((m.access & Opcodes.ACC_SYNTHETIC) != 0 || m.instructions.size() == 0) {
                    continue;
                }
                analyze(c, m, needs, what -> violations.add(c.name + "." + m.name + m.desc + ": " + what));
            }
        }
    }

    private interface Sink {
        void add(String what);
    }

    /**
     * The locks held at each instruction of {@code m}; reports every access that needs a lock not
     * held there (for an accessor: the lock, to be held by its callers).
     */
    private void analyze(final ClassNode c, final MethodNode m, final Map<String, Set<String>> needs, final Sink sink)
            throws AnalyzerException {
        final boolean accessor = (m.access & Opcodes.ACC_SYNTHETIC) != 0;
        final int n = m.instructions.size();
        final List<List<Integer>> normal = new ArrayList<>();
        final List<List<Integer>> exceptional = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            normal.add(new ArrayList<>());
            exceptional.add(new ArrayList<>());
        }
        final Analyzer<Origin> analyzer = new Analyzer<Origin>(new OriginInterpreter()) {
            @Override
            protected void newControlFlowEdge(final int insn, final int successor) {
                normal.get(insn).add(successor);
            }

            @Override
            protected boolean newControlFlowExceptionEdge(final int insn, final int successor) {
                exceptional.get(insn).add(successor);
                return true;
            }
        };
        final Frame<Origin>[] frames = analyzer.analyze(c.name, m);

        // must-hold data flow: the count of each lock held, the minimum where paths meet
        final List<Map<String, Integer>> held = new ArrayList<>(Collections.nCopies(n, null));
        final Map<String, Integer> entry = new TreeMap<>();
        final String own = guardedMethods.get(c.name + "." + m.name + m.desc);
        if (own != null) {
            entry.put(own, 1);
        }
        held.set(0, entry);
        final Deque<Integer> work = new ArrayDeque<>();
        work.add(0);
        while (!work.isEmpty()) {
            final int i = work.poll();
            final Map<String, Integer> before = held.get(i);
            final Map<String, Integer> after = new TreeMap<>(before);
            final AbstractInsnNode insn = m.instructions.get(i);
            if (insn.getOpcode() == Opcodes.MONITORENTER || insn.getOpcode() == Opcodes.MONITOREXIT) {
                final Frame<Origin> f = Objects.requireNonNull(frames[i], "unreachable monitor instruction");
                final String lock = lockOf(f.getStack(f.getStackSize() - 1));
                if (insn.getOpcode() == Opcodes.MONITORENTER) {
                    after.merge(lock, 1, Integer::sum);
                } else {
                    after.computeIfPresent(lock, (k, v) -> v > 1 ? v - 1 : null);
                }
            }
            for (final int s : normal.get(i)) {
                flow(held, work, s, after);
            }
            for (final int s : exceptional.get(i)) {
                flow(held, work, s, before);
            }
        }

        for (int i = 0; i < n; i++) {
            final Map<String, Integer> h = held.get(i);
            if (h == null) {
                continue; // unreachable
            }
            final AbstractInsnNode insn = m.instructions.get(i);
            final List<String> required = new ArrayList<>();
            String what = null;
            if (insn instanceof FieldInsnNode fi) {
                final String lock = guardedFields.get(fi.owner + "." + fi.name);
                final boolean ownInit = m.name.equals("<init>") || m.name.equals("<clinit>");
                if (lock != null && !(ownInit && fi.owner.equals(c.name))) {
                    required.add(lock);
                    what = "access to " + fi.owner + "." + fi.name;
                }
            } else if (insn instanceof MethodInsnNode mi) {
                final String key = mi.owner + "." + mi.name + mi.desc;
                final String lock = guardedMethods.get(key);
                if (lock != null) {
                    required.add(lock);
                }
                required.addAll(needs.getOrDefault(key, Set.of()));
                what = "call of " + key;
            }
            for (final String lock : required) {
                if (!h.containsKey(lock)) {
                    sink.add(accessor ? lock : what + " without " + lock + " held");
                }
            }
        }
    }

    private static void flow(
            final List<Map<String, Integer>> held,
            final Deque<Integer> work,
            final int s,
            final Map<String, Integer> state) {
        final Map<String, Integer> old = held.get(s);
        final Map<String, Integer> merged;
        if (old == null) {
            merged = new TreeMap<>(state);
        } else {
            merged = new TreeMap<>();
            for (final Map.Entry<String, Integer> e : old.entrySet()) {
                final Integer other = state.get(e.getKey());
                if (other != null) {
                    merged.put(e.getKey(), Math.min(e.getValue(), other));
                }
            }
        }
        if (!merged.equals(old)) {
            held.set(s, merged);
            work.add(s);
        }
    }

    /** The lock a monitor operand is: the field it was loaded from, or "?" if not one field. */
    private static String lockOf(final Origin v) {
        return v.fields.size() == 1 ? v.fields.iterator().next() : "?";
    }

    // -------------------------------------------------------------------------------------------
    // where a value comes from: the names of the fields it may have been loaded from

    static final class Origin implements Value {
        final int size;
        final Set<String> fields;

        Origin(final int size, final Set<String> fields) {
            this.size = size;
            this.fields = fields;
        }

        @Override
        public int getSize() {
            return size;
        }

        @Override
        public boolean equals(final Object o) {
            return o instanceof Origin other && other.size == size && other.fields.equals(fields);
        }

        @Override
        public int hashCode() {
            return 31 * size + fields.hashCode();
        }
    }

    /** Tracks field origins through copies; the sizes come from ASM's {@link BasicInterpreter}. */
    static final class OriginInterpreter extends Interpreter<Origin> {
        private final BasicInterpreter basic = new BasicInterpreter();

        OriginInterpreter() {
            super(Opcodes.ASM9);
        }

        private static Origin of(final BasicValue v) {
            return v == null ? null : new Origin(v.getSize(), Set.of());
        }

        private static BasicValue basic(final Origin v) {
            return v.size == 2 ? BasicValue.LONG_VALUE : BasicValue.REFERENCE_VALUE;
        }

        @Override
        public Origin newValue(final Type type) {
            return of(basic.newValue(type));
        }

        @Override
        public Origin newOperation(final AbstractInsnNode insn) throws AnalyzerException {
            final Origin v = of(basic.newOperation(insn));
            if (insn instanceof FieldInsnNode fi && v != null) {
                return new Origin(v.size, Set.of(fi.name));
            }
            return v;
        }

        @Override
        public Origin copyOperation(final AbstractInsnNode insn, final Origin value) {
            return value;
        }

        @Override
        public Origin unaryOperation(final AbstractInsnNode insn, final Origin value) throws AnalyzerException {
            final Origin v = of(basic.unaryOperation(insn, basic(value)));
            if (insn.getOpcode() == Opcodes.GETFIELD && v != null) {
                return new Origin(v.size, Set.of(((FieldInsnNode) insn).name));
            }
            return v;
        }

        @Override
        public Origin binaryOperation(final AbstractInsnNode insn, final Origin a, final Origin b)
                throws AnalyzerException {
            return of(basic.binaryOperation(insn, basic(a), basic(b)));
        }

        @Override
        public Origin ternaryOperation(final AbstractInsnNode insn, final Origin a, final Origin b, final Origin c) {
            return null;
        }

        @Override
        public Origin naryOperation(final AbstractInsnNode insn, final List<? extends Origin> values)
                throws AnalyzerException {
            final List<BasicValue> args = new ArrayList<>();
            for (final Origin o : values) {
                args.add(basic(o));
            }
            return of(basic.naryOperation(insn, args));
        }

        @Override
        public void returnOperation(final AbstractInsnNode insn, final Origin value, final Origin expected) {}

        @Override
        public Origin merge(final Origin a, final Origin b) {
            if (a.equals(b)) {
                return a;
            }
            final Set<String> union = new HashSet<>(a.fields);
            union.addAll(b.fields);
            return new Origin(Math.min(a.size, b.size), Set.copyOf(union));
        }
    }
}
