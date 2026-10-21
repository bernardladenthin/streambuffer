// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import com.google.errorprone.annotations.concurrent.GuardedBy;
import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicLong;

/**
 * A stream buffer is a class to buffer data that has been written to an
 * {@link OutputStream} and provide the data in an {@link InputStream}. There is
 * no need to close the stream before read. The read works during a write
 * process. It is possible to call concurrent a method in the
 * {@link OutputStream} and {@link InputStream}. Read/Write at the same time.
 *
 * @author Bernard Ladenthin bernard.ladenthin@gmail.com
 */
public class StreamBuffer implements Closeable {

    static final String EXCEPTION_MESSAGE_VALIDATE_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION =
            "Invalid offset or length given to validateOffsetAndLengthToWrite.";

    /**
     * Largest {@code byte[]} length this class allocates: {@code Integer.MAX_VALUE - 8}.
     * Same value as {@code jdk.internal.util.ArraysSupport.SOFT_MAX_ARRAY_LENGTH}, mirrored
     * because that class is JDK-internal (not exported, absent on Java 8).
     * Reason: VMs reserve array header words; HotSpot rejects {@code Integer.MAX_VALUE} and
     * {@code Integer.MAX_VALUE - 1} with "Requested array size exceeds VM limit", on any heap size.
     */
    static final int MAX_ARRAY_LENGTH = Integer.MAX_VALUE - 8;

    /**
     * An object to get an unique access to the {@link #buffer}. It is needed to
     * get an exclusive access for read and write operations.
     */
    private final Object bufferLock = new Object();

    /**
     * The buffer which contains the raw data.
     */
    @GuardedBy("bufferLock")
    private final Deque<byte[]> buffer = new ArrayDeque<>();

    /**
     * A {@link Semaphore} to signal that data are added to the {@link #buffer}.
     * This signal is also used to announce that the stream was closed.
     * This {@link Semaphore} is used only for internal communication.
     */
    private final Semaphore signalModification = new Semaphore(0);

    /**
     * List of external {@link Semaphore} signals to be released on modifications.
     * Uses {@link CopyOnWriteArrayList} for thread-safe iteration without locks.
     * Each registered semaphore is released using the same "max 1 permit" pattern
     * as the internal {@link #signalModification} semaphore, enabling thread-decoupled
     * notification where the observer blocks on its own semaphore in its own thread.
     */
    private final CopyOnWriteArrayList<Semaphore> signals = new CopyOnWriteArrayList<>();

    /**
     * Observers notified when trim() starts executing.
     * Uses {@link CopyOnWriteArrayList} for thread-safe iteration.
     * Each registered semaphore is released when trim begins.
     */
    private final CopyOnWriteArrayList<Semaphore> trimStartSignals = new CopyOnWriteArrayList<>();

    /**
     * Observers notified when trim() completes executing.
     * Uses {@link CopyOnWriteArrayList} for thread-safe iteration.
     * Each registered semaphore is released when trim ends.
     */
    private final CopyOnWriteArrayList<Semaphore> trimEndSignals = new CopyOnWriteArrayList<>();

    /**
     * A variable for the current position of the current element in the
     * {@link #buffer}.
     */
    private volatile int positionAtCurrentBufferEntry = 0;

    /**
     * The sum of available bytes.
     */
    private volatile long availableBytes = 0;

    /**
     * A flag to indicate the stream was closed.
     */
    private volatile boolean streamClosed = false;

    /**
     * A flag to enable a safe write. If safe write is enabled, modifiable byte
     * arrays are cloned before they are written (put) into the FIFO. Benefit:
     * It cost more performance to clone a byte array, but the content is
     * immutable. Internally created arrays that never escape (see
     * {@link #writeSingleByte(int)}) are not cloned.
     */
    private volatile boolean safeWrite = false;

    /**
     * The maximum buffer elements. A number of maximum elements to invoke the
     * trim method. If the buffer contains more elements as the maximum, the
     * buffer will be completely reduced to one element. This option can help to
     * improve the performance for a read of huge amount data. It can also help
     * to shrink the size of the memory used. Use a value lower or equals
     * <code>0</code> to disable the trim option. Default is a maximum of
     * <code>100</code> elements.
     */
    private volatile int maxBufferElements = 100;

    /**
     * Peak value of availableBytes ever observed. Updated under bufferLock, read as volatile.
     */
    private volatile long maxObservedBytes = 0;

    /**
     * Cumulative bytes written by the user (excludes internal trim operations).
     * Uses {@link AtomicLong} because {@code x += len} on a plain {@code volatile} is
     * non-atomic (read-modify-write) and would lose updates under concurrent writers.
     */
    private final AtomicLong totalBytesWritten = new AtomicLong();

    /**
     * Cumulative bytes consumed by user reads and skips (excludes internal trim operations).
     * See {@link #totalBytesWritten} for the rationale.
     */
    private final AtomicLong totalBytesRead = new AtomicLong();

    /**
     * Maximum size of a single byte array during consolidation. Default {@link #MAX_ARRAY_LENGTH}.
     */
    private volatile long maxAllocationSize = MAX_ARRAY_LENGTH;

    /**
     * Flag set to true while trim is rearranging internal buffers.
     * Volatile so it's visible to all threads; {@link #isTrimRunning()} exposes it.
     * Set to true at start of trim body, set to false in finally block.
     * Trim itself copies straight from the FIFO and never reads or writes through the
     * streams. The flag matters for code that runs on the trim thread while trim is in
     * progress: a trim signal whose {@code release()} writes reaches the write path again
     * (bufferLock is reentrant), and must not start a nested trim (see
     * {@link #shouldTrim()}). Such I/O is user I/O and is counted in the statistics.
     */
    private volatile boolean isTrimRunning = false;

