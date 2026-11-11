// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.is;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/** The geometric trim (TODO roadmap A14): its two decisions and the FIFO it leaves. */
class StreamBufferTrimGeometricTest {

    @Nested
    @DisplayName("joinsTrimMerge()")
    class JoinsTrimMerge {

        @Test
        @DisplayName("the newest entry always joins")
        void newestEntryAlwaysJoins() {
            assertThat(StreamBuffer.joinsTrimMerge(0, 0, 5, 100, 0), is(true));
        }

        @Test
        @DisplayName("an entry the caller may hold joins, however long, from the end of the owned prefix on")
        void callerEntryAlwaysJoins() {
            assertThat(StreamBuffer.joinsTrimMerge(1, 3, 3, 100, 1), is(true));
            assertThat(StreamBuffer.joinsTrimMerge(1, 4, 3, 100, 1), is(true));
        }

        @Test
        @DisplayName("an own chunk joins while it is not longer than what is collected")
        void ownChunkJoinsUpToCollected() {
            assertThat(StreamBuffer.joinsTrimMerge(1, 2, 3, 10, 10), is(true));
            assertThat(StreamBuffer.joinsTrimMerge(1, 2, 3, 11, 10), is(false));
        }
    }

    @Nested
    @DisplayName("shouldTrimMergeAll()")
    class ShouldTrimMergeAll {

        @Test
        @DisplayName("a tail of one entry: merge everything")
        void singleEntryTailMergesAll() {
            assertThat(StreamBuffer.shouldTrimMergeAll(1, 10, 1, 100), is(true));
            assertThat(StreamBuffer.shouldTrimMergeAll(2, 10, 1, 100), is(false));
        }

        @Test
        @DisplayName("the entries left: up to half of maxBufferElements keeps the tail merge")
        void entriesLeftUpToHalf() {
            // left = 10 - 6 + 1 = 5; half of 10 is 5
            assertThat(StreamBuffer.shouldTrimMergeAll(6, 10, 1, 10), is(false));
            // left = 10 - 5 + 1 = 6
            assertThat(StreamBuffer.shouldTrimMergeAll(5, 10, 1, 10), is(true));
            // the chunks of the merged bytes count too: left = 10 - 6 + 2 = 6
            assertThat(StreamBuffer.shouldTrimMergeAll(6, 10, 2, 10), is(true));
        }

        @Test
        @DisplayName("at least one entry may be left, even for maxBufferElements below 2")
        void atLeastOneLeft() {
            // left = 3 - 2 + 0 = 1; max(1, 1 / 2) = 1
            assertThat(StreamBuffer.shouldTrimMergeAll(2, 3, 0, 1), is(false));
            assertThat(StreamBuffer.shouldTrimMergeAll(2, 3, 1, 1), is(true));
            // max(1, 3 / 2) = 1
            assertThat(StreamBuffer.shouldTrimMergeAll(2, 3, 1, 3), is(true));
            assertThat(StreamBuffer.shouldTrimMergeAll(2, 3, 0, 3), is(false));
        }
    }

    @Nested
    @DisplayName("the FIFO a trim leaves")
    class Structure {

        private void writeOnes(final OutputStream os, final int count, final int[] next) throws IOException {
            for (int i = 0; i < count; i++) {
                os.write(new byte[] {(byte) next[0]++});
            }
        }

        private void assertReadsInOrder(final StreamBuffer sb, final int bytes) throws IOException {
            final InputStream is = sb.getInputStream();
            final byte[] read = new byte[bytes];
            assertThat(is.read(read, 0, bytes), is(bytes));
            for (int i = 0; i < bytes; i++) {
                assertThat(read[i], is((byte) (i + 1)));
            }
        }

        @Test
        @DisplayName("the first trim merges all caller arrays into one chunk")
        void firstTrimMergesAllCallerArrays() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final int[] next = {1};
            writeOnes(sb.getOutputStream(), 5, next);
            assertThat(sb.getBufferElementCount(), is(1));
            assertReadsInOrder(sb, 5);
        }

