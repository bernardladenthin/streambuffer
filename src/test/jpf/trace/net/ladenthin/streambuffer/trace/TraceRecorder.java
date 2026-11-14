// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import gov.nasa.jpf.vm.Verify;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * The tracer of A6 for Java PathFinder (roadmap A18), with the API of {@code
 * src/test/java/.../trace/TraceRecorder.java}, which the instrumented class calls. Instead of one
 * global lock it logs in a JPF atomic block, so the tracer adds no state of its own. Every access
 * keeps exactly one scheduling point, a {@code Thread.yield()} before its block (JPF breaks the
 * transition there, {@code cg.threads.break_yield}), so the interleavings of the accesses are all
 * still explored; the access and its log line are one step, as under the global lock.
 *
 * <p>Compiled only for JPF (with {@code jpf-classes.jar}), in place of the JVM's tracer.
 */
public final class TraceRecorder {

    /** One event: the thread, the site (method, access and its ordinal), and a value. */
    public static final class Event {
        /** The name of the thread. */
        public final String thread;
        /** The site, e.g. {@code waitForAtLeast.getAvail#0}, or a harness event. */
        public final String site;
        /** The value read or written, or 0. */
        public final long value;
        /** The bytes of a harness event (a completed read), else empty. */
        public final List<Integer> bytes;

        Event(String thread, String site, long value, List<Integer> bytes) {
            this.thread = thread;
            this.site = site;
            this.value = value;
            this.bytes = bytes;
        }
    }

    private static final List<Event> EVENTS = new ArrayList<>();

    private static boolean recording;

    private TraceRecorder() {}

    /**
     * Starts a recording.
     *
     * @param newSeed ignored (no yields of its own under JPF)
     * @param newYieldPer256 ignored
     */
    public static void start(long newSeed, int newYieldPer256) {
        Verify.beginAtomic();
        EVENTS.clear();
        recording = true;
        Verify.endAtomic();
    }

    /**
     * Stops the recording.
     *
     * @return the events in the order they happened
     */
    public static List<Event> stop() {
        Verify.beginAtomic();
        recording = false;
        final List<Event> events = Collections.unmodifiableList(new ArrayList<>(EVENTS));
        Verify.endAtomic();
        return events;
    }

    private static void add(String site, long value, List<Integer> bytes) {
        if (recording) {
            EVENTS.add(new Event(Thread.currentThread().getName(), site, value, bytes));
        }
    }

    /** Before a non-blocking access: the scheduling point, then the atomic block. */
    public static void begin() {
        Thread.yield();
        Verify.beginAtomic();
    }

    /**
     * After a non-blocking access of a long: logs it, ends the block.
     *
     * @param value the value read or returned
     * @param site the site
     */
    public static void endLong(long value, String site) {
        add(site, value, Collections.<Integer>emptyList());
        Verify.endAtomic();
    }

    /**
     * After a non-blocking access of an int or boolean.
     *
     * @param value the value (a boolean as 0 or 1)
     * @param site the site
     */
    public static void endInt(int value, String site) {
        endLong(value, site);
    }

    /**
     * Within a block, before a write of a long: logs the value.
     *
     * @param value the value to be written
     * @param site the site
     */
    public static void logLong(long value, String site) {
        add(site, value, Collections.<Integer>emptyList());
    }

    /**
     * Within a block, before a write of an int or boolean.
     *
     * @param value the value (a boolean as 0 or 1)
     * @param site the site
     */
    public static void logInt(int value, String site) {
        logLong(value, site);
    }

    /**
     * Within a block, before a call without a result.
     *
     * @param site the site
     */
    public static void log(String site) {
        add(site, 0, Collections.<Integer>emptyList());
    }

    /** After a non-blocking access: ends the block. */
    public static void end() {
        Verify.endAtomic();
    }

    /**
     * A blocking access just returned, or a release is about to happen.
     *
     * @param site the site
     */
    public static void event(String site) {
        Thread.yield();
        Verify.beginAtomic();
        add(site, 0, Collections.<Integer>emptyList());
        Verify.endAtomic();
    }

    /**
     * A harness event (a call returned).
     *
     * @param site the event
     * @param value its value
     * @param bytes the bytes a read returned, else empty
     */
    public static void harness(String site, long value, List<Integer> bytes) {
        Thread.yield();
        Verify.beginAtomic();
        add(site, value, Collections.unmodifiableList(new ArrayList<>(bytes)));
        Verify.endAtomic();
    }
}
