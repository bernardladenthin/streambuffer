// @formatter:off

// Copyright 2014 Bernard Ladenthin bernard.ladenthin@gmail.com
// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
// @formatter:on
package net.ladenthin.streambuffer;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Deque;
import java.util.LinkedList;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Semaphore;


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

    final static String EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION = "Invalid offset or length given to correctOffsetAndLengthToWrite.";

    /**
     * An object to get an unique access to the {@link #buffer}. It is needed to
     * get an exclusive access for read and write operations.
     */
    private final Object bufferLock = new Object();

    /**
     * The buffer which contains the raw data.
     */
    private final Deque<byte[]> buffer = new LinkedList<>();

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
     * immutable. This may be revoked by {@link #ignoreSafeWrite}, for example a
     * byte array was created internally.
     */
    private volatile boolean safeWrite = false;

    /**
     * A flag to disable the {@link StreamBuffer#safeWrite}. I. e. to write a byte array from
     * the trim method.
     * It should be used if the reference to the buffer deque is not reachable out of the scope.
     * It is possible to ignore the safeWrite flag to prevent not necessary clone operations.
     */
    private boolean ignoreSafeWrite = false;

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
     */
    private volatile long totalBytesWritten = 0;

    /**
     * Cumulative bytes consumed by user reads and skips (excludes internal trim operations).
     */
    private volatile long totalBytesRead = 0;

    /**
     * Maximum size of a single byte array during consolidation. Default {@link Integer#MAX_VALUE}.
     */
    private volatile long maxAllocationSize = Integer.MAX_VALUE;

    /**
     * Flag set to true while trim is rearranging internal buffers.
     * Volatile so it's visible to all threads — used to skip statistics updates during trim.
     * Set to true at start of trim body, set to false in finally block.
     * This ensures totalBytesRead and totalBytesWritten always represent user I/O only.
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
     * Set a secure or unsercure write operation.
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
        return totalBytesWritten;
    }

    /**
     * Returns the cumulative number of bytes read by user I/O operations.
     * Excludes bytes read/written during internal {@link #trim()} operations.
     *
     * @return total bytes read.
     */
    public long getTotalBytesRead() {
        return totalBytesRead;
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
     * this limit. Default is {@link Integer#MAX_VALUE}.
     *
     * @param maxSize maximum allocation size in bytes. Must be positive.
     * @throws IllegalArgumentException if maxSize is not positive.
     */
    public void setMaxAllocationSize(final long maxSize) {
        if (maxSize <= 0) {
            throw new IllegalArgumentException("maxAllocationSize must be positive");
        }
        this.maxAllocationSize = maxSize;
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
            throw new NullPointerException("Semaphore cannot be null");
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
     *
     * @param semaphore the semaphore to register for trim start events
     * @throws NullPointerException if semaphore is null
     */
    public void addTrimStartSignal(Semaphore semaphore) {
        if (semaphore == null) {
            throw new NullPointerException("Semaphore cannot be null");
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
     *
     * @param semaphore the semaphore to register for trim end events
     * @throws NullPointerException if semaphore is null
     */
    public void addTrimEndSignal(Semaphore semaphore) {
        if (semaphore == null) {
            throw new NullPointerException("Semaphore cannot be null");
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
    public static boolean correctOffsetAndLengthToRead(byte[] b, int off, int len) {
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
    public static boolean correctOffsetAndLengthToWrite(byte[] b, int off, int len) {
        if (b == null) {
            throw new NullPointerException();
        } else if ((off < 0) || (off > b.length) || (len < 0)
                || ((off + len) > b.length) || ((off + len) < 0)) {
            throw new IndexOutOfBoundsException(EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION);
        } else if (len == 0) {
            return false;
        }
        return true;
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
     * Use {@link #tryWaitForEnoughBytes(long)}.
     *
     * @throws InterruptedException if the current thread is interrupted
     */
    @Deprecated
    public void blockDataAvailable() throws InterruptedException {
        tryWaitForEnoughBytes(1);
    }

    /**
     * This method trims the buffer. This method can be invoked after every
     * write operation. The method checks itself if the buffer should be trimmed
     * or not.
     * <strong>MUST be called inside {@code synchronized(bufferLock)}.</strong>
     * Sets {@link #isTrimRunning} volatile flag to prevent statistics updates during internal I/O.
     * Respects {@link #maxAllocationSize} limit when allocating byte arrays.
     */
    private void trim() throws IOException {
        if (isTrimShouldBeExecuted()) {
            isTrimRunning = true;
            try {
                releaseTrimStartSignals();

                /**
                 * Need to store more bufs, may it is not possible to read out all
                 * data at once. The available method only returns an int value
                 * instead a long value. Store all read parts of the full buffer in
                 * a deque.
                 */
                final Deque<byte[]> tmpBuffer = new LinkedList<>();

                int available;
                // empty the current buffer, read out all bytes
                while ((available = is.available()) > 0) {
                    // Limit each allocation to maxAllocationSize
                    final int toAllocate = (int) Math.min(available, maxAllocationSize);
                    final byte[] buf = new byte[toAllocate];
                    // read out of the buffer
                    // and store the result to the tmpBuffer
                    int read = is.read(buf);
                    // should never happen
                    assert read == toAllocate : "Read not enough bytes from buffer.";
                    tmpBuffer.add(buf);
                }
                /**
                 * Write all previously read parts back to the buffer directly.
                 * We are already holding {@link #bufferLock} and the chunks were
                 * just produced internally, so going through {@link SBOutputStream#write}
                 * is unnecessary and would fail at {@link #requireNonClosed()} if
                 * {@link #close()} is invoked concurrently — discarding tmpBuffer
                 * and losing every byte that trim already drained.
                 */
                while (!tmpBuffer.isEmpty()) {
                    // pollFirst returns always a non null value, tmpBuffer is only filled with non null values
                    final byte[] chunk = tmpBuffer.pollFirst();
                    buffer.add(chunk);
                    availableBytes += chunk.length;
                }
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
     * Checks if a trim should be performed.
     * Critical: Ensures trim will actually reduce buffer chunks below {@link #maxBufferElements}.
     * If consolidating would create chunks that still exceed the limit (when respecting
     * {@link #maxAllocationSize}), trim is skipped to prevent repeated trim calls on every write.
     *
     * @return <code>true</code> if a trim should be performed, otherwise <code>false</code>.
     */
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
    boolean decideTrimExecution(
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

    boolean isTrimShouldBeExecuted() {
        /**
         * Prevent recursive trim: if trim is already running, its internal
         * writes must never trigger another trim (infinite recursion / stack overflow).
         */
        if (isTrimRunning) {
            return false;
        }

        /**
         * To be thread safe, cache the maxBufferElements value. May the method
         * {@link #setMaxBufferElements(int)} was invoked from outside by another thread.
         */
        final int maxBufferElements = getMaxBufferElements();

        // Delegate to pure decision function
        return decideTrimExecution(
            buffer.size(),
            maxBufferElements,
            availableBytes,
            getMaxAllocationSize()
        );
    }

    /**
     * Clamps a long value to the range of an int without a conditional branch,
     * eliminating the equivalent ConditionalsBoundary mutation that would arise
     * from {@code value > MAX_VALUE} vs {@code value >= MAX_VALUE} (both return
     * the same result when {@code value == MAX_VALUE}).
     *
     * SAFETY GUARANTEE FOR LARGE BUFFERS:
     *
     * This method handles the type mismatch between:
     * - {@link #availableBytes}: volatile long (0 to 2^63-1, supports future-proof large buffers)
     * - InputStream.available(): int contract (0 to 2^31-1, ~2.1 billion)
     *
     * If availableBytes ever exceeds Integer.MAX_VALUE (e.g., 5GB+ of buffered data):
     * 1. This method returns Integer.MAX_VALUE (~2.1GB)
     * 2. The trim() loop reads Integer.MAX_VALUE bytes in one iteration
     * 3. Loop condition (available > 0) allows continuation
     * 4. Next iteration calls available() again, reads remaining bytes
     * 5. Process repeats until all availableBytes are consolidated
     *
     * Result: NO DATA LOSS, NO OVERFLOW - all data is processed correctly.
     *
     * EXAMPLE FLOW (5GB data):
     *   Iteration 1: available() &#x2192; clamped to 2,147,483,647 bytes &#x2192; read and consolidate
     *   Iteration 2: available() &#x2192; clamped to remaining bytes &#x2192; read and consolidate
     *   ... continues until availableBytes == 0
     *
     * This design allows StreamBuffer to theoretically support buffers larger than 2GB
     * while maintaining compatibility with the InputStream API contract that uses int.
     *
     * Package-private for direct unit testing.
     */
    int clampToMaxInt(long value) {
        return (int) Math.min(value, Integer.MAX_VALUE);
    }

    /**
     * Decrements a byte-budget counter by the given amount.
     * Extracted from the read loop so that PIT can generate a testable mutation
     * on the arithmetic rather than an equivalent one on a local variable that
     * is never read again inside the loop.
     * Package-private for direct unit testing.
     */
    long decrementAvailableBytesBudget(long current, long decrement) {
        return current - decrement;
    }

    /**
     * Calculates the number of chunks needed to hold availableBytes when
     * consolidating with a size limit of maxAllocSize.
     * Uses ceiling division: ceil(n/d) = (n + d - 1) / d
     * Extracted so PIT can generate testable mutations on the arithmetic operators.
     * Package-private for direct unit testing.
     */
    long calculateResultingChunks(long availableBytes, long maxAllocSize) {
        return (availableBytes + maxAllocSize - 1) / maxAllocSize;
    }

    /**
     * Determines if trim should be skipped due to edge case:
     * when consolidating would NOT reduce chunk count below the current buffer size.
     * Extracted so PIT can generate testable mutations on the comparison operators.
     * Package-private for direct unit testing.
     */
    boolean shouldSkipTrimDueToEdgeCase(long resultingChunks, int currentBufferSize) {
        return resultingChunks >= currentBufferSize;
    }

    /**
     * Check if trim should be skipped because maxBufferElements is invalid.
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean shouldSkipTrimDueToInvalidMaxBufferElements(int maxBufferElements) {
        return maxBufferElements <= 0;
    }

    /**
     * Check if trim should be skipped because buffer is too small.
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean shouldSkipTrimDueToSmallBuffer(int bufferSize) {
        return bufferSize < 2;
    }

    /**
     * Check if trim should be skipped because buffer size is within limit.
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean shouldSkipTrimDueToSufficientBuffer(int bufferSize, int maxBufferElements) {
        return bufferSize <= maxBufferElements;
    }

    /**
     * Check if available bytes is positive (boundary: &gt; 0).
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean isAvailableBytesPositive(long availableBytes) {
        return availableBytes > 0;
    }

    /**
     * Check if max allocation size is less than available bytes (boundary: &lt;).
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean isMaxAllocSizeLessThanAvailable(long maxAllocSize, long availableBytes) {
        return maxAllocSize < availableBytes;
    }

    /**
     * Check if edge case check should be performed (available bytes &gt; 0 AND maxAllocSize &lt; availableBytes).
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean shouldCheckEdgeCase(long availableBytes, long maxAllocSize) {
        return isAvailableBytesPositive(availableBytes) &&
               isMaxAllocSizeLessThanAvailable(maxAllocSize, availableBytes);
    }

    /**
     * Record bytes read to statistics if trim is not running.
     * Package-private for direct unit testing.
     */
    void recordReadStatistics(long bytesRead) {
        if (!isTrimRunning) {
            totalBytesRead += bytesRead;
        }
    }

    /**
     * Check if available bytes exceeds current max observed (boundary: &gt;).
     * Package-private for direct unit testing of boundary conditions.
     */
    boolean shouldUpdateMaxObservedBytes(long availableBytes, long currentMax) {
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
     * This method mustn't be called in a synchronized context, the variable is
     * volatile.
     */
    private void requireNonClosed() throws IOException {
        if (streamClosed) {
            throw new IOException("Stream closed.");
        }
    }

    /**
     * This method blocks until the stream is closed or enough bytes are
     * available, which can be read from the buffer.
     *
     * This method is blocking until data is available on the
     * {@link InputStream} or the stream was closed. This method could must be called
     * from one thread only (same thread as read methods, do not call this method during read operations).
     * It's not allowed to use this method to notify multiple threads.
     * @throws java.lang.InterruptedException if the current thread is interrupted
     *
     * @param bytes the number of bytes waiting for.
     * @throws IOException If the thread is interrupted.
     * @return The available bytes.
     */
    private long tryWaitForEnoughBytes(final long bytes) throws InterruptedException {
        // we can only wait for a positive number of bytes
        assert bytes > 0 : "Number of bytes are negative or zero : " + bytes;

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

    private class SBInputStream extends InputStream {
        @Override
        public int available() throws IOException {
            return clampToMaxInt(availableBytes);
        }

        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public int read() throws IOException {
            try{
                // we wait for enough bytes (one byte)
                if (tryWaitForEnoughBytes(1) < 1) {
                    // try to wait, but not enough bytes available
                    // return the end of stream is reached
                    return -1;
                }
            }
            catch (InterruptedException e) {
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

        // please do not override the method "int read(byte b[])"
        // the method calls internal "read(b, 0, b.length)"
        @Override
        public int read(final byte b[], final int off, final int len) throws IOException {
            if (!correctOffsetAndLengthToRead(b, off, len)) {
                return 0;
            }

            // try to read the first byte from FIFO
            // copied from super.read
            // === snip
            int c = read();
            if (c == -1) {
                return -1;
            }
            b[off] = (byte) c;
            // === snap

            // we have already copied one byte, initialize with 1
            int copiedBytes = 1;

            int missingBytes = len - copiedBytes;
            if (noMoreMissingBytes(missingBytes)) {
                return copiedBytes;
            }

            long maximumAvailableBytes;
            try {
                maximumAvailableBytes = tryWaitForEnoughBytes(missingBytes);
            } catch (InterruptedException e) {
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
                for (;;) {

                    if (noMoreMissingBytes(missingBytes)) {
                        return copiedBytes;
                    }

                    // get the first element from FIFO
                    final byte[] first = buffer.getFirst();
                    // get the maximum bytes which can be copied
                    // from the first element
                    final int maximumBytesToCopy
                            = first.length - positionAtCurrentBufferEntry;

                    // this element can be copied fully to the destination
                    if (missingBytes >= maximumBytesToCopy) {
                        // copy the complete byte[] to the destination
                        System.arraycopy(first, positionAtCurrentBufferEntry, b,
                                copiedBytes + off, maximumBytesToCopy);
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
                        System.arraycopy(first, positionAtCurrentBufferEntry, b,
                                copiedBytes + off, missingBytes);
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
        private boolean noMoreMissingBytes(int missingBytes) {
            assert missingBytes >= 0 : "Copied more bytes as given";

            // check if we don't need to copy further bytes anymore
            return missingBytes == 0;
        }

    }

    private class SBOutputStream extends OutputStream {
        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public void write(final int b) throws IOException {
            try {
                ignoreSafeWrite = true;
                write(new byte[]{(byte) b});
            } finally {
                ignoreSafeWrite = false;
            }
        }

        // please do not override the method "void write(final byte[] b)"
        // the method calls internal "write(b, 0, b.length);"
        @Override
        public void write(final byte[] b, final int off, final int len)
                throws IOException {
            if (!correctOffsetAndLengthToWrite(b, off, len)) {
                return;
            }
            requireNonClosed();
            // To be thread safe cache the safeWrite value.
            boolean tmpSafeWrite = isSafeWrite();

            synchronized (bufferLock) {
                if (off == 0 && b.length == len) {
                    // add the full byte[] to the buffer
                    if (tmpSafeWrite && !ignoreSafeWrite) {
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
                if (!isTrimRunning) {
                    totalBytesWritten += len;
                    updateMaxObservedBytesIfNeeded(availableBytes);
                }
                trim();
            }
            // always at least, signal bytes are written to the buffer
            signalModification();
        }
    }

    public void close() throws IOException {
        closeAll();
    }

    /**
     * Invoke a close.
     */
    private void closeAll() {
        streamClosed = true;
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
     * Returns the number of elements in the buffer.
     *
     * @return the number of elements in the buffer.
     */
    public int getBufferSize() {
        synchronized (bufferLock) {
            return buffer.size();
        }
    }
}