    private final SBInputStream is = new SBInputStream();
    private final SBOutputStream os = new SBOutputStream();

    /**
     * Construct a new {@link StreamBuffer}.
     */
    public StreamBuffer() {
        signals.add(signalModification);
    }

    /**
     * Returns the flag which indicates whether write operations are executed
     * safe or unsafe.
     *
     * @return <code>true</code> if the safe write option is enabled, otherwise
     * <code>false</code>.
     */
    public boolean isSafeWrite() {
        return safeWrite;
    }

    /**
     * Set a secure or unsecure write operation.
     *
     * @param safeWrite A flag to enable a safe write. If safe write is enabled,
     * modifiable byte arrays are cloned before they are written. Benefit: It
     * cost more performance to clone a byte array, but it is hardened to
     * external changes. Use <code>true</code> to force a clone. Otherwise use
     * <code>false</code> (default).
     */
    public void setSafeWrite(boolean safeWrite) {
        this.safeWrite = safeWrite;
    }

    /**
     * Returns the number of maximum elements which are held in maximum memory.
     *
     * @return the number of elements.
     */
    public int getMaxBufferElements() {
        return maxBufferElements;
    }

    /**
     * Set maximum elements for the buffer. Change the value doesn't invoke a
     * trim call if the buffer contains more elements. Only write operations
     * force a trim call.
     *
     * @param maxBufferElements number of maximum elements.
     */
    public void setMaxBufferElements(int maxBufferElements) {
        this.maxBufferElements = maxBufferElements;
    }

    /**
     * Returns the cumulative number of bytes written by user I/O operations.
     * Excludes bytes read/written during internal {@link #trim()} operations.
     *
     * @return total bytes written.
     */
    public long getTotalBytesWritten() {
        return totalBytesWritten.get();
    }

    /**
     * Returns the cumulative number of bytes read by user I/O operations.
     * Excludes bytes read/written during internal {@link #trim()} operations.
     *
     * @return total bytes read.
     */
    public long getTotalBytesRead() {
        return totalBytesRead.get();
    }

    /**
     * Returns the exact number of bytes currently buffered.
     *
     * <p>Unlike {@link SBInputStream#available()}, which is clamped to
     * {@link Integer#MAX_VALUE} to honour the {@link InputStream#available()}
     * contract, this method returns the full {@code long} count and is therefore
     * the correct accessor when the buffer holds more than 2 GB.</p>
     *
     * <p>The value reflects a single volatile read and may be stale by the time
     * the caller acts on it; concurrent writes or reads can change it
     * immediately after this method returns.</p>
     *
     * @return the number of buffered bytes (never negative)
     */
    public long getAvailableBytesExact() {
        return availableBytes;
    }

    /**
     * Returns the peak value of available bytes ever observed.
     *
     * @return maximum observed available bytes.
     */
    public long getMaxObservedBytes() {
        return maxObservedBytes;
    }

    /**
     * Returns the maximum size of a single byte array allocated during trim.
     *
     * @return maximum allocation size.
     */
    public long getMaxAllocationSize() {
        return maxAllocationSize;
    }

    /**
     * Set the maximum size of a single byte array allocated during {@link #trim()}.
     * When trim consolidates the buffer, it splits data into chunks respecting
     * this limit. Default is {@link #MAX_ARRAY_LENGTH} ({@code Integer.MAX_VALUE - 8});
     * larger values are clamped to it.
     *
     * @param maxSize maximum allocation size in bytes. Must be positive.
     * @throws IllegalArgumentException if maxSize is not positive.
     */
    public void setMaxAllocationSize(final long maxSize) {
        if (maxSize <= 0) {
            throw new IllegalArgumentException("maxAllocationSize must be positive but was " + maxSize);
        }
        this.maxAllocationSize = Math.min(maxSize, MAX_ARRAY_LENGTH);
    }

    /**
     * Returns whether {@link #trim()} is currently running.
     * This can be used to determine if the buffer is in the middle of consolidation.
     * <strong>Note:</strong> This value can change at any time in concurrent scenarios.
     * The caller must not rely on this value remaining constant between method calls.
     *
     * @return {@code true} if trim is currently executing, {@code false} otherwise.
     */
    public boolean isTrimRunning() {
        return isTrimRunning;
    }

    /**
     * Returns the current number of byte arrays in the internal queue.
     * <strong>Note:</strong> This value can change at any time in concurrent scenarios
     * due to {@link java.io.OutputStream#write(int)} / {@link java.io.InputStream#read()} operations or {@link #trim()} consolidation.
     * The caller must not rely on this value remaining constant between method calls.
     *
     * @return the number of byte arrays currently in the queue.
     */
    public int getBufferElementCount() {
        synchronized (bufferLock) {
            return buffer.size();
        }
    }

    /**
     * Register an external {@link Semaphore} to be released when the buffer is
     * modified (data written or stream closed). The semaphore uses the same
     * "max 1 permit" pattern as the internal signaling: a permit is released
     * only if the semaphore currently has zero permits. This enables
     * thread-decoupled notification where the observer blocks on its own
     * semaphore in its own thread.
     *
     * @param semaphore the semaphore to register
     * @throws NullPointerException if semaphore is null
     */
    public void addSignal(Semaphore semaphore) {
        if (semaphore == null) {
            throw new NullPointerException(
                    "Semaphore cannot be null (addSignal; " + signals.size() + " signal(s) already registered)");
        }
        signals.add(semaphore);
    }

