// @formatter:off
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
// @formatter:on
package net.ladenthin.streambuffer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * A single-threaded byte collector backed by {@link StreamBuffer}'s dynamic FIFO deque.
 *
 * <p>This class is a drop-in replacement for the common pattern of a growing {@code byte[]}
 * with an {@code ensureCapacity()} helper. Writes are O(1) with no capacity planning,
 * no power-of-two arithmetic, and no integer overflow during the write phase.
 * The {@link #size()} counter uses {@code long}, so byte accumulation is not limited
 * to {@link Integer#MAX_VALUE} bytes during writing.</p>
 *
 * <p>The design mirrors the approach used in
 * {@code kotlinx.serialization}'s {@code ByteArrayOutput} (CBOR encoder), but eliminates
 * the {@code ensureCapacity()} overflow that occurs when the growing {@code byte[]}
 * approaches 1 GB. Because {@link StreamBuffer} appends each chunk to a {@link java.util.Deque}
 * instead of doubling a contiguous array, there is no intermediate integer overflow
 * and no need for a {@code nextPowerOfTwoCapacity()} helper function.</p>
 *
 * <p>{@link #toByteArray()} still requires the total size to fit in an {@code int}, since a
 * Java {@code byte[]} is indexed by {@code int}. For payloads larger than
 * {@link Integer#MAX_VALUE} bytes, consume the data as a stream via {@link #getInputStream()}.</p>
 *
 * <p>This class is <strong>not thread-safe</strong>. All writes and the final read must
 * occur on the same thread (or with external synchronisation).</p>
 *
 * <h2>Usage</h2>
 * <pre>{@code
 * ByteCollector collector = new ByteCollector();
 * collector.write(header);
 * collector.write(payload, 0, payloadLen);
 * collector.write(0xFF); // single byte
 * byte[] result = collector.toByteArray();
 * }</pre>
 *
 * @author Bernard Ladenthin bernard.ladenthin@gmail.com
 * @see StreamBuffer
 */
public class ByteCollector {

    private final StreamBuffer streamBuffer;
    private final OutputStream out;

    /**
     * Creates a new {@link ByteCollector}.
     * Buffer trimming is disabled because single-threaded accumulation has no benefit
     * from intermediate consolidation.
     */
    public ByteCollector() {
        streamBuffer = new StreamBuffer();
        streamBuffer.setMaxBufferElements(0);
        out = streamBuffer.getOutputStream();
    }

    /**
     * Writes a single byte. Only the low 8 bits of {@code b} are written.
     *
     * @param b the byte value to write
     * @throws IOException if an I/O error occurs
     */
    public void write(int b) throws IOException {
        out.write(b);
    }

    /**
     * Writes all bytes in {@code bytes}.
     *
     * @param bytes the source array; must not be {@code null}
     * @throws IOException if an I/O error occurs
     */
    public void write(byte[] bytes) throws IOException {
        out.write(bytes);
    }

    /**
     * Writes {@code length} bytes from {@code bytes} starting at {@code offset}.
     *
     * @param bytes  the source array; must not be {@code null}
     * @param offset start index within {@code bytes}
     * @param length number of bytes to write
     * @throws IOException              if an I/O error occurs
     * @throws IndexOutOfBoundsException if {@code offset} or {@code length} is out of range
     */
    public void write(byte[] bytes, int offset, int length) throws IOException {
        out.write(bytes, offset, length);
    }

    /**
     * Returns the total number of bytes written so far.
     *
     * <p>Unlike a position counter stored in an {@code int}, this value uses {@code long}
     * and does not overflow during accumulation.</p>
     *
     * @return total bytes written
     */
    public long size() {
        return streamBuffer.getTotalBytesWritten();
    }

    /**
     * Returns all collected bytes as a single contiguous array and closes this collector.
     *
     * <p>Requires {@link #size()} &#x2264; {@link Integer#MAX_VALUE}.</p>
     *
     * <p>This method may only be called once. After it returns, the collector is closed
     * and further writes will throw {@link IOException}.</p>
     *
     * @return byte array containing every byte written to this collector, in order
     * @throws IOException           if an I/O error occurs while draining the buffer
     * @throws IllegalStateException if the total size exceeds {@link Integer#MAX_VALUE}
     */
    public byte[] toByteArray() throws IOException {
        long total = size();
        if (total > Integer.MAX_VALUE) {
            throw new IllegalStateException(
                "Collected " + total + " bytes; exceeds the maximum byte[] length of " + Integer.MAX_VALUE
                    + ". Use getInputStream() to consume the data as a stream instead."
            );
        }
        streamBuffer.close();
        final byte[] result = new byte[(int) total];
        final InputStream in = streamBuffer.getInputStream();
        int offset = 0;
        int remaining = (int) total;
        while (remaining > 0) {
            final int read = in.read(result, offset, remaining);
            if (read == -1) {
                break;
            }
            offset += read;
            remaining -= read;
        }
        return result;
    }

    /**
     * Returns the underlying {@link InputStream} for streaming consumption.
     *
     * <p>Use this instead of {@link #toByteArray()} when the total size may exceed 2 GB,
     * or when you want to process data incrementally without a final contiguous allocation.</p>
     *
     * <p>Close the {@link StreamBuffer} (or the returned stream) after you are done to
     * release resources. Calling {@link #toByteArray()} after obtaining the stream produces
     * undefined results.</p>
     *
     * @return input stream that reads bytes from this collector's buffer
     */
    public InputStream getInputStream() {
        return streamBuffer.getInputStream();
    }
}
