// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.util.Arrays;
import java.util.List;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;

/**
 * Defects put into {@code StreamBuffer}'s class file before it is instrumented: the negative
 * controls of the trace validation (A6, {@code trace-controls.sh}) and of the check of every
 * interleaving (A18, {@code check-graph.sh}). A check that accepts the defective class shows that
 * the link from the code to the model does not see that kind of defect, so each must be rejected.
 *
 * <ul>
 *   <li>{@code no-decrement}: the reads no longer lower {@code availableBytes} (a wrong count);
 *   <li>{@code no-write-signal}: a write never calls {@code signalModification()}, so a reader
 *       waiting for it is woken only by the close (a lost wake-up). Every scenario has a closer, so
 *       the runs still end; before the signal steps were tied to the code's lines ({@code
 *       TraceStreamBuffer.tla}, {@code SignalAt}) the model took the writer's signal where the
 *       code had none, and such traces were accepted.
 * </ul>
 */
public final class TraceMutants {

    /** The defects, by name. */
    public static final List<String> NAMES = Arrays.asList("no-decrement", "no-write-signal");

    private static final String SB = "net/ladenthin/streambuffer/StreamBuffer";

    private TraceMutants() {}

    /**
     * Puts a defect into a class file.
     *
     * @param mutant the defect, one of {@link #NAMES}, or {@code null} for none
     * @param name the internal name of the class ({@code net/ladenthin/streambuffer/StreamBuffer}
     *     or one of its inner classes, which no defect changes)
     * @param classFile the class file
     * @return the class file with the defect
     * @throws IllegalArgumentException for an unknown defect
     * @throws IllegalStateException if the code the defect changes is not found
     */
    public static byte[] apply(String mutant, String name, byte[] classFile) {
        if (mutant == null) {
            return classFile;
        }
        if (!NAMES.contains(mutant)) {
            throw new IllegalArgumentException("unknown mutant " + mutant + ", known: " + NAMES);
        }
        if (!name.equals(SB)) {
            return classFile;
        }
        return mutant.equals("no-decrement") ? noDecrement(classFile) : noWriteSignal(classFile);
    }

    /**
     * In {@code readSingleByte} and {@code readIntoArray}, every {@code lsub} right before the store
     * of {@code availableBytes} becomes {@code pop2}: the count is written back unchanged, on both
     * read paths, so the control fails for every kind of reader.
     */
    private static byte[] noDecrement(byte[] classFile) {
        final ClassNode node = read(classFile);
        int done = 0;
        for (MethodNode m : node.methods) {
            if (!m.name.equals("readSingleByte") && !m.name.equals("readIntoArray")) {
                continue;
            }
            for (AbstractInsnNode insn : m.instructions.toArray()) {
                final AbstractInsnNode next = insn.getNext();
                if (insn.getOpcode() == Opcodes.LSUB
                        && next instanceof FieldInsnNode
                        && next.getOpcode() == Opcodes.PUTFIELD
                        && ((FieldInsnNode) next).name.equals("availableBytes")) {
                    m.instructions.set(insn, new InsnNode(Opcodes.POP2));
                    done++;
                }
            }
        }
        if (done < 2) {
            throw new IllegalStateException(
                    "expected the decrement of availableBytes in both read methods, found " + done);
        }
        return write(node);
    }

    /**
     * In {@code writeFromArray}, the call of {@code signalModification()} becomes {@code pop} (of
     * the receiver it was given): the write commits its bytes and never wakes a waiting reader. The
     * close still signals. Every write of the stream goes through {@code writeFromArray}.
     */
    private static byte[] noWriteSignal(byte[] classFile) {
        final ClassNode node = read(classFile);
        int done = 0;
        for (MethodNode m : node.methods) {
            if (!m.name.equals("writeFromArray")) {
                continue;
            }
            for (AbstractInsnNode insn : m.instructions.toArray()) {
                if (insn instanceof MethodInsnNode
                        && ((MethodInsnNode) insn).owner.equals(SB)
                        && ((MethodInsnNode) insn).name.equals("signalModification")
                        && ((MethodInsnNode) insn).desc.equals("()V")) {
                    m.instructions.set(insn, new InsnNode(Opcodes.POP));
                    done++;
                }
            }
        }
        if (done != 1) {
            throw new IllegalStateException(
                    "expected one call of signalModification() in writeFromArray, found " + done);
        }
        return write(node);
    }

    private static ClassNode read(byte[] classFile) {
        final ClassNode node = new ClassNode();
        new ClassReader(classFile).accept(node, 0);
        return node;
    }

    private static byte[] write(ClassNode node) {
        final ClassWriter w = new ClassWriter(0);
        node.accept(w);
        return w.toByteArray();
    }
}