    /**
     * Remove a previously registered external {@link Semaphore} from the
     * signal list.
     *
     * @param semaphore the semaphore to remove
     * @return <code>true</code> if the semaphore was found and removed, otherwise <code>false</code>
     */
    public boolean removeSignal(Semaphore semaphore) {
        return signals.remove(semaphore);
    }

    /**
     * Register an external {@link Semaphore} to be released when trim() starts.
     * The semaphore uses the same "max 1 permit" pattern as modification signals.
     * It is released under the buffer lock: a {@code release()} override must return promptly and
     * must not wait for a read, write or {@link #close()} of this buffer (see {@link #close()}).
     *
     * @param semaphore the semaphore to register for trim start events
     * @throws NullPointerException if semaphore is null
     */
    public void addTrimStartSignal(Semaphore semaphore) {
        if (semaphore == null) {
            throw new NullPointerException("Semaphore cannot be null (addTrimStartSignal; " + trimStartSignals.size()
                    + " trim-start signal(s) already registered)");
        }
        trimStartSignals.add(semaphore);
    }

    /**
     * Remove a previously registered trim start semaphore.
     *
     * @param semaphore the semaphore to remove
     * @return true if the semaphore was found and removed, otherwise false
     */
    public boolean removeTrimStartSignal(Semaphore semaphore) {
        return trimStartSignals.remove(semaphore);
    }

    /**
     * Register an external {@link Semaphore} to be released when trim() completes.
     * The semaphore uses the same "max 1 permit" pattern as modification signals.
     * It is released under the buffer lock: a {@code release()} override must return promptly and
     * must not wait for a read, write or {@link #close()} of this buffer (see {@link #close()}).
     *
     * @param semaphore the semaphore to register for trim end events
     * @throws NullPointerException if semaphore is null
     */
    public void addTrimEndSignal(Semaphore semaphore) {
        if (semaphore == null) {
            throw new NullPointerException("Semaphore cannot be null (addTrimEndSignal; " + trimEndSignals.size()
                    + " trim-end signal(s) already registered)");
        }
        trimEndSignals.add(semaphore);
    }

    /**
     * Remove a previously registered trim end semaphore.
     *
     * @param semaphore the semaphore to remove
     * @return true if the semaphore was found and removed, otherwise false
     */
    public boolean removeTrimEndSignal(Semaphore semaphore) {
        return trimEndSignals.remove(semaphore);
    }

    /**
     * Security check mostly copied from {@link InputStream#read(byte[], int, int)}.
     * Ensures the parameter are valid.
     * @param b the byte array to copy from
     * @param off the offset to read from the array
     * @param len the len of the bytes to read from the array
     * @return <code>true</code> if there are bytes to read, otherwise <code>false</code>
     * @throws NullPointerException if the array is null
     * @throws IndexOutOfBoundsException if the index is not correct
     */
    public static boolean validateOffsetAndLengthToRead(byte[] b, int off, int len) {
        if (b == null) {
            throw new NullPointerException();
        } else if (off < 0 || len < 0 || len > b.length - off) {
            throw new IndexOutOfBoundsException();
        } else if (len == 0) {
            return false;
        }
        return true;
    }

    /**
     * Security check mostly copied from {@link OutputStream#write(byte[], int, int)}.
     * Ensures the parameter are valid.
     * @param b the byte array to write to the array
     * @param off the offset to write to the array
     * @param len the len of the bytes to write to the array
     * @return <code>true</code> if there are bytes to write, otherwise <code>false</code>
     * @throws NullPointerException if the array is null
     * @throws IndexOutOfBoundsException if the offset or length is not invalid
     */
    public static boolean validateOffsetAndLengthToWrite(byte[] b, int off, int len) {
        // Manual null check (not Objects.requireNonNull) so OpenJML ESC can discharge the
        // exceptional_behavior 'signals_only NullPointerException' obligation: under the spec
        // file's nullable_by_default, the bundled Objects.requireNonNull contract leaves an
        // unprovable ExceptionList goal. Behaviourally identical — same type, same message.
        if (b == null) {
            throw new NullPointerException("validateOffsetAndLengthToWrite: byte array b must not be null");
        }
        if ((off < 0) || (off > b.length) || (len < 0) || ((off + len) > b.length) || ((off + len) < 0)) {
            throw newInvalidOffsetOrLengthToWriteException(b.length, off, len);
        } else if (len == 0) {
            return false;
        }
        return true;
    }

    /**
     * Builds the {@link IndexOutOfBoundsException} thrown by
     * {@link #validateOffsetAndLengthToWrite(byte[], int, int)}.
     *
     * <p>Extracted into its own method so the OpenJML ESC proof of the validator does not
     * have to reason about string concatenation (the desugared {@code StringBuilder} chain
     * sends the SMT solver into an "unknown" verdict). The builder carries an
     * <em>assumed</em>, not proven, contract in the specification file
     * ({@code src/main/jml/net/ladenthin/streambuffer/StreamBuffer.jml}): it terminates
     * normally, has no side effects and returns a non-null exception. That assumption is
     * exercised dynamically by the RAC test run and the unit tests.</p>
     *
     * @param arrayLength the length of the byte array that failed validation
     * @param off the offset that failed validation
     * @param len the length that failed validation
     * @return a new {@link IndexOutOfBoundsException} with a diagnostic message
     */
    private static IndexOutOfBoundsException newInvalidOffsetOrLengthToWriteException(
            final int arrayLength, final int off, final int len) {
        return new IndexOutOfBoundsException(
                EXCEPTION_MESSAGE_VALIDATE_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION + " (b.length="
                        + arrayLength + ", off=" + off + ", len=" + len + ")");
    }