        @Test
        @DisplayName("a later trim keeps an own chunk longer than the new bytes")
        void laterTrimKeepsLongerOwnChunk() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final int[] next = {1};
            // trim 1: five caller arrays -> one chunk of 5 bytes
            writeOnes(sb.getOutputStream(), 5, next);
            // trim 2: four caller arrays of 1 byte (4 bytes) do not reach the 5-byte chunk
            writeOnes(sb.getOutputStream(), 4, next);
            assertThat(sb.getBufferElementCount(), is(2));
            assertReadsInOrder(sb, 9);
        }

        @Test
        @DisplayName("a later trim merges an own chunk no longer than the new bytes")
        void laterTrimMergesOwnChunkNoLonger() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final OutputStream os = sb.getOutputStream();
            final int[] next = {1};
            writeOnes(os, 5, next);
            // 5 new bytes (2 + 1 + 1 + 1) reach the 5-byte chunk: everything is merged again
            os.write(new byte[] {(byte) next[0]++, (byte) next[0]++});
            writeOnes(os, 3, next);
            assertThat(sb.getBufferElementCount(), is(1));
            assertReadsInOrder(sb, 10);
        }

        @Test
        @DisplayName("a read of the whole own chunk leaves only caller arrays, which the next trim merges")
        void readOwnChunkThenTrim() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final OutputStream os = sb.getOutputStream();
            final InputStream is = sb.getInputStream();
            final int[] next = {1};
            writeOnes(os, 5, next);
            // trim 2 keeps the 5-byte chunk: [5, 4]
            writeOnes(os, 4, next);
            // read the 5-byte chunk: [4], owned prefix 1
            assertThat(is.read(new byte[5], 0, 5), is(5));
            // read the 4-byte chunk: [], owned prefix 0
            assertThat(is.read(new byte[4], 0, 4), is(4));
            // a long caller array at the head, then four short ones: all of them are the caller's,
            // so the trim merges all five (a stale owned prefix would keep the long one)
            final byte[] longArray = new byte[10];
            for (int i = 0; i < longArray.length; i++) {
                longArray[i] = (byte) next[0]++;
            }
            os.write(longArray);
            writeOnes(os, 4, next);
            assertThat(sb.getBufferElementCount(), is(1));
            final byte[] read = new byte[14];
            assertThat(is.read(read, 0, 14), is(14));
            for (int i = 0; i < read.length; i++) {
                assertThat(read[i], is((byte) (10 + i)));
            }
        }

        @Test
        @DisplayName("a partly read head stays as it is when the trim does not reach it")
        void partlyReadHeadUntouched() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final OutputStream os = sb.getOutputStream();
            final InputStream is = sb.getInputStream();
            final int[] next = {1};
            // trim 1: five 2-byte arrays -> one 10-byte chunk
            for (int i = 0; i < 5; i++) {
                os.write(new byte[] {(byte) next[0]++, (byte) next[0]++});
            }
            assertThat(sb.getBufferElementCount(), is(1));
            // read 2 of its 10 bytes: 8 unread
            assertThat(is.read(), is(1));
            assertThat(is.read(), is(2));
            // trim 2: four new bytes do not reach the 8 unread bytes
            writeOnes(os, 4, next);
            assertThat(sb.getBufferElementCount(), is(2));
            final byte[] read = new byte[12];
            assertThat(is.read(read, 0, 12), is(12));
            assertThat(read, is(new byte[] {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}));
        }

        @Test
        @DisplayName("a partly read head is merged from its unread bytes when the trim reaches it")
        void partlyReadHeadMerged() throws IOException {
            final StreamBuffer sb = new StreamBuffer();
            sb.setMaxBufferElements(4);
            final OutputStream os = sb.getOutputStream();
            final InputStream is = sb.getInputStream();
            final int[] next = {1};
            writeOnes(os, 5, next);
            // read 3 of the 5-byte chunk: 2 unread
            assertThat(is.read(new byte[3], 0, 3), is(3));
            // trim 2: four new bytes reach the 2 unread ones: one chunk of 6
            writeOnes(os, 4, next);
            assertThat(sb.getBufferElementCount(), is(1));
            final byte[] read = new byte[6];
            assertThat(is.read(read, 0, 6), is(6));
            assertThat(read, is(new byte[] {4, 5, 6, 7, 8, 9}));
        }
    }
}
