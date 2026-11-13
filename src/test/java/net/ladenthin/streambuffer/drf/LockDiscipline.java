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
import org.objectweb.asm.Handle;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.AnnotationNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.InnerClassNode;
import org.objectweb.asm.tree.InvokeDynamicInsnNode;
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
 * annotated {@code @GuardedBy(L)}, and every call of a method annotated so, happens on the object
 * itself with the monitor of its field {@code L} held, on every path of the method; a field that
 * is neither final nor volatile must be annotated. Unlike a scenario-based race detector this
 * covers every execution: the locks held at an instruction are a property of the control flow.
 *
 * <p>The analysis per method is a forward data flow over the control-flow graph (ASM's {@link
 * Analyzer}). A value's origin is tracked: the object itself ({@code this} of the outer class, or
 * {@code this$0} of an inner class), a field loaded from it, or unknown; where paths meet, the
 * origins are joined, so a value that is a lock on one path only is no lock. {@code monitorenter}
 * of the object's field {@code L} adds L, {@code monitorexit} removes it, and where paths meet only
 * what every path holds is held. A method annotated {@code @GuardedBy(L)} starts with L held.
 *
 * <p>Synthetic accessors ({@code access$NNN}: Java 8 bytecode has no nestmates, so an inner class
 * reaches the outer class's private members through them) pass what they need on to their callers;
 * their first parameter is taken to be the object itself, as javac passes {@code this$0}. Every
 * other method is checked as it is, lambda bodies included, and a method reference to a guarded
 * method or field is reported (when it runs cannot be seen). A constructor may touch its own
 * object's fields unguarded (it is not published yet), and nothing else is exempt.
 *
 * <p>Not covered: a guarded object's reference used outside the lock after it was read under it,
 * and calls through a supertype of the class (as with Error Prone's {@code GuardedBy} check).
 */
final class LockDiscipline {

    static final String GUARDED_BY = "Lcom/google/errorprone/annotations/concurrent/GuardedBy;";

    /** the object whose lock discipline is checked */
    static final String SELF = "self";
    /** the instance of an inner class, whose {@code this$0} is the object */
    static final String INNER = "inner";
    /** a value of unknown origin */
    static final String UNKNOWN = "?";
    /** the prefix of a field loaded from the object */
    static final String FIELD = "field:";

    private final String outer;
    private final Map<String, ClassNode> classes;
    /** owner.name -> the lock field guarding it */
    private final Map<String, String> guardedFields = new HashMap<>();
    /** owner.name+desc -> the lock the method expects held */
    private final Map<String, String> guardedMethods = new HashMap<>();

    private final List<String> violations = new ArrayList<>();

    private LockDiscipline(final String outer, final Map<String, ClassNode> classes) {
        this.outer = outer;
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

    /**
     * The violations of the lock discipline of {@code outer} (an internal name) and its nested
     * classes in {@code classes}; empty if it holds.
     */
    static List<String> check(final String outer, final Map<String, ClassNode> classes) throws AnalyzerException {
        final LockDiscipline d = new LockDiscipline(outer, classes);
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

    /**
     * A field that is shared and mutable without being final or volatile. A field of an atomic
     * type is safe only when it is final, so it counts as plain otherwise.
     */
    static boolean isPlain(final FieldNode f) {
        return (f.access & (Opcodes.ACC_FINAL | Opcodes.ACC_VOLATILE)) == 0;
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

    /** A javac accessor of the outer class's private members for its inner classes. */
    private boolean isAccessor(final ClassNode c, final MethodNode m) {
        return c.name.equals(outer) && (m.access & Opcodes.ACC_SYNTHETIC) != 0 && m.name.startsWith("access$");
    }

    private void checkMethods() throws AnalyzerException {
        // what each accessor needs held at its call, to a fixpoint (an accessor may call another);
        // then every other method, the accessors' needs at their call sites included
        final Map<String, Set<String>> needs = new HashMap<>();
        boolean changed = true;
        while (changed) {
            changed = false;
            for (final ClassNode c : classes.values()) {
                for (final MethodNode m : c.methods) {
                    if (!isAccessor(c, m) || m.instructions.size() == 0) {
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
                if (isAccessor(c, m) || m.instructions.size() == 0) {
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
     * held there, or is made on another object (for an accessor: the lock, to be held by its
     * callers).
     */
    private void analyze(final ClassNode c, final MethodNode m, final Map<String, Set<String>> needs, final Sink sink)
            throws AnalyzerException {
        final boolean accessor = isAccessor(c, m);
        final int n = m.instructions.size();
        final List<List<Integer>> normal = new ArrayList<>();
        final List<List<Integer>> exceptional = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            normal.add(new ArrayList<>());
            exceptional.add(new ArrayList<>());
        }
        final String thisOrigin = c.name.equals(outer) ? SELF : INNER;
        final Analyzer<Origin> analyzer =
                new Analyzer<Origin>(new OriginInterpreter(thisOrigin, accessor ? outer : null)) {
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

        // must-hold data flow: the count of each lock held, the minimum where paths meet; an
        // exception edge leaves an instruction before its effect
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

        final boolean init = m.name.equals("<init>");
        for (int i = 0; i < n; i++) {
            final Map<String, Integer> h = held.get(i);
            final Frame<Origin> f = frames[i];
            if (h == null || f == null) {
                continue; // unreachable
            }
            final AbstractInsnNode insn = m.instructions.get(i);
            if (insn instanceof FieldInsnNode fi) {
                final String lock = guardedFields.get(fi.owner + "." + fi.name);
                if (lock == null) {
                    continue;
                }
                final String what = "access to " + fi.owner + "." + fi.name;
                final boolean isStatic = fi.getOpcode() == Opcodes.GETSTATIC || fi.getOpcode() == Opcodes.PUTSTATIC;
                if (!isStatic) {
                    // the receiver: below the value for PUTFIELD, on top for GETFIELD
                    final int depth = fi.getOpcode() == Opcodes.PUTFIELD ? 2 : 1;
                    final Origin receiver = f.getStack(f.getStackSize() - depth);
                    if (!receiver.isSelf()) {
                        sink.add(what + " on another object than this");
                        continue;
                    }
                    if (init && fi.owner.equals(c.name)) {
                        continue; // the constructor's own object, not yet published
                    }
                }
                require(h, List.of(lock), what, accessor, sink);
            } else if (insn instanceof MethodInsnNode mi) {
                final String key = mi.owner + "." + mi.name + mi.desc;
                final String lock = guardedMethods.get(key);
                final Set<String> accessorNeeds = needs.getOrDefault(key, Set.of());
                final List<String> required = new ArrayList<>(accessorNeeds);
                final String what = "call of " + key;
                if (!accessorNeeds.isEmpty()) {
                    // an accessor's needs are those of the object it is given: it must be this
                    final int args = Type.getArgumentTypes(mi.desc).length;
                    if (args == 0 || !f.getStack(f.getStackSize() - args).isSelf()) {
                        sink.add(what + " with another object than this");
                        continue;
                    }
                }
                if (lock != null) {
                    required.add(lock);
                    if (mi.getOpcode() != Opcodes.INVOKESTATIC) {
                        final int args = Type.getArgumentTypes(mi.desc).length;
                        if (!f.getStack(f.getStackSize() - 1 - args).isSelf()) {
                            sink.add(what + " on another object than this");
                            continue;
                        }
                    }
                }
                require(h, required, what, accessor, sink);
            } else if (insn instanceof InvokeDynamicInsnNode indy) {
                for (final Object arg : indy.bsmArgs) {
                    if (arg instanceof Handle handle) {
                        final String key = handle.getOwner() + "." + handle.getName();
                        if (guardedMethods.containsKey(key + handle.getDesc()) || guardedFields.containsKey(key)) {
                            sink.add("a method reference to the guarded " + key + handle.getDesc()
                                    + " (when it runs cannot be checked)");
                        }
                    }
                }
            }
        }
    }

    private static void require(
            final Map<String, Integer> held,
            final List<String> locks,
            final String what,
            final boolean accessor,
            final Sink sink) {
        for (final String lock : locks) {
            if (!held.containsKey(lock)) {
                sink.add(accessor ? lock : what + " without " + lock + " held");
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

    /** The lock a monitor operand is: the object's field it was loaded from on every path, or "?". */
    private static String lockOf(final Origin v) {
        if (v.origins.size() == 1) {
            final String o = v.origins.iterator().next();
            if (o.startsWith(FIELD)) {
                return o.substring(FIELD.length());
            }
        }
        return UNKNOWN;
    }

    // -------------------------------------------------------------------------------------------
    // where a value comes from

    /** The origins a value may have, joined over the paths that reach it. */
    static final class Origin implements Value {
        final int size;
        final Set<String> origins;

        Origin(final int size, final Set<String> origins) {
            this.size = size;
            this.origins = origins;
        }

        boolean isSelf() {
            return origins.equals(Set.of(SELF));
        }

        @Override
        public int getSize() {
            return size;
        }

        @Override
        public boolean equals(final Object o) {
            return o instanceof Origin other && other.size == size && other.origins.equals(origins);
        }

        @Override
        public int hashCode() {
            return 31 * size + origins.hashCode();
        }
    }

    /**
     * Tracks the object, its fields and unknown values through copies and merges; the sizes come
     * from ASM's {@link BasicInterpreter}.
     */
    static final class OriginInterpreter extends Interpreter<Origin> {
        private final BasicInterpreter basic = new BasicInterpreter();
        private final String thisOrigin;
        /** the outer class, for an accessor (whose parameter 0 of that type is the object) */
        private final String accessorOf;

        OriginInterpreter(final String thisOrigin, final String accessorOf) {
            super(Opcodes.ASM9);
            this.thisOrigin = thisOrigin;
            this.accessorOf = accessorOf;
        }

        private static Origin unknown(final BasicValue v) {
            return v == null ? null : new Origin(v.getSize(), Set.of(UNKNOWN));
        }

        private static BasicValue basic(final Origin v) {
            return v.size == 2 ? BasicValue.LONG_VALUE : BasicValue.REFERENCE_VALUE;
        }

        @Override
        public Origin newValue(final Type type) {
            return unknown(basic.newValue(type));
        }

        @Override
        public Origin newParameterValue(final boolean isInstanceMethod, final int local, final Type type) {
            if (local == 0 && isInstanceMethod) {
                return new Origin(1, Set.of(thisOrigin));
            }
            if (local == 0 && accessorOf != null && type.getDescriptor().equals("L" + accessorOf + ";")) {
                return new Origin(1, Set.of(SELF)); // javac passes this$0 to an accessor
            }
            return newValue(type);
        }

        @Override
        public Origin newOperation(final AbstractInsnNode insn) throws AnalyzerException {
            return unknown(basic.newOperation(insn));
        }

        @Override
        public Origin copyOperation(final AbstractInsnNode insn, final Origin value) {
            return value;
        }

        @Override
        public Origin unaryOperation(final AbstractInsnNode insn, final Origin value) throws AnalyzerException {
            final Origin v = unknown(basic.unaryOperation(insn, basic(value)));
            if (insn.getOpcode() == Opcodes.GETFIELD && v != null) {
                final String name = ((FieldInsnNode) insn).name;
                if (value.isSelf()) {
                    return new Origin(v.size, Set.of(FIELD + name));
                }
                if (value.origins.equals(Set.of(INNER)) && name.equals("this$0")) {
                    return new Origin(v.size, Set.of(SELF));
                }
            }
            return v;
        }

        @Override
        public Origin binaryOperation(final AbstractInsnNode insn, final Origin a, final Origin b)
                throws AnalyzerException {
            return unknown(basic.binaryOperation(insn, basic(a), basic(b)));
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
            return unknown(basic.naryOperation(insn, args));
        }

        @Override
        public void returnOperation(final AbstractInsnNode insn, final Origin value, final Origin expected) {}

        @Override
        public Origin merge(final Origin a, final Origin b) {
            if (a.equals(b)) {
                return a;
            }
            final Set<String> union = new HashSet<>(a.origins);
            union.addAll(b.origins);
            return new Origin(Math.min(a.size, b.size), Set.copyOf(union));
        }
    }
}