    /**
     * Call this method always after all changes are synchronized. This method
     * signals a modification. It could be a write on the stream or a close.
     */
    private void signalModification() {
        // release all registered signals (including the internal one) using the max 1 permit pattern
        for (Semaphore signal : signals) {
            if (signal.availablePermits() == 0) {
                signal.release();
            }
        }
    }

    /**
     * This method trims the buffer. This method can be invoked after every
     * write operation. The method checks itself if the buffer should be trimmed
     * or not.
     * <strong>MUST be called inside {@code synchronized(bufferLock)}.</strong>
     * Sets the {@link #isTrimRunning} volatile flag while it runs. The buffered byte count
     * ({@link #availableBytes}) stays constant throughout.
     * Respects {@link #maxAllocationSize} limit when allocating byte arrays.
     */
    // Non-atomic update on the volatile positionAtCurrentBufferEntry field is
    // safe because the entire method body runs under bufferLock (see @GuardedBy
    // and the synchronized block in the caller). volatile guarantees visibility
    // to readers outside the lock; bufferLock guarantees atomicity of the
    // read-modify-write.
    @SuppressWarnings("NonAtomicVolatileUpdate")
    @GuardedBy("bufferLock")
    private void trim() {
        if (shouldTrim()) {
            isTrimRunning = true;
            try {
                releaseTrimStartSignals();

                /*
                 * Copy the buffered bytes into chunks of at most maxAllocationSize
                 * directly from the FIFO. availableBytes is deliberately left untouched:
                 * waitForAtLeast(long) and available() read it without bufferLock, and
                 * draining it to zero and filling it up again (as reading through the
                 * input stream did) let a waiter observe the intermediate count, e.g.
                 * a read() reporting the end of an open stream that still held data.
                 */
                final Deque<byte[]> tmpBuffer = new ArrayDeque<>();
                long remaining = availableBytes;
                while (remaining > 0) {
                    final int toAllocate = (int) Math.min(remaining, maxAllocationSize);
                    final byte[] chunk = new byte[toAllocate];
                    int filled = 0;
                    while (filled < toAllocate) {
                        final byte[] first = buffer.getFirst();
                        final int toCopy = Math.min(first.length - positionAtCurrentBufferEntry, toAllocate - filled);
                        System.arraycopy(first, positionAtCurrentBufferEntry, chunk, filled, toCopy);
                        filled += toCopy;
                        positionAtCurrentBufferEntry += toCopy;
                        if (positionAtCurrentBufferEntry == first.length) {
                            buffer.pollFirst();
                            positionAtCurrentBufferEntry = 0;
                        }
                    }
                    tmpBuffer.add(chunk);
                    remaining -= toAllocate;
                }
                buffer.addAll(tmpBuffer);
            } finally {
                isTrimRunning = false;
                releaseTrimEndSignals();
            }
        }
    }

    /**
     * Release all registered trim start signals (max 1 permit pattern).
     * This is called when trim() begins executing.
     */
    private void releaseTrimStartSignals() {
        for (Semaphore semaphore : trimStartSignals) {
            if (semaphore.availablePermits() == 0) {
                semaphore.release();
            }
        }
    }

    /**
     * Release all registered trim end signals (max 1 permit pattern).
     * This is called when trim() completes executing.
     */
    private void releaseTrimEndSignals() {
        for (Semaphore semaphore : trimEndSignals) {
            if (semaphore.availablePermits() == 0) {
                semaphore.release();
            }
        }
    }

    /**
     * Pure function to decide if trim should execute based on buffer state.
     * Contains all decision logic for the trim decision tree:
     * - maxBufferElements validity check (&#x2264; 0 is invalid)
     * - buffer size constraints (must be &#x2265; 2)
     * - current size vs max limit check (must exceed max)
     * - edge case: consolidation chunk count analysis
     *
     * This is a PURE FUNCTION with NO side effects or state access.
     * All parameters are value-based, not references to mutable state.
     *
     * Decision logic:
     * 1. If maxBufferElements &#x2264; 0: invalid configuration &#x2192; return false
     * 2. If currentBufferSize &lt; 2: buffer too small to consolidate &#x2192; return false
     * 3. If currentBufferSize &#x2264; maxBufferElements: within limit &#x2192; return false
     * 4. If edge case applies:
     *    - Calculate resulting chunks: ceil(availableBytes / maxAllocationSize)
     *    - If resultingChunks &#x2265; currentBufferSize: consolidation wouldn't reduce &#x2192; return false
     * 5. Otherwise: all conditions met &#x2192; return true
     *
     * @param currentBufferSize number of byte arrays in buffer Deque
     * @param maxBufferElements maximum allowed elements before trim triggers
     * @param availableBytes total bytes currently buffered
     * @param maxAllocationSize maximum size of a single byte array during consolidation
     * @return true if trim should execute, false if trim should be skipped
     */
    static boolean decideTrimExecution(
            final int currentBufferSize,
            final int maxBufferElements,
            final long availableBytes,
            final long maxAllocationSize) {

        // Check 1: Invalid maxBufferElements (≤ 0)
        if (maxBufferElements <= 0) {
            return false;
        }

        // Check 2: Buffer too small to consolidate (< 2 elements)
        if (currentBufferSize < 2) {
            return false;
        }

        // Check 3: Buffer within limit (≤ maxBufferElements)
        if (currentBufferSize <= maxBufferElements) {
            return false;
        }

        // Check 4: Edge case - consolidation wouldn't reduce chunk count
        if (shouldCheckEdgeCase(availableBytes, maxAllocationSize)) {
            // Calculate resulting chunks using ceiling division: ceil(n/d) = (n + d - 1) / d
            final long resultingChunks = calculateResultingChunks(availableBytes, maxAllocationSize);
            // If consolidation would still exceed current buffer size, trim is pointless
            if (shouldSkipTrimDueToEdgeCase(resultingChunks, currentBufferSize)) {
                return false;
            }
        }

        // All checks passed - trim should execute
        return true;
    }

