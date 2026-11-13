// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer.trace;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.concurrent.locks.ReentrantLock;

/**
 * The tracer the instrumented {@code StreamBuffer} calls (roadmap A6). Every access to shared
 * state that {@link TracingClassLoader} rewrote runs between {@link #begin()} and one of the
 * {@code end} methods, under one global lock, so the order of the events is the order in which
 * the accesses happened. A blocking access (a monitor enter, {@code lock()}, the return from
 * {@code await()}) is logged right after it, a release right before it, with {@link #event}.
 *
 * <p>Static because the rewritten bytecode calls it with {@code invokestatic}; this class is
 * loaded by the application class loader, which the tracing loader delegates to, so the
 * instrumented class and the test share one instance of its state.
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

        @Override
        public String toString() {
            return thread + " " + site + " " + value + (bytes.isEmpty() ? "" : " " + bytes);
        }
    }

    private static final ReentrantLock GLOBAL = new ReentrantLock();

    private static final List<Event> EVENTS = new ArrayList<>();

    private static volatile boolean recording;

    /** The probability (in 1/256) of a yield before an access; 0 = none. */
    private static volatile int yieldPer256;

    private static final ThreadLocal<Random> RANDOM = new ThreadLocal<>();

    private static volatile long seed;

    private TraceRecorder() {}

    /**
     * Starts a recording: clears the events.
     *
     * @param newSeed the seed of the yields (each thread derives its own from it and its name)
     * @param newYieldPer256 the probability of a yield before an access, in 1/256
     */
    public static void start(long newSeed, int newYieldPer256) {
        GLOBAL.lock();
        try {
            EVENTS.clear();
            seed = newSeed;
            yieldPer256 = newYieldPer256;
            recording = true;
        } finally {
            GLOBAL.unlock();
        }
    }

    /**
     * Stops the recording.
     *
     * @return the events in the order they happened
     */
    public static List<Event> stop() {
        GLOBAL.lock();
        try {
            recording = false;
            return Collections.unmodifiableList(new ArrayList<>(EVENTS));
        } finally {
            GLOBAL.unlock();
        }
    }

    private static void maybeYield() {
        final int p = yieldPer256;
        if (p == 0) {
            return;
        }
        Random r = RANDOM.get();
        if (r == null) {
            r = new Random(seed ^ Thread.currentThread().getName().hashCode());
            RANDOM.set(r);
        }
        if (r.nextInt(256) < p) {
            Thread.yield();
        }
    }

    private static void add(String site, long value, List<Integer> bytes) {
        if (recording) {
            EVENTS.add(new Event(Thread.currentThread().getName(), site, value, bytes));
        }
    }

    /** Before a non-blocking access: takes the global lock. */
    public static void begin() {
        maybeYield();
        GLOBAL.lock();
    }

    /**
     * After a non-blocking access of a long: logs it, releases the global lock.
     *
     * @param value the value read or returned
     * @param site the site
     */
    public static void endLong(long value, String site) {
        try {
            add(site, value, Collections.emptyList());
        } finally {
            GLOBAL.unlock();
        }
    }

    /**
     * After a non-blocking access of an int or boolean: logs it, releases the global lock.
     *
     * @param value the value read or returned (a boolean as 0 or 1)
     * @param site the site
     */
    public static void endInt(int value, String site) {
        endLong(value, site);
    }

    /**
     * Within a non-blocking access, before a write of a long: logs the value (the global lock is
     * held; {@link #end()} releases it after the write).
     *
     * @param value the value to be written
     * @param site the site
     */
    public static void logLong(long value, String site) {
        add(site, value, Collections.emptyList());
    }

    /**
     * Within a non-blocking access, before a write of an int or boolean: logs the value.
     *
     * @param value the value to be written (a boolean as 0 or 1)
     * @param site the site
     */
    public static void logInt(int value, String site) {
        logLong(value, site);
    }

    /**
     * Within a non-blocking access, before a call without a result: logs the site.
     *
     * @param site the site
     */
    public static void log(String site) {
        add(site, 0, Collections.emptyList());
    }

    /** After a non-blocking access: releases the global lock. */
    public static void end() {
        GLOBAL.unlock();
    }

    /**
     * A blocking access just returned, or a release is about to happen: logs the site on its own.
     *
     * @param site the site
     */
    public static void event(String site) {
        maybeYield();
        GLOBAL.lock();
        try {
            add(site, 0, Collections.emptyList());
        } finally {
            GLOBAL.unlock();
        }
    }

    /**
     * A harness event of the test (a call returned), logged in the same order as the accesses.
     *
     * @param site the event, e.g. {@code ret}
     * @param value its value
     * @param bytes the bytes a read returned, else empty
     */
    public static void harness(String site, long value, List<Integer> bytes) {
        GLOBAL.lock();
        try {
            add(site, value, Collections.unmodifiableList(new ArrayList<>(bytes)));
        } finally {
            GLOBAL.unlock();
        }
    }
}
