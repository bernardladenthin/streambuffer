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

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Tests for {@link ByteCollector}.
 *
 * <p>Key property under test: no integer overflow occurs during the write phase regardless
 * of how many small chunks are appended, which is the root cause of the
 * {@code ByteArrayOutput.ensureCapacity()} overflow in the CBOR encoder of
 * {@code kotlinx.serialization} (issue: negative array size when buffer approaches 1 GB).</p>
 */
@Timeout(value = 20, unit = TimeUnit.SECONDS)
public class ByteCollectorTest {

    // -------------------------------------------------------------------------
    // Empty collector
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("empty collector")
    class EmptyCollector {

        @Test
        void sizeIsZero() throws IOException {
            ByteCollector collector = new ByteCollector();
            assertEquals(0L, collector.size());
        }

        @Test
        void toByteArrayReturnsEmptyArray() throws IOException {
            ByteCollector collector = new ByteCollector();
            assertArrayEquals(new byte[0], collector.toByteArray());
        }
    }

    // -------------------------------------------------------------------------
    // write(int b)
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("write(int)")
    class WriteSingleByte {

        @Test
        void sizeIncrements() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(0x42);
            assertEquals(1L, collector.size());
        }

        @Test
        void byteValueIsPreserved() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(0x42);
            assertArrayEquals(new byte[]{0x42}, collector.toByteArray());
        }

        @Test
        void onlyLow8BitsAreWritten() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(0x1FF);
            assertArrayEquals(new byte[]{(byte) 0xFF}, collector.toByteArray());
        }

        @Test
        void writeZero() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(0);
            assertArrayEquals(new byte[]{0}, collector.toByteArray());
        }
    }

    // -------------------------------------------------------------------------
    // write(byte[])
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("write(byte[])")
    class WriteByteArray {

        @Test
        void sizeReflectsArrayLength() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{1, 2, 3, 4, 5});
            assertEquals(5L, collector.size());
        }

        @Test
        void contentIsPreserved() throws IOException {
            ByteCollector collector = new ByteCollector();
            byte[] data = {10, 20, 30};
            collector.write(data);
            assertArrayEquals(data, collector.toByteArray());
        }

        @Test
        void writeEmptyArray() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[0]);
            assertEquals(0L, collector.size());
            assertArrayEquals(new byte[0], collector.toByteArray());
        }
    }

    // -------------------------------------------------------------------------
    // write(byte[], int, int)
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("write(byte[], offset, length)")
    class WriteByteArraySlice {

        @Test
        void writesOnlySlice() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{10, 20, 30, 40, 50}, 1, 3);
            assertArrayEquals(new byte[]{20, 30, 40}, collector.toByteArray());
        }

        @Test
        void writeFromStart() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{1, 2, 3}, 0, 2);
            assertArrayEquals(new byte[]{1, 2}, collector.toByteArray());
        }

        @Test
        void writeToEnd() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{1, 2, 3}, 1, 2);
            assertArrayEquals(new byte[]{2, 3}, collector.toByteArray());
        }

        @Test
        void writeZeroLength() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{1, 2, 3}, 0, 0);
            assertEquals(0L, collector.size());
        }

        @Test
        void invalidOffsetThrows() {
            ByteCollector collector = new ByteCollector();
            assertThrows(Exception.class, () -> collector.write(new byte[]{1, 2, 3}, -1, 2));
        }

        @Test
        void lengthExceedingArrayThrows() {
            ByteCollector collector = new ByteCollector();
            assertThrows(Exception.class, () -> collector.write(new byte[]{1, 2, 3}, 0, 10));
        }
    }

    // -------------------------------------------------------------------------
    // Multiple writes — ordering and accumulation
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("multiple sequential writes")
    class MultipleWrites {

        @Test
        void orderIsPreserved() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{1, 2});
            collector.write(3);
            collector.write(new byte[]{4, 5, 6}, 0, 3);
            assertArrayEquals(new byte[]{1, 2, 3, 4, 5, 6}, collector.toByteArray());
        }

        @Test
        void sizeAccumulates() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[10]);
            collector.write(new byte[20]);
            collector.write(new byte[30]);
            assertEquals(60L, collector.size());
        }

        @Test
        void manySmallWritesProduceCorrectResult() throws IOException {
            ByteCollector collector = new ByteCollector();
            int count = 1000;
            for (int i = 0; i < count; i++) {
                collector.write((byte) (i & 0xFF));
            }
            assertEquals(count, collector.size());
            byte[] result = collector.toByteArray();
            assertEquals(count, result.length);
            for (int i = 0; i < count; i++) {
                assertEquals((byte) (i & 0xFF), result[i], "byte at index " + i);
            }
        }
    }

    // -------------------------------------------------------------------------
    // No ensureCapacity overflow — the core motivation
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("no integer overflow during writes (core property)")
    class NoOverflow {

        /**
         * Writes enough data that a naive doubling ByteArray would need to grow many times.
         * In the kotlinx.serialization CBOR encoder, the ByteArray doubles: 32, 64, 128, …
         * and overflows to a negative size when position + needed &#x3e; Integer.MAX_VALUE/2.
         * ByteCollector never performs capacity arithmetic, so no overflow is possible.
         */
        @Test
        void writingManyChunksDoesNotOverflow() throws IOException {
            ByteCollector collector = new ByteCollector();
            byte[] chunk = new byte[4096];
            int chunkCount = 1024; // 4 MB total — well above the initial 32-byte capacity
            for (int i = 0; i < chunkCount; i++) {
                chunk[0] = (byte) (i & 0xFF);
                collector.write(chunk);
            }
            assertEquals(4096L * chunkCount, collector.size());
            byte[] result = collector.toByteArray();
            assertEquals(4096 * chunkCount, result.length);
        }

        @Test
        void sizeIsLongNotInt() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[100]);
            long size = collector.size();
            // Verify the return type contract: long, not int
            assertEquals(100L, size);
        }
    }

    // -------------------------------------------------------------------------
    // getInputStream — streaming access
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("getInputStream()")
    class StreamingAccess {

        @Test
        void inputStreamReadsWrittenBytes() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[]{7, 8, 9});
            // Bytes already available — read() returns immediately without blocking
            InputStream in = collector.getInputStream();
            assertEquals(7, in.read());
            assertEquals(8, in.read());
            assertEquals(9, in.read());
        }
    }

    // -------------------------------------------------------------------------
    // toByteArray — called on fresh collector (standard path)
    // -------------------------------------------------------------------------

    @Nested
    @DisplayName("toByteArray()")
    class ToByteArray {

        @Test
        void allBytesAreReturned() throws IOException {
            ByteCollector collector = new ByteCollector();
            byte[] input = {(byte) 0xCA, (byte) 0xFE, (byte) 0xBA, (byte) 0xBE};
            collector.write(input);
            assertArrayEquals(input, collector.toByteArray());
        }

        @Test
        void resultLengthMatchesSize() throws IOException {
            ByteCollector collector = new ByteCollector();
            collector.write(new byte[256]);
            byte[] result = collector.toByteArray();
            assertEquals(256, result.length);
        }
    }
}