    @GuardedBy("bufferLock")
    boolean shouldTrim() {
        /*
         * Prevent recursive trim: a write that reaches this point while trim is
         * running (only possible on the trim thread itself, from a trim signal's
         * release(), since bufferLock is reentrant) must not start another trim
         * over the deque the running one is rearranging.
         */
        if (isTrimRunning) {
            return false;
        }

        /*
         * To be thread safe, cache the maxBufferElements value. May the method
         * setMaxBufferElements(int) was invoked from outside by another thread.
         */
        final int maxBufferElements = getMaxBufferElements();

        // Delegate to pure decision function
        return decideTrimExecution(buffer.size(), maxBufferElements, availableBytes, getMaxAllocationSize());
    }

    /**
     * Clamps a long value to the range of an int without a conditional branch,
     * eliminating the equivalent ConditionalsBoundary mutation that would arise
     * from {@code value > MAX_VALUE} vs {@code value >= MAX_VALUE} (both return
     * the same result when {@code value == MAX_VALUE}).
     *
     * <p>Used by {@code available()}: {@link #availableBytes} is a {@code long} and can exceed
     * {@link Integer#MAX_VALUE} when more than 2&nbsp;GiB are buffered, while
     * {@link java.io.InputStream#available()} returns an {@code int}. Such a value is reported as
     * {@link Integer#MAX_VALUE}; the buffered data itself is unaffected.
     *
     * Package-private for direct unit testing.
     */
    static int clampToMaxInt(long value) {
        return (int) Math.min(value, Integer.MAX_VALUE);
    }

    /**
     * Decrements a byte-budget counter by the given amount.
     * Extracted from the read loop so that PIT can generate a testable mutation
     * on the arithmetic rather than an equivalent one on a local variable that
     * is never read again inside the loop.
     * Package-private for direct unit testing.
     */
    static long decrementAvailableBytesBudget(long current, long decrement) {
        return current - decrement;
    }

    /**
     * Calculates the number of chunks needed to hold availableBytes when
     * consolidating with a size limit of maxAllocSize.
     * Uses ceiling division: ceil(n/d) = (n + d - 1) / d
     * Extracted so PIT can generate testable mutations on the arithmetic operators.
     * Package-private for direct unit testing.
     */
    static long calculateResultingChunks(long availableBytes, long maxAllocSize) {
        return (availableBytes + maxAllocSize - 1) / maxAllocSize;
    }

    /**
     * Determines if trim should be skipped due to edge case:
     * when consolidating would NOT reduce chunk count below the current buffer size.
     * Extracted so PIT can generate testable mutations on the comparison operators.
     * Package-private for direct unit testing.
     */
    static boolean shouldSkipTrimDueToEdgeCase(long resultingChunks, int currentBufferSize) {
        return resultingChunks >= currentBufferSize;
    }

    /**
     * Check if trim should be skipped because maxBufferElements is invalid.
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean shouldSkipTrimDueToInvalidMaxBufferElements(int maxBufferElements) {
        return maxBufferElements <= 0;
    }

    /**
     * Check if trim should be skipped because buffer is too small.
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean shouldSkipTrimDueToSmallBuffer(int bufferSize) {
        return bufferSize < 2;
    }

    /**
     * Check if trim should be skipped because buffer size is within limit.
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean shouldSkipTrimDueToSufficientBuffer(int bufferSize, int maxBufferElements) {
        return bufferSize <= maxBufferElements;
    }

    /**
     * Check if available bytes is positive (boundary: &gt; 0).
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean isAvailableBytesPositive(long availableBytes) {
        return availableBytes > 0;
    }

    /**
     * Check if max allocation size is less than available bytes (boundary: &lt;).
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean isMaxAllocSizeLessThanAvailable(long maxAllocSize, long availableBytes) {
        return maxAllocSize < availableBytes;
    }

    /**
     * Check if edge case check should be performed (available bytes &gt; 0 AND maxAllocSize &lt; availableBytes).
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean shouldCheckEdgeCase(long availableBytes, long maxAllocSize) {
        return isAvailableBytesPositive(availableBytes)
                && isMaxAllocSizeLessThanAvailable(maxAllocSize, availableBytes);
    }

    /**
     * Record bytes read to statistics. Trim itself never reads through the stream, so
     * every read reaching this method is user I/O, including one made by a trim signal.
     * Package-private for direct unit testing.
     */
    void recordReadStatistics(long bytesRead) {
        totalBytesRead.addAndGet(bytesRead);
    }

    /**
     * Check if available bytes exceeds current max observed (boundary: &gt;).
     * Package-private for direct unit testing of boundary conditions.
     */
    static boolean shouldUpdateMaxObservedBytes(long availableBytes, long currentMax) {
        return availableBytes > currentMax;
    }

