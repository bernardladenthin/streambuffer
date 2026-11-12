// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.HashMap;
import java.util.Map;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

/**
 * Loads {@code StreamBuffer} and its inner classes itself (child first) and rewrites every access
 * to the state the TLA+ model has into calls of {@link TraceRecorder} (roadmap A6). The source and
 * the shipped classes stay as they are; only the copy in this loader is instrumented.
 *
 * <p>Sites: {@code <method>.<access>#<ordinal>}, the ordinal counting that access in that method
 * in bytecode order. Accesses: {@code getAvail}/{@code putAvail} ({@code availableBytes}),
 * {@code getClosed}/{@code putClosed} ({@code streamClosed}), {@code waitersGet},
 * {@code waitersInc}, {@code waitersDec} ({@code waitingReaders}), {@code enter}/{@code exit}
 * ({@code bufferLock}, the only monitor), {@code wlock}/{@code wunlock} ({@code waitLock}),
 * {@code park}/{@code unpark} (before and after {@code modified.await()}) and {@code signalAll}.
 */
public final class TracingClassLoader extends ClassLoader {

    private static final String SB = "net/ladenthin/streambuffer/StreamBuffer";

    private static final String REC = "net/ladenthin/streambuffer/trace/TraceRecorder";

    /** Creates the loader; it delegates every class but {@code StreamBuffer*} to its parent. */
    public TracingClassLoader() {
        super(TracingClassLoader.class.getClassLoader());
    }

    @Override
    protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
        if (!name.equals(SB.replace('/', '.')) && !name.startsWith(SB.replace('/', '.') + "$")) {
            return super.loadClass(name, resolve);
        }
        synchronized (getClassLoadingLock(name)) {
            Class<?> c = findLoadedClass(name);
            if (c == null) {
                final byte[] original = read(name.replace('.', '/') + ".class");
                final byte[] rewritten = instrument(original);
                c = defineClass(name, rewritten, 0, rewritten.length);
            }
            if (resolve) {
                resolveClass(c);
            }
            return c;
        }
    }

    private static byte[] read(String resource) {
        try (InputStream in = TracingClassLoader.class.getClassLoader().getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException("not found: " + resource);
            }
            final ByteArrayOutputStream out = new ByteArrayOutputStream();
            final byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) {
                out.write(b, 0, n);
            }
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Rewrites one class file.
     *
     * @param classFile the original class file
     * @return the instrumented class file
     */
    static byte[] instrument(byte[] classFile) {
        final ClassReader reader = new ClassReader(classFile);
        final ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        reader.accept(
                new ClassVisitor(Opcodes.ASM9, writer) {
                    @Override
                    public MethodVisitor visitMethod(
                            int access, String name, String descriptor, String signature, String[] exceptions) {
                        final MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
                        return new Rewriter(mv, name);
                    }
                },
                0);
        return writer.toByteArray();
    }

    /** Rewrites the accesses of one method. */
    private static final class Rewriter extends MethodVisitor {

        private final String method;

        private final Map<String, Integer> ordinals = new HashMap<>();

        Rewriter(MethodVisitor mv, String method) {
            super(Opcodes.ASM9, mv);
            this.method = method;
        }

        private String site(String access) {
            final int n = ordinals.merge(access, 1, Integer::sum) - 1;
            return method + "." + access + "#" + n;
        }

        private void rec(String name, String descriptor) {
            super.visitMethodInsn(Opcodes.INVOKESTATIC, REC, name, descriptor, false);
        }

        @Override
        public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
            final boolean avail = owner.equals(SB) && name.equals("availableBytes");
            final boolean closed = owner.equals(SB) && name.equals("streamClosed");
            if (!avail && !closed) {
                super.visitFieldInsn(opcode, owner, name, descriptor);
                return;
            }
            final String what = avail ? "Avail" : "Closed";
            if (opcode == Opcodes.GETFIELD) {
                final String s = site("get" + what);
                rec("begin", "()V");
                super.visitFieldInsn(opcode, owner, name, descriptor);
                if (avail) {
                    super.visitInsn(Opcodes.DUP2);
                    super.visitLdcInsn(s);
                    rec("endLong", "(JLjava/lang/String;)V");
                } else {
                    super.visitInsn(Opcodes.DUP);
                    super.visitLdcInsn(s);
                    rec("endInt", "(ILjava/lang/String;)V");
                }
            } else if (opcode == Opcodes.PUTFIELD) {
                final String s = site("put" + what);
                rec("begin", "()V");
                if (avail) {
                    super.visitInsn(Opcodes.DUP2);
                    super.visitLdcInsn(s);
                    rec("logLong", "(JLjava/lang/String;)V");
                } else {
                    super.visitInsn(Opcodes.DUP);
                    super.visitLdcInsn(s);
                    rec("logInt", "(ILjava/lang/String;)V");
                }
                super.visitFieldInsn(opcode, owner, name, descriptor);
                rec("end", "()V");
            } else {
                throw new IllegalStateException("unexpected access to " + name + " in " + method);
            }
        }

        @Override
        public void visitInsn(int opcode) {
            if (opcode == Opcodes.MONITORENTER) {
                super.visitInsn(opcode);
                super.visitLdcInsn(site("enter"));
                rec("event", "(Ljava/lang/String;)V");
            } else if (opcode == Opcodes.MONITOREXIT) {
                super.visitLdcInsn(site("exit"));
                rec("event", "(Ljava/lang/String;)V");
                super.visitInsn(opcode);
            } else {
                super.visitInsn(opcode);
            }
        }

        @Override
        public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean isInterface) {
            if (owner.equals("java/util/concurrent/atomic/AtomicInteger")
                    && (name.equals("get") || name.equals("incrementAndGet") || name.equals("decrementAndGet"))) {
                final String s = site(
                        name.equals("get")
                                ? "waitersGet"
                                : name.equals("incrementAndGet") ? "waitersInc" : "waitersDec");
                rec("begin", "()V");
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                super.visitInsn(Opcodes.DUP);
                super.visitLdcInsn(s);
                rec("endInt", "(ILjava/lang/String;)V");
            } else if (owner.equals("java/util/concurrent/locks/ReentrantLock")
                    && (name.equals("lock") || name.equals("lockInterruptibly"))) {
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                super.visitLdcInsn(site("wlock"));
                rec("event", "(Ljava/lang/String;)V");
            } else if (owner.equals("java/util/concurrent/locks/ReentrantLock") && name.equals("unlock")) {
                super.visitLdcInsn(site("wunlock"));
                rec("event", "(Ljava/lang/String;)V");
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
            } else if (owner.equals("java/util/concurrent/locks/Condition")
                    && name.equals("await")
                    && descriptor.equals("()V")) {
                super.visitLdcInsn(site("park"));
                rec("event", "(Ljava/lang/String;)V");
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                super.visitLdcInsn(site("unpark"));
                rec("event", "(Ljava/lang/String;)V");
            } else if (owner.equals("java/util/concurrent/locks/Condition") && name.equals("signalAll")) {
                final String s = site("signalAll");
                rec("begin", "()V");
                super.visitLdcInsn(s);
                rec("log", "(Ljava/lang/String;)V");
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                rec("end", "()V");
            } else {
                super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
            }
        }
    }
}
