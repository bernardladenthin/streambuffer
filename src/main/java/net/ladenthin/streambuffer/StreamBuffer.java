/**
 * Copyright 2014 Bernard Ladenthin bernard.ladenthin@gmail.com
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */
package net.ladenthin.streambuffer;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Deque;
import java.util.LinkedList;
import java.util.concurrent.Semaphore;

/**
 * A stream buffer is a class to buffer data that has been written to an
 * {@link OutputStream} and provide the data in an {@link InputStream}. There is
 * no need to close the stream before read. The read works during a write
 * process. It is possible to call concurrent a method in the
 * {@link OutputStream} and {@link InputStream}. Read/Write at the same time.
 *
 * @author Bernard Ladenthin <bernard.ladenthin@gmail.com>
 */
public class StreamBuffer implements Closeable {

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
     * A {@link Semaphore} to signal that data are added to the {@link #buffer}.
     * This signal is also used to announce that the stream was closed.
     * This {@link Semaphore} is used only for external communication.
     */
    private final Semaphore signalModificationExternal = new Semaphore(0);

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
     * A flag to disable the {@link safeWrite}. I. e. to write a byte array from
     * the trim method.
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
     * Construct a new {@link StreamBuffer}.
     */
    public StreamBuffer() {
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
     * Set maximum elements for the buffer.
     *
     * @param maxBufferElements number of maximum elements.
     */
    public void setMaxBufferElements(int maxBufferElements) {
        this.maxBufferElements = maxBufferElements;
    }

    /**
     * Call this method always after all changes are synchronized. This method
     * signals a modification. It cloud be a write on the stream or a close.
     */
    private void signalModification() {
        // hold up the count to a maximum of one
        if (signalModification.availablePermits() == 0) {
            signalModification.release();
        }
        // same twice for external communication
        if (signalModificationExternal.availablePermits() == 0) {
            signalModificationExternal.release();
        }
    }
    
    /**
     * This method is blocking until data is available on the
     * {@link InputStream} or the stream was closed.
     */
    public void blockDataAvailable() throws InterruptedException {
        if (isClosed()) {
            return;
        }
        
        if (availableBytes < 1) {
            signalModificationExternal.acquire();
        }
    }

    /**
     * This method trims the buffer.
     */
    private void trim() throws IOException {
        // To be thread safe cache the maxBufferElements value.
        int tmpMaxBufferElements = getMaxBufferElements();
        if ((tmpMaxBufferElements > 0) && (buffer.size() >= 2) && (buffer.size() > tmpMaxBufferElements)) {

            // ned to store more bufs, may it is not possible to read out all data at once
            // the available method only returns an int value instead a long value
            final Deque<byte[]> tmpBuffer = new LinkedList<>();

            int available;
            // empty the current buffer, read out all bytes
            while ((available = is.available()) > 0) {
                byte[] buf = new byte[available];
                // read out of the buffer
                // and store the result to the tmpBuffer
                int read = is.read(buf);
                if (read != available) {
                    throw new IOException("Read not enough bytes from buffer.");
                }
                tmpBuffer.add(buf);
            }
            // write all bytes back to the clean buffer
            try {
                ignoreSafeWrite = true;
                while (!tmpBuffer.isEmpty()) {
                    os.write(tmpBuffer.pollFirst());
                }
            } finally {
                ignoreSafeWrite = false;
            }
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
     * @param bytes the number of bytes waiting for.
     * @throws IOException If the thread is interrupted.
     * @return The available bytes.
     */
    private long tryWaitForEnoughBytes(final long bytes) throws IOException {
        // we can only wait for a positive number of bytes
        assert !(bytes <= 0) : "Number of bytes are negative or zero : " + bytes;

        // if we haven't enough bytes, the loop starts and wait for enough bytes
        while (bytes > availableBytes) {
            try {
                // first of all, check for a closed stream
                if (streamClosed) {
                    // is the stream closed, return only the current available bytes
                    return availableBytes;
                }
                // wait for a next loop run and block until a modification is signalized
                signalModification.acquire();
            } catch (InterruptedException ex) {
                throw new IOException(ex);
            }
        }
        // return the available bytes (maybe higher as the required bytes)
        return availableBytes;
    }

    InputStream is = new InputStream() {
        @Override
        public int available() throws IOException {
            if (availableBytes > Integer.MAX_VALUE) {
                return Integer.MAX_VALUE;
            }
            return (int) availableBytes;
        }

        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public int read() throws IOException {
            // we wait for enough bytes (one byte)
            if (tryWaitForEnoughBytes(1) < 1) {
                // try to wait, but not enough bytes available
                // return the end of stream is reached
                return -1;
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
                // returned as int in the range 0 to 255.
                return value & 0xff;
            }
        }

        // please do not override the method "int read(byte b[])"
        // the method calls internal "read(b, 0, b.length)"
        @Override
        public int read(final byte b[], final int off, final int len) throws IOException {
            // security check copied from super.read
            // === snip
            if (b == null) {
                throw new NullPointerException();
            } else if (off < 0 || len < 0 || len > b.length - off) {
                throw new IndexOutOfBoundsException();
            } else if (len == 0) {
                return 0;
            }
            // === snap

            // try to read the first byte from FIFO
            // copied from super.read
            // === snip
            int c = read();
            if (c == -1) {
                return -1;
            }
            b[off] = (byte) c;
            // === snap

            // we have already copied one byte initialize with 1
            int copiedBytes = 1;

            int missingBytes = len - copiedBytes;

            // the next snippet is used two times
            // ==================================================
            // === snip
            // should never happen
            assert !(missingBytes < 0) : "Copied more bytes as given";

            // check if we don't need to copy further bytes anymore
            if (missingBytes == 0) {
                return copiedBytes;
            }
            // === snap
            // ==================================================

            long maximumAvailableBytes = tryWaitForEnoughBytes(missingBytes);

            if (maximumAvailableBytes < 1) {
                // try to wait, but no more bytes available
                return copiedBytes;
            }

            // some or enough bytes are available, lock and modify the FIFO
            synchronized (bufferLock) {
                for (;;) {

                    // the next snippet is used two times
                    // ==================================================
                    // === snip
                    // should never happen
                    assert !(missingBytes < 0) : "Copied more bytes as given";

                    // check if we don't need to copy further bytes anymore
                    if (missingBytes == 0) {
                        return copiedBytes;
                    }
                    // === snap
                    // ==================================================

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
                        maximumAvailableBytes -= maximumBytesToCopy;
                        availableBytes -= maximumBytesToCopy;
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
                        maximumAvailableBytes -= missingBytes;
                        availableBytes -= missingBytes;
                        // set missing bytes to zero
                        // we reach the end of the current buffer (b)
                        missingBytes = 0;
                    }
                }
            }
        }

    };
    OutputStream os = new OutputStream() {
        @Override
        public void close() throws IOException {
            closeAll();
        }

        @Override
        public void write(final int b) throws IOException {
            requireNonClosed();
            synchronized (bufferLock) {
                // add the byte to the buffer
                buffer.add(new byte[]{(byte) b});
                // increment the length
                ++availableBytes;
                assert !(availableBytes < 0) : "More memory used as a long can count";
                trim();
            }
            // always at least, signal bytes are written to the buffer
            signalModification();
        }

        // please do not override the method "void write(final byte[] b)"
        // the method calls internal "write(b, 0, b.length);"
        @Override
        public void write(final byte[] b, final int off, final int len)
                throws IOException {
            // To be thread safe cache the safeWrite value.
            boolean tmpSafeWrite = isSafeWrite();
            // security check copied from super.write
            // === snip
            if (b == null) {
                throw new NullPointerException();
            } else if ((off < 0) || (off > b.length) || (len < 0)
                    || ((off + len) > b.length) || ((off + len) < 0)) {
                throw new IndexOutOfBoundsException();
            } else if (len == 0) {
                return;
            }
            // === snap

            requireNonClosed();
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
                availableBytes += b.length;
                assert !(availableBytes < 0) : "More memory used as a long can count";
                trim();
            }
            // always at least, signal bytes are written to the buffer
            signalModification();
        }
    };

    @Override
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
}