    /**
     * Update max observed bytes if available bytes exceeds current max.
     * Package-private for direct unit testing.
     */
    void updateMaxObservedBytesIfNeeded(long availableBytes) {
        if (shouldUpdateMaxObservedBytes(availableBytes, maxObservedBytes)) {
            maxObservedBytes = availableBytes;
        }
    }

    /**
     * Fails if the stream is closed. Called under {@link #bufferLock}, the lock
     * {@link #closeAll()} sets {@link #streamClosed} under, so a write that passes this check
     * is buffered before a concurrent close completes.
     */
    @GuardedBy("bufferLock")
    private void requireNonClosed() throws IOException {
        if (streamClosed) {
            throw new IOException("Stream closed (availableBytes=" + availableBytes + ").");
        }
    }

    /**
     * Blocks until at least {@code bytes} bytes are available, or the stream is closed.
     * If the stream is closed before {@code bytes} bytes arrive, returns the actual
     * number of bytes that did arrive (which may be less than {@code bytes}).
     *
     * <p>Must be called from a single reader thread; do not interleave with
     * {@link InputStream#read read()} on the same {@link StreamBuffer}.</p>
     *
     * @param bytes minimum number of bytes to wait for (must be &#x2265; 1)
     * @return the number of bytes available now
     * @throws InterruptedException if the current thread is interrupted while waiting
     */
    public long waitForAtLeast(final long bytes) throws InterruptedException {
        // we can only wait for a positive number of bytes
        if (bytes <= 0) {
            throw new IllegalArgumentException("Number of bytes are negative or zero : " + bytes);
        }

        // if we haven't enough bytes, the loop starts and wait for enough bytes
        while (bytes > availableBytes) {
            // first of all, check for a closed stream
            if (streamClosed) {
                // is the stream closed, return only the current available bytes
                return availableBytes;
            }
            // wait for a next loop run and block until a modification is signalized
            signalModification.acquire();
        }
        // return the available bytes (maybe higher as the required bytes)
        return availableBytes;
    }

    /**
     * Convenience: blocks until at least one byte is available, or the stream is
     * closed without data. Equivalent to {@link #waitForAtLeast(long) waitForAtLeast(1L)}.
     *
     * @return the number of bytes available now (&#x2265; 1 if data arrived;
     *         0 if the stream closed first without data)
     * @throws InterruptedException if the current thread is interrupted while waiting
     */
    public long waitForAnyData() throws InterruptedException {
        return waitForAtLeast(1L);
    }

    /**
     * Implementation of {@link SBInputStream#available()}: the buffered byte count clamped
     * to the {@link InputStream#available()} int contract.
     *
     * <p>The stream logic lives in these {@code private} outer methods — the inner stream
     * classes are pure delegating adapters. This is a hard requirement of the formal
     * verification setup, not just style: OpenJML's RAC compiler (21.0.27) emits field
     * references with a wrong owner class for outer-field access inside non-static inner
     * classes ({@code NoSuchFieldError} at test runtime), while method calls through
     * {@code this$0} are compiled correctly. See CLAUDE.md "Formal Verification".</p>
     *
     * @return the number of available bytes, clamped to {@link Integer#MAX_VALUE}
     */
    private int availableClamped() {
        return clampToMaxInt(availableBytes);
    }

    /**
     * Implementation of {@link SBInputStream#read()}: blocks until a byte is available or
     * the stream is closed. See {@link #availableClamped()} for why this lives in the outer
     * class.
     *
     * @return the next byte in the range {@code 0}–{@code 255}, or {@code -1} on end of stream
     * @throws IOException if the current thread is interrupted while waiting
     */
    private int readSingleByte() throws IOException {
        try {
            if (waitForAnyData() < 1) {
                // try to wait, but not enough bytes available
                // return the end of stream is reached
                return -1;
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException(e);
        }

        // enough bytes are available, lock and modify the FIFO
        synchronized (bufferLock) {
            // get the first element from FIFO
            final byte[] first = buffer.getFirst();
            // get the first byte
            byte value = first[positionAtCurrentBufferEntry];
            // we have the first byte, now set the pointer to the next value
            ++positionAtCurrentBufferEntry;
            // if the pointer was pointed to the last element of the
            // byte array remove the first element from FIFO and reset the pointer
            if (positionAtCurrentBufferEntry >= first.length) {
                // reset the pointer
                positionAtCurrentBufferEntry = 0;
                // remove the first element from the buffer
                buffer.pollFirst();
            }
            availableBytes--;
            recordReadStatistics(1);
            // returned as int in the range 0 to 255.
            return value & 0xff;
        }
    }

    /**
     * Implementation of {@link SBInputStream#read(byte[], int, int)}. See
     * {@link #availableClamped()} for why this lives in the outer class.
     *
     * <p>Waits for the first byte, then for all remaining {@code len - 1} bytes
     * ({@code waitForAtLeast}) unless the stream is closed first. Designed that
     * way since the first version; {@link #getInputStream()} documents it for
     * callers.
     *
     * @param b the destination array
     * @param off the offset in the destination array
     * @param len the maximum number of bytes to read
     * @return the number of bytes copied, {@code 0} for a zero-length request, or {@code -1}
     *         on end of stream
     * @throws IOException if the current thread is interrupted while waiting
     */
    private int readIntoArray(final byte b[], final int off, final int len) throws IOException {
        if (!validateOffsetAndLengthToRead(b, off, len)) {
            return 0;
        }

        // try to read the first byte from FIFO
        // copied from super.read
        // === snip
        int c = readSingleByte();
        if (c == -1) {
            return -1;
        }
        b[off] = (byte) c;
        // === snap

        // we have already copied one byte, initialize with 1
        int copiedBytes = 1;

        int missingBytes = len - copiedBytes;
        if (hasNoMissingBytes(missingBytes)) {
            return copiedBytes;
        }

        long maximumAvailableBytes;
        try {
            maximumAvailableBytes = waitForAtLeast(missingBytes);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException(e);
        }

        if (maximumAvailableBytes < 1) {
            // try to wait, but no more bytes available
            return copiedBytes;
        }

        // cap missingBytes to the actually available bytes
        missingBytes = (int) Math.min(maximumAvailableBytes, (long) missingBytes);

        // some or enough bytes are available, lock and modify the FIFO
        synchronized (bufferLock) {
            for (; ; ) {

                if (hasNoMissingBytes(missingBytes)) {
                    return copiedBytes;
                }

                // get the first element from FIFO
                final byte[] first = buffer.getFirst();
                // get the maximum bytes which can be copied
                // from the first element
                final int maximumBytesToCopy = first.length - positionAtCurrentBufferEntry;

                // this element can be copied fully to the destination
                if (missingBytes >= maximumBytesToCopy) {
                    // copy the complete byte[] to the destination
                    System.arraycopy(first, positionAtCurrentBufferEntry, b, copiedBytes + off, maximumBytesToCopy);
                    copiedBytes += maximumBytesToCopy;
                    maximumAvailableBytes = decrementAvailableBytesBudget(maximumAvailableBytes, maximumBytesToCopy);
                    availableBytes -= maximumBytesToCopy;
                    recordReadStatistics(maximumBytesToCopy);
                    missingBytes -= maximumBytesToCopy;
                    // remove the first element from the buffer
                    buffer.pollFirst();
                    // reset the pointer
                    positionAtCurrentBufferEntry = 0;
                } else {
                    // copy only a part of byte[] to the destination
                    System.arraycopy(first, positionAtCurrentBufferEntry, b, copiedBytes + off, missingBytes);
                    // add the offset
                    positionAtCurrentBufferEntry += missingBytes;
                    copiedBytes += missingBytes;
                    maximumAvailableBytes = decrementAvailableBytesBudget(maximumAvailableBytes, missingBytes);
                    availableBytes -= missingBytes;
                    recordReadStatistics(missingBytes);
                    // set missing bytes to zero
                    // we reach the end of the current buffer (b)
                    missingBytes = 0;
                }
            }
        }
    }

    /**
     * Ensure that no more bytes are missing.
     * @param missingBytes number of missing bytes.
     * @return <code>true</code> if no more bytes are missing, otherwise <code>false</code>.
     */
    private static boolean hasNoMissingBytes(int missingBytes) {
        assert missingBytes >= 0 : "Copied more bytes as given";

        // check if we don't need to copy further bytes anymore
        return missingBytes == 0;
    }

    /**
     * Implementation of {@link SBOutputStream#write(int)}: writes a single byte, bypassing
     * the {@link #safeWrite} clone because the one-element array never escapes. See
     * {@link #availableClamped()} for why this lives in the outer class.
     *
     * @param b the byte to write (only the low 8 bits are used)
     * @throws IOException if the stream is closed
     */
    private void writeSingleByte(final int b) throws IOException {
        final byte[] single = new byte[] {(byte) b};
        writeFromArray(single, 0, single.length, false);
    }

    /**
     * Implementation of {@link SBOutputStream#write(byte[], int, int)}. See
     * {@link #availableClamped()} for why this lives in the outer class.
     *
     * @param b the source array
     * @param off the offset in the source array
     * @param len the number of bytes to write
     * @throws IOException if the stream is closed
     */
    private void writeFromArray(final byte[] b, final int off, final int len) throws IOException {
        writeFromArray(b, off, len, true);
    }

    /**
     * Shared write path of {@link #writeFromArray(byte[], int, int)} and {@link #writeSingleByte(int)}.
     * Whether the {@link #safeWrite} clone may be skipped is a parameter rather than a field: a field
     * shared between threads let a concurrent {@code write(int)} switch the clone off for another
     * thread's {@code write(byte[])}, which then stored the caller's array by reference.
     *
     * @param b the source array
     * @param off the offset in the source array
     * @param len the number of bytes to write
     * @param cloneOnSafeWrite {@code false} if {@code b} was created internally and never escapes
     * @throws IOException if the stream is closed
     */
    private void writeFromArray(final byte[] b, final int off, final int len, final boolean cloneOnSafeWrite)
            throws IOException {
        if (!validateOffsetAndLengthToWrite(b, off, len)) {
            return;
        }
        // To be thread safe cache the safeWrite value.
        boolean tmpSafeWrite = isSafeWrite();

        synchronized (bufferLock) {
            // Checked under the lock closeAll() sets the flag under; see closeAll().
            requireNonClosed();
            if (off == 0 && b.length == len) {
                // add the full byte[] to the buffer
                if (tmpSafeWrite && cloneOnSafeWrite) {
                    buffer.add(b.clone());
                } else {
                    buffer.add(b);
                }
            } else {
                byte[] target = new byte[len];
                System.arraycopy(b, off, target, 0, len);
                buffer.add(target);
            }
            // increment the length
            availableBytes += len;
            // the count must be positive after any write operation
            assert availableBytes > 0 : "More memory used as a long can count";
            totalBytesWritten.addAndGet(len);
            updateMaxObservedBytesIfNeeded(availableBytes);
            trim();
        }
        // always at least, signal bytes are written to the buffer
        signalModification();
    }

    /**
     * The {@link InputStream} adapter. A pure delegating shell: every method forwards to a
     * {@code private} method of the enclosing {@link StreamBuffer} and the class body
     * contains no direct access to outer fields — see {@link #availableClamped()} for the
     * formal-verification constraint behind this shape.
     */
    private class SBInputStream extends InputStream {
        @Override
        public int available() throws IOException {
            return availableClamped();
        }

        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public int read() throws IOException {
            return readSingleByte();
        }

        // please do not override the method "int read(byte b[])"
        // the method calls internal "read(b, 0, b.length)"
        @Override
        public int read(final byte b[], final int off, final int len) throws IOException {
            return readIntoArray(b, off, len);
        }
    }

    /**
     * The {@link OutputStream} adapter. A pure delegating shell — see
     * {@link SBInputStream}.
     */
    private class SBOutputStream extends OutputStream {
        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public void write(final int b) throws IOException {
            writeSingleByte(b);
        }

        // please do not override the method "void write(final byte[] b)"
        // the method calls internal "write(b, 0, b.length);"
        @Override
        public void write(final byte[] b, final int off, final int len) throws IOException {
            writeFromArray(b, off, len);
        }
    }

    /**
     * Closes the buffer; both streams then report it as closed.
     *
     * <p>Waits for a write or trim in progress on another thread to finish (they hold the same
     * lock), so a write racing the close is either fully buffered or fails with "Stream closed".
     * A trim copies every buffered byte, so with a large buffer the wait can be noticeable.
     *
     * <p>A trim start or end signal ({@link #addTrimStartSignal(Semaphore)},
     * {@link #addTrimEndSignal(Semaphore)}) is released under that lock, so its {@code release()}
     * must not block on this buffer: a {@code close()} from another thread would wait behind it.
     */
    @Override
    public void close() throws IOException {
        closeAll();
    }

    /**
     * Invoke a close.
     *
     * <p>The flag is set under {@link #bufferLock}, the lock a write checks it under, so a write
     * racing the close is either fully buffered before the close or fails with "Stream closed";
     * it never appends after the close has returned, when a reader may already have reported the
     * end of the stream.
     */
    private void closeAll() {
        synchronized (bufferLock) {
            streamClosed = true;
        }
        signalModification();
    }

    /**
     * Returns <code>true</code> if the stream is closed. Otherwise
     * <code>false</code>.
     *
     * @return <code>true</code> if the stream is closed. Otherwise
     * <code>false</code>.
     */
    public boolean isClosed() {
        return streamClosed;
    }

    /**
     * Returns an input stream for this buffer.
     *
     * <p>
     * Under abnormal conditions the underlying buffer may be closed. When the
     * buffer is closed the following applies to the returned input stream :-
     *
     * <ul>
     *
     * <li><p>
     * If there are no bytes buffered on the buffer, and the buffer has not been
     * closed using {@link #close close}, then
     * {@link java.io.InputStream#available available} will return
     * <code>0</code>.
     *
     * </ul>
     *
     * <p>
     * Closing the returned {@link java.io.InputStream InputStream} will close
     * the complete buffer.
     *
     * <p>
     * {@link java.io.InputStream#read(byte[], int, int) read(b, off, len)}
     * blocks until <b>all</b> {@code len} bytes are available or the buffer is
     * closed; only then does it return fewer. This is stricter than the
     * {@code InputStream} contract, which only waits for one byte, and differs
     * from {@link java.io.PipedInputStream}. A reader that must not wait for a
     * full block, such as an {@code InputStreamReader} over a request/response
     * protocol, waits with {@link #waitForAnyData()} and then reads at most
     * {@link java.io.InputStream#available() available()} bytes.
     *
     * @return an input stream for reading bytes from this buffer.
     */
    public InputStream getInputStream() {
        return is;
    }

    /**
     * Returns an output stream for this buffer.
     *
     * <p>
     * Closing the returned {@link java.io.OutputStream OutputStream} will close
     * the associated buffer.
     *
     * @return an output stream for writing bytes to this buffer.
     */
    public OutputStream getOutputStream() {
        return os;
    }

    /**
     * Identity-shaped snapshot of the buffer's externally observable state.
     *
     * <p>Reports the bytes available to read, the current Deque element count,
     * the closed flag, and the {@code safeWrite} setting. Acquires
     * {@link #bufferLock} so the four numbers reflect the same instant; never
     * holds the lock for more than a constant-time read.
     *
     * <p>Intended for log lines and debugger displays; do not parse it.
     *
     * @return a human-readable single-line snapshot
     */
    @Override
    public String toString() {
        final long availableBytesSnapshot;
        final int bufferSizeSnapshot;
        final boolean closedSnapshot;
        final boolean safeWriteSnapshot;
        synchronized (bufferLock) {
            availableBytesSnapshot = availableBytes;
            bufferSizeSnapshot = buffer.size();
            closedSnapshot = streamClosed;
            safeWriteSnapshot = safeWrite;
        }
        return "StreamBuffer[available=" + availableBytesSnapshot
                + ", elements=" + bufferSizeSnapshot
                + ", closed=" + closedSnapshot
                + ", safeWrite=" + safeWriteSnapshot + "]";
    }
}
