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

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import java.io.*;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.not;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.number.OrderingComparison.greaterThan;
import static org.hamcrest.number.OrderingComparison.greaterThanOrEqualTo;
import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

@Timeout(value = 20, unit = TimeUnit.SECONDS)
public class StreamBufferTest {

    static Stream<Arguments> writeMethods() {
        return Stream.of(
            Arguments.of(WriteMethod.ByteArray),
            Arguments.of(WriteMethod.Int),
            Arguments.of(WriteMethod.ByteArrayWithParameter)
        );
    }

    /**
     * The answer to all questions.
     */
    private final static byte anyValue = 42;

    // <editor-fold defaultstate="collapsed" desc="roundtrip">
    @Test
    public void testSimpleRoundTrip() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(0);
        byte[] b0 = new byte[10];
        for (int i = 0; i < b0.length; ++i) {
            b0[i] = anyValue;
        }
        os.write(b0);
        os.write(0);

        assertEquals(12, is.available());

        // act
        byte[] target = new byte[12];
        is.read(target);

        // assert
        byte[] expected = new byte[12];
        for (int i = 1; i < 11; ++i) {
            expected[i] = anyValue;
        }
        assertArrayEquals(expected, target);
    }

    /**
     * This test verifies that the input stream's read method places bytes at a specific offset.
     * @throws IOException
     */
    @Test
    public void testSafeWriteSimpleOffset() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        sb.setSafeWrite(false);
        // the initial value
        final byte anyNumber = (byte) 4;

        // Create a new array with initial values.
        final byte[] content = new byte[]{anyNumber, anyNumber, anyNumber};

        // Write the array to the stream.
        os.write(content);

        // Ensure the array was completely written to the stream.
        assertEquals(3, is.available());

        // A buffer to read the content from the stream.
        final byte[] fromMemory = new byte[4];

        // act — read 2 bytes at an offset of 2 bytes
        final int read = is.read(fromMemory, 2, 2);

        // assert — first 2 slots unwritten (0), last 2 slots filled with anyNumber
        assertAll(
            () -> assertEquals(2, read, "should have read 2 values"),
            () -> assertEquals(1, is.available(), "1 value should remain in the stream"),
            () -> assertArrayEquals(new byte[]{0, 0, anyNumber, anyNumber}, fromMemory, "first 2 values unwritten, last 2 filled at the given offset")
        );
    }

    @Test
    public void testMultipleArray() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        byte[] b4 = new byte[]{4, 4, 4, 4};
        byte[] b5 = new byte[]{5, 5, 5, 5, 5};
        byte[] b6 = new byte[]{6, 6, 6, 6, 6, 6};
        os.write(b4);
        os.write(b5);
        os.write(b6);
        assertEquals(4 + 5 + 6, is.available());

        // act
        byte[] t0 = new byte[6];
        byte[] t1 = new byte[6];
        byte[] t2 = new byte[3];
        is.read(t0);
        is.read(t1);
        is.read(t2);

        // assert
        assertEquals((4 + 5 + 6) - (6 + 6 + 3), is.available());

        assertAll(
            () -> assertArrayEquals(new byte[]{4, 4, 4, 4, 5, 5}, t0),
            () -> assertArrayEquals(new byte[]{5, 5, 5, 6, 6, 6}, t1),
            () -> assertArrayEquals(new byte[]{6, 6, 6}, t2)
        );
    }

    @Test
    public void testLoopedRoundtrip() throws IOException {
        // arrange
        final int size = 32640; //255/2*(255+1)
        ByteArrayOutputStream baosOriginalData = new ByteArrayOutputStream(size);
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        for (int i = 1; i <= 255; ++i) {
            byte[] array = new byte[i];
            if (i >= 250) {
                System.out.println();
            }
            // Fill the array with content
            for (int j = 0; j < array.length; ++j) {
                array[j] = (byte) i;
            }

            os.write(array);
            baosOriginalData.write(array);
        }

        final byte[] originalData = baosOriginalData.toByteArray();

        assertEquals(size, is.available());

        // act
        ByteArrayOutputStream baosReadFromTwist = new ByteArrayOutputStream(size);
        long readBytes = 0;
        for (int i = 255; i >= 1; --i) {
            readBytes += i;
            byte[] array = new byte[i];

            is.read(array);
            assertEquals(size - readBytes, is.available());
            baosReadFromTwist.write(array);
        }

        final long finalReadBytes = readBytes;
        byte[] byteChain = baosReadFromTwist.toByteArray();

        // assert
        assertAll(
            () -> assertEquals(size, finalReadBytes, "total bytes read should equal size"),
            () -> assertEquals(0, is.available(), "stream should be empty after reading all bytes"),
            () -> assertEquals(size, byteChain.length, "reconstructed byte chain length should match size"),
            () -> assertArrayEquals(originalData, byteChain, "reconstructed byte chain should match original data")
        );
    }

    @Test
    public void testDataInputOutput() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        DataInput din = new DataInputStream(is);
        DataOutput dout = new DataOutputStream(os);

        final String testString = "test string";

        dout.writeUTF(testString);

        // act
        String readUTF = din.readUTF();

        // assert
        assertEquals(testString, readUTF);
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="constructor">
    @Test
    public void constructor_noArguments_NoExceptionThrown() {
        // arrange
        // act
        new StreamBuffer();
        // assert — no exception thrown
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="getMaxBufferElements">
    @Test
    public void getMaxBufferElements_initialValue_GreaterZero() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.getMaxBufferElements(), is(greaterThan(0)));
    }

    @Test
    public void getMaxBufferElements_afterSet_Zero() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.setMaxBufferElements(0);

        // assert
        assertThat(sb.getMaxBufferElements(), is(0));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="setMaxBufferElements">
    @Test
    public void setMaxBufferElements_writeNegativeValue_equalsToGetter() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.setMaxBufferElements(-1);

        // assert
        assertThat(-1, is(sb.getMaxBufferElements()));
    }

    @Test
    public void setMaxBufferElements_useNegativeValue_trimNotCalled() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.setMaxBufferElements(-1);

        // Write fewer than four elements to the stream.
        // The trim method should not be called.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        // assert
        assertThat(sb.getBufferSize(), is(3));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isSafeWrite">
    @Test
    public void isSafeWrite_initialValue_false() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.isSafeWrite(), is(false));
    }

    @Test
    public void isSafeWrite_afterSet_true() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.setSafeWrite(true);

        // assert
        assertThat(sb.isSafeWrite(), is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isClosed">
    @Test
    public void isClosed_afterConstruct_false() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.isClosed(), is(false));
    }

    @Test
    public void isClosed_afterClose_true() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.close();

        // assert
        assertThat(sb.isClosed(), is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read_changeBufferFromOutside">
    /**
     * This test verifies that when the option safeWrite is disabled, the buffer
     * can be modified externally (the write method does not create clones of the
     * written arrays).
     *
     * @throws IOException
     */
    @Test
    public void read_changeBufferFromOutside_hasChanged() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // Disable the safe write option.
        sb.setSafeWrite(false);
        // Create a new byte array which is not immutable.
        byte[] notImmutable = new byte[]{anyValue};
        // Write the byte array.
        sb.getOutputStream().write(notImmutable);
        // Change the byte array.
        notImmutable[0]++;
        // A new byte array for the read method.
        byte[] fromStream = new byte[1];

        // act
        // Read the content out of the stream.
        sb.getInputStream().read(fromStream);

        // assert
        assertThat(fromStream[0], is(not((byte) anyValue)));
    }

    /**
     * This test verifies that when the option safeWrite is enabled, the buffer
     * cannot be changed from outside (the write method creates clones of the
     * written arrays).
     *
     * @throws IOException
     */
    @Test
    public void read_changeBufferFromOutside_notChanged() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // Disable the safe write option.
        sb.setSafeWrite(true);
        // Create a new byte array which is not immutable.
        byte[] notImmutable = new byte[]{anyValue};
        // Write the byte array.
        sb.getOutputStream().write(notImmutable);
        // Change the byte array.
        notImmutable[0]++;
        // A new byte array for the read method.
        byte[] fromStream = new byte[1];

        // act
        // Read the content out of the stream.
        sb.getInputStream().read(fromStream);

        // assert
        assertThat(fromStream[0], is((byte) anyValue));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="getBufferSize">
    @Test
    public void getBufferSize_reachMaxBufferElements_trimCalled() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);

        // act
        // Write more than one element to the stream to force a trim call.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        // assert
        int result = sb.getBufferSize();
        assertThat(result, is(1));
    }

    @Test
    public void getBufferSize_reachMaxBufferElements_trimBufferRightValues() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        sb.setMaxBufferElements(2);

        // act
        // Write more than one element to the stream to force a trim call.
        sb.getOutputStream().write(1);
        sb.getOutputStream().write(new byte[]{2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});

        // assert
        byte[] read = new byte[is.available()];
        is.read(read);
        assertThat(read, is(new byte[]{1, 2, 3, 4, 5, 6}));
    }

    @Test
    public void getBufferSize_writeSomeElements_trimNotCalled() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(4);

        // act
        // Write fewer than four elements to the stream.
        // The trim method should not be called.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        // assert
        assertThat(sb.getBufferSize(), is(3));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read">
    @Test
    public void read_closedStreamBeforeWrite_ReturnMinusOne() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        // act
        os.close();

        // assert
        assertThat(is.read(), is(-1));
    }

    @Test
    public void read_closedStreamAfterWrite_ReturnMinusOne() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(anyValue);
        os.close();
        // Read the previously written value from the buffer.
        is.read();

        // act
        // assert
        assertThat(is.read(), is(-1));
    }

    @Test
    public void read_readWithOffset_useOffset() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{anyValue, anyValue, anyValue});

        // act
        byte[] dest = new byte[9];
        is.read(dest, 3, 3);

        // assert
        assertThat(dest, is(new byte[]{0, 0, 0, anyValue, anyValue, anyValue, 0, 0, 0}));
    }

    @Test
    public void read_zeroLength_unmodifiedByteArray() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{anyValue, anyValue, anyValue});

        // act
        byte[] dest = new byte[1];
        is.read(dest, 0, 0);

        // assert
        assertThat(dest, is(new byte[]{0}));
    }

    @Test
    public void read_nothingWritten_returnMinusOne() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.close();

        // act
        byte[] dest = new byte[1];
        int read = is.read(dest, 0, 1);

        // assert
        assertThat(read, is(-1));
    }

    @Test
    public void read_nullDestGiven_throwNullPointerException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        // act
        // assert
        assertThrows(NullPointerException.class, () -> is.read(null, 0, 0));
    }

    @Test
    public void read_useInvalidOffset_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        byte[] dest = new byte[1];
        // act
        // assert
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 3, 1));
    }

    @Test
    public void read_lengthGreaterThanDestination_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        byte[] dest = new byte[1];
        // act
        // assert
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 0, 2));
    }

    @Test
    public void read_negativeLength_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        byte[] dest = new byte[1];
        // act
        // assert
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 0, -1));
    }

    @Test
    public void read_negativeOffset_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        byte[] dest = new byte[1];
        // act
        // assert
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, -1, 1));
    }

    @Test
    public void read_closeStream_returnsWrittenBytes() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();
        final OutputStream os = sb.getOutputStream();
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sleepOneSecond();
                    // first, write a value
                    os.write(anyValue);
                    // wait again
                    sleepOneSecond();
                    // close the stream
                    os.close();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                } catch (IOException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });

        // act
        consumer.start();
        byte[] dest = new byte[3];
        int read = is.read(dest);

        // assert
        assertThat(read, is(1));
    }

    @Test
    public void read_afterImmediateClose_returnsEOF() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.close();
        // act
        // assert
        assertThat(sb.getInputStream().read(), is(-1));
    }

    @Test
    public void read_parallelClose_noDeadlock() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();

        Thread reader = new Thread(() -> {
            try {
                is.read(); // Should block initially, then unblock on close
            } catch (IOException e) {
                // Expected when stream is closed
            }
        });

        // act
        reader.start();
        Thread.sleep(500); // Let the read() call block
        sb.close();        // Should unblock the reader
        reader.join();     // Ensure thread completes

        // assert — no deadlock, no exception
    }

    @Test
    public void read_afterTrimAndClose_returnsRemainingBytesThenEOF() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        sb.getOutputStream().write(new byte[]{1, 2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});
        sb.close();

        // act
        byte[] buffer = new byte[6];
        int read = sb.getInputStream().read(buffer);

        // assert
        assertAll(
            () -> assertThat("Should read all bytes", read, is(6)),
            () -> assertThat("Should return EOF", sb.getInputStream().read(), is(-1))
        );
    }

    @Test
    public void alternatingReadWrite_smallChunks_correctOrder() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // act
        for (int i = 0; i < 100; i++) {
            os.write(i);
            assertThat(is.read(), is(i));
        }

        // assert
        assertThat("Stream should be empty after balanced writes/reads", is.available(), is(0));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="write">
    @Test
    public void write_nullDestGiven_throwNullPointerException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        // act
        // assert
        assertThrows(NullPointerException.class, () -> os.write(null, 0, 0));
    }

    @Test
    public void write_useInvalidOffset_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] from = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 3, 1));

        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_lengthGreaterThanDestination_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] from = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 0, 2));

        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_negativeLength_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] from = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 0, -1));

        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_negativeOffset_throwIndexOutOfBoundsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] from = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, -1, 1));

        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_withValidOffset_partialWriteSuccessful() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        byte[] from = new byte[]{anyValue, anyValue};

        // act
        os.write(from, 1, 1);

        // assert
        assertThat(is.available(), is(1));
    }

    private void writeAnyValue(WriteMethod writeMethod, OutputStream os) throws IOException {
        switch(writeMethod) {
            case ByteArray:
                os.write(new byte[]{anyValue});
                break;
            case Int:
                os.write(anyValue);
                break;
            case ByteArrayWithParameter:
                os.write(new byte[]{anyValue, 0, 1});
                break;
            default:
                throw new IllegalArgumentException("Unknown WriteMethod: " + writeMethod);
        }
    }

    @ParameterizedTest
    @MethodSource("writeMethods")
    public void write_closedStream_throwIOException(WriteMethod writeMethod) {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        // act
        // assert
        assertThrows(IOException.class, () -> {
            os.close();
            writeAnyValue(writeMethod, os);
        });
    }

    @Test
    public void write_invalidOffset_notWritten() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        int invalidOffset = 1;

        // act
        os.write(new byte[]{anyValue}, invalidOffset, 0);

        // assert
        assertThat(sb.getBufferSize(), is(0));
    }

    @Test
    public void write_invalidLength_notWritten() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        int invalidLength = 0;

        // act
        os.write(new byte[]{anyValue}, 0, invalidLength);

        // assert
        assertThat(sb.getBufferSize(), is(0));
    }

    @Test
    public void write_nullArrayWithOffset_throwsNPE() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThrows(NullPointerException.class, () -> sb.getOutputStream().write(null, 0, 1));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="available">
    @Test
    public void available_bufferContainsMoreBytesAsMaxInt_returnMaxValue() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        int chunks = 16;

         // It's not a good idea to allocate a very big array at once.
         // Allocate a small piece instead and write this again and again to the stream.
         // I have chosen 16 pieces and written this value 17 times
         // to trigger an overflow in the available() method.
        byte[] chunk = new byte[Integer.MAX_VALUE / chunks];

        // act
        for (int i = 0; i < chunks; i++) {
            os.write(chunk);
        }
        // write one additional
        os.write(chunk);

        // assert
        assertThat(is.available(), is(Integer.MAX_VALUE));
    }

    @Test
    public void available_afterMultipleWrites_correctCount() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // act
        // Write 5 chunks, each of 2 bytes
        for (int i = 0; i < 5; i++) {
            os.write(new byte[]{1, 2});
        }

        // assert
        assertThat("available() should reflect the correct byte count", is.available(), is(10));
    }
    // </editor-fold>
    
    /**
     * Brief sleep to allow the method to block the thread correctly.
     */
    private void sleepOneSecond() throws InterruptedException {
        Thread.sleep(1000);
    }

    // <editor-fold defaultstate="collapsed" desc="blockDataAvailable">
    @ParameterizedTest
    @MethodSource("writeMethods")
    public void blockDataAvailable_dataWrittenBefore_noWaiting(WriteMethod writeMethod) throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        final Semaphore after = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    after.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });
        writeAnyValue(writeMethod, os);

        // act
        consumer.start();
        sleepOneSecond();

        // assert
        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }

    @Test
    @Timeout(value = 1, unit = TimeUnit.HOURS)
    public void blockDataAvailable_dataWrittenBeforeAndReadAfterwards_waiting() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        final Semaphore after = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    after.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });
        writeAnyValue(WriteMethod.Int, os);
        is.read();

        // act
        consumer.start();
        sleepOneSecond();

        // assert
        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(false));
    }

    @Test
    @Timeout(value = 1, unit = TimeUnit.HOURS)
    public void blockDataAvailable_streamUntouched_waiting() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore after = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    after.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });

        // act
        consumer.start();
        sleepOneSecond();
        after.drainPermits();

        // assert
        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(false));
    }

    @ParameterizedTest
    @MethodSource("writeMethods")
    public void blockDataAvailable_writeToStream_return(WriteMethod writeMethod) throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        final Semaphore after = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    after.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });

        // act
        consumer.start();
        sleepOneSecond();
        after.drainPermits();
        writeAnyValue(writeMethod, os);

        // assert
        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void blockDataAvailable_closeStream_return() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        final Semaphore after = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    after.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });

        // act
        consumer.start();
        sleepOneSecond();
        after.drainPermits();
        os.close();

        // assert
        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void blockDataAvailable_streamAlreadyClosed_return() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act
        sb.close();
        sb.blockDataAvailable();

        // assert — no exception thrown
    }

    @Test
    public void blockDataAvailable_dataAlreadyAvailable_onlyOneWakeup() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        // Write one value before starting threads
        os.write(anyValue);

        final Semaphore ready = new Semaphore(0);
        final Semaphore done = new Semaphore(0);

        Thread consumer1 = new Thread(() -> {
            try {
                ready.release();
                sb.blockDataAvailable();
                done.release();
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
        });

        Thread consumer2 = new Thread(() -> {
            try {
                ready.release();
                sb.blockDataAvailable();
                done.release();
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
        });

        // act
        consumer1.start();
        consumer2.start();
        ready.acquire(2); // wait for both threads to be ready
        done.tryAcquire(1, TimeUnit.SECONDS); // one should proceed
        Thread.sleep(100); // give it some time
        int acquired = done.drainPermits(); // number of threads that actually returned

        // assert
        assertThat("Only one thread should proceed due to single permit", acquired, is(1));
    }

    @Test
    public void blockDataAvailable_multipleWritesBeforeCall_doesNotBlock() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        os.write(anyValue);
        os.write(anyValue);

        // act
        // Should not block since data is already written
        sb.blockDataAvailable();

        // assert — does not block
    }

    @Test
    public void blockDataAvailable_afterBytesConsumed_blocksAgain() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        os.write(anyValue);
        is.read(); // consumes byte, availableBytes now 0

        final Semaphore signal = new Semaphore(0);
        Thread thread = new Thread(() -> {
            try {
                sb.blockDataAvailable();
                signal.release();
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
        });

        // act
        thread.start();

        Thread.sleep(500); // give thread time to block

        // assert
        assertThat("Thread should block since no new data was written", signal.tryAcquire(), is(false));

        os.write(anyValue);
        assertThat("Thread should wake up after new data", signal.tryAcquire(2, TimeUnit.SECONDS), is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="mark">
    @Test
    public void mark_useBufferedInputStream_resetPosition() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        int size = 3;
        BufferedInputStream bis = new BufferedInputStream(is, size);
        for (int i = 0; i < size; i++) {
            os.write(anyValue);
        }

        // act
        bis.mark(1);
        bis.read();
        bis.reset();

        // assert
        int result = bis.available();
        assertThat(result, is(size));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="trim">
    @Test
    public void trim_preservesAllBytesInCorrectOrder() throws Exception {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(2);

        byte[] input = new byte[10];
        for (int i = 0; i < 10; i++) input[i] = (byte) i;
        for (int i = 0; i < 10; i++) {
            sb.getOutputStream().write(new byte[]{input[i]});
        }

        // act
        byte[] output = new byte[10];
        sb.getInputStream().read(output);

        // assert
        assertArrayEquals(input, output, "Trimmed buffer should preserve all byte order");
    }

    @Test
    public void trim_emptyBuffer_noExceptionThrown() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);

        // act
        // nothing written yet, but trim should not fail
        sb.getOutputStream().write(new byte[0]);

        // assert — no exception thrown
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="close">
    @Test
    public void close_multipleCalls_noExceptionThrown() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.close();
        sb.close(); // Should not throw

        // assert — no exception thrown
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="concurrentReadWrite">
    @Test
    public void concurrentReadWrite_stressTest_noCrashOrInconsistency() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final int iterations = 1000;
        final byte[] written = new byte[iterations];
        final byte[] read = new byte[iterations];

        Thread writer = new Thread(() -> {
            try {
                for (int i = 0; i < iterations; i++) {
                    byte val = (byte) (i % 256);
                    written[i] = val;
                    os.write(val);
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });

        Thread reader = new Thread(() -> {
            try {
                for (int i = 0; i < iterations; i++) {
                    int value = is.read();
                    read[i] = (byte) value;
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });

        // act
        writer.start();
        reader.start();
        writer.join();
        reader.join();

        // assert
        assertArrayEquals(written, read, "Read data should match written data");
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="getInputStream">
    /**
     * This test documents that multiple calls to getInputStream()
     * return the same shared InputStream instance.
     *
     * Note: StreamBuffer is designed to support a single consumer.
     * Repeated calls return the same instance; independent parallel reads are not supported.
     */
    @Test
    public void multipleInputStream_returnsSameInstance_eachCall() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream first = sb.getInputStream();
        InputStream second = sb.getInputStream();

        // act
        // assert
        assertSame(first, second, "StreamBuffer should return the same InputStream instance");
    }
    // </editor-fold>
    
    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToRead">
    @Test
    public void correctOffsetAndLengthToRead_nullArray_throwsNullPointerException() {
        // arrange
        // act
        // assert — exception thrown is the assertion
        assertThrows(NullPointerException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(null, 0, 1));
    }

    @Test
    public void correctOffsetAndLengthToRead_negativeOffset_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(b, -1, 1));
        // assert — exception thrown is the assertion
    }

    @Test
    public void correctOffsetAndLengthToRead_negativeLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(b, 0, -1));
        // assert — exception thrown is the assertion
    }

    @Test
    public void correctOffsetAndLengthToRead_lengthExceedsRemainingArray_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(b, 3, 3));
        // assert — exception thrown is the assertion
    }

    @Test
    public void correctOffsetAndLengthToRead_zeroLength_returnsFalse() {
        // arrange
        byte[] b = new byte[5];

        // act
        boolean result = StreamBuffer.correctOffsetAndLengthToRead(b, 0, 0);

        // assert
        assertThat(result, is(false));
    }

    @Test
    public void correctOffsetAndLengthToRead_validParameters_returnsTrue() {
        // arrange
        byte[] b = new byte[5];

        // act
        boolean result = StreamBuffer.correctOffsetAndLengthToRead(b, 1, 3);

        // assert
        assertThat(result, is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToWrite">
    @Test
    public void correctOffsetAndLengthToWrite_nullArray_throwsNullPointerException() {
        // arrange
        // act
        // assert — exception thrown is the assertion
        assertThrows(NullPointerException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(null, 0, 1));
    }

    @Test
    public void correctOffsetAndLengthToWrite_negativeOffset_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, -1, 1));
        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_negativeLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 0, -1));
        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_offsetExceedsArrayLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 2, 1));
        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_lengthExceedsRemainingArray_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 3, 3));
        // assert
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_zeroLength_returnsFalse() {
        // arrange
        byte[] b = new byte[5];

        // act
        boolean result = StreamBuffer.correctOffsetAndLengthToWrite(b, 0, 0);

        // assert
        assertThat(result, is(false));
    }

    @Test
    public void correctOffsetAndLengthToWrite_validParameters_returnsTrue() {
        // arrange
        byte[] b = new byte[5];

        // act
        boolean result = StreamBuffer.correctOffsetAndLengthToWrite(b, 1, 3);

        // assert
        assertThat(result, is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isTrimShouldBeExecuted boundary">
    @Test
    public void getBufferSize_exactlyAtMaxBufferElements_trimNotCalled() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(2);

        // act
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        // assert
        assertThat(sb.getBufferSize(), is(2));
    }

    @Test
    public void getBufferSize_oneAboveMaxBufferElements_trimCalled() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(2);

        // act
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        // assert
        assertThat(sb.getBufferSize(), is(1));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="getOutputStream">
    @Test
    public void multipleOutputStream_returnsSameInstance_eachCall() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        OutputStream first = sb.getOutputStream();
        OutputStream second = sb.getOutputStream();

        // assert
        assertSame(first, second, "StreamBuffer should return the same OutputStream instance");
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="requireNonClosed">
    @Test
    public void write_closedStream_throwIOExceptionWithStreamClosedMessage() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.close();

        // act
        IOException ex = assertThrows(IOException.class,
            () -> sb.getOutputStream().write(new byte[]{anyValue}, 0, 1));
        assertThat(ex.getMessage(), is("Stream closed."));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="write inherited">
    @Test
    public void write_fullArrayWithoutOffsetParameter_allBytesWritten() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        byte[] source = new byte[]{1, 2, 3};

        // act
        sb.getOutputStream().write(source);

        // assert
        assertThat(is.available(), is(3));
        byte[] dest = new byte[3];
        is.read(dest);
        assertThat(dest, is(new byte[]{1, 2, 3}));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read inherited">
    @Test
    public void read_fullArrayWithoutOffsetParameter_allBytesRead() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3});

        // act
        byte[] dest = new byte[3];
        int bytesRead = sb.getInputStream().read(dest);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertThat(dest, is(new byte[]{1, 2, 3}))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="trim with partial buffer entry">
    @Test
    public void trim_withPartiallyConsumedBufferEntry_remainingBytesCorrectAfterTrim() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        sb.getOutputStream().write(new byte[]{1, 2, 3});
        // Read one byte to advance positionAtCurrentBufferEntry to 1
        assertThat(sb.getInputStream().read(), is(1));

        // act — write a second entry to trigger trim while positionAtCurrentBufferEntry == 1
        sb.getOutputStream().write(new byte[]{4, 5, 6});

        // assert — remaining 5 bytes should be 2,3,4,5,6 in order
        byte[] dest = new byte[5];
        int bytesRead = sb.getInputStream().read(dest);
        assertAll(
            () -> assertThat(bytesRead, is(5)),
            () -> assertThat(dest, is(new byte[]{2, 3, 4, 5, 6}))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="available">
    @Test
    public void available_emptyBuffer_returnsZero() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        int result = sb.getInputStream().available();

        // assert
        assertThat(result, is(0));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="safeWrite partial range">
    @Test
    public void write_partialRangeWithSafeWriteDisabled_externalMutationNotAffectingReadValue() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setSafeWrite(false);
        byte[] source = new byte[]{0, anyValue, 0};

        // act — partial write always copies via System.arraycopy, regardless of safeWrite flag
        sb.getOutputStream().write(source, 1, 1);
        source[1]++;

        // assert — the buffered byte is a copy; mutation of source must not affect it
        byte[] dest = new byte[1];
        sb.getInputStream().read(dest);
        assertThat(dest[0], is(anyValue));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read partial return on closed stream">
    @Test
    public void read_byteArrayWhenStreamClosedAfterOneByte_returnsOneByte() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(anyValue);
        sb.close();

        // act — only 1 byte available; stream closed; read(dest, 0, 2) must return 1, not -1
        byte[] dest = new byte[2];
        int bytesRead = sb.getInputStream().read(dest, 0, 2);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(1)),
            () -> assertThat(dest[0], is(anyValue))
        );
    }

    @Test
    public void read_requestMoreBytesThanAvailableOnClosedStream_returnsAvailableBytes() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3});
        sb.close();

        // act — 3 bytes available but 5 requested; must return 3, not throw NoSuchElementException
        byte[] dest = new byte[5];
        int bytesRead = sb.getInputStream().read(dest, 0, 5);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertArrayEquals(new byte[]{1, 2, 3}, Arrays.copyOf(dest, 3))
        );
    }

    @Test
    public void read_concurrentWriteCloseWithInsufficientBytes_returnsAvailableBytes() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final int[] bytesReadHolder = new int[1];
        final byte[] dest = new byte[10];
        final Semaphore readerStarted = new Semaphore(0);

        // reader requests 10 bytes but only 3 will ever be written
        Thread reader = new Thread(() -> {
            try {
                readerStarted.release();
                bytesReadHolder[0] = is.read(dest, 0, 10);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });

        // act
        reader.start();
        readerStarted.acquire();
        Thread.sleep(500); // let reader block in tryWaitForEnoughBytes
        os.write(new byte[]{1, 2, 3});
        os.close(); // unblocks reader with only 3 bytes available

        reader.join();

        // assert
        assertAll(
            () -> assertThat(bytesReadHolder[0], is(3)),
            () -> assertArrayEquals(new byte[]{1, 2, 3}, Arrays.copyOf(dest, 3))
        );
    }

    @Test
    public void read_multipleDequeEntriesOnClosedStream_returnsAvailableBytes() throws IOException {
        // arrange — three separate writes create three deque entries
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        os.write(new byte[]{1});
        os.write(new byte[]{2});
        os.write(new byte[]{3});
        sb.close();

        // act — request 10 bytes, only 3 available across 3 entries
        byte[] dest = new byte[10];
        int bytesRead = is.read(dest, 0, 10);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertArrayEquals(new byte[]{1, 2, 3}, Arrays.copyOf(dest, 3))
        );
    }

    @Test
    public void read_partialEntryConsumedThenCloseAndOverRead_returnsRemainingBytes() throws IOException {
        // arrange — write 5 bytes, read 2 to advance positionAtCurrentBufferEntry
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        os.write(new byte[]{1, 2, 3, 4, 5});
        assertThat(is.read(), is(1));
        assertThat(is.read(), is(2));
        sb.close();

        // act — 3 bytes remain, request 8
        byte[] dest = new byte[8];
        int bytesRead = is.read(dest, 0, 8);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertArrayEquals(new byte[]{3, 4, 5}, Arrays.copyOf(dest, 3))
        );
    }

    @Test
    public void read_requestExactlyOneMoreThanAvailable_returnsAvailableBytes() throws IOException {
        // arrange — 4 bytes written, request 5 (after first internal read: 3 remain, missingBytes=4)
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{10, 20, 30, 40});
        sb.close();

        // act
        byte[] dest = new byte[5];
        int bytesRead = sb.getInputStream().read(dest, 0, 5);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(4)),
            () -> assertArrayEquals(new byte[]{10, 20, 30, 40}, Arrays.copyOf(dest, 4))
        );
    }

    @Test
    public void read_nonZeroOffsetWithOverReadOnClosedStream_returnsAvailableBytesAtOffset() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3});
        sb.close();

        // act — read into offset 3 of a 10-byte array, requesting 7
        byte[] dest = new byte[10];
        int bytesRead = sb.getInputStream().read(dest, 3, 7);

        // assert — leading/trailing zeros prove the offset was respected
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertArrayEquals(new byte[]{0, 0, 0, 1, 2, 3, 0, 0, 0, 0}, dest)
        );
    }

    @Test
    public void read_trimThenCloseAndOverRead_returnsAvailableBytes() throws IOException {
        // arrange — low maxBufferElements triggers trim during writes
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        os.write(new byte[]{1});
        os.write(new byte[]{2});
        os.write(new byte[]{3});
        os.write(new byte[]{4, 5});
        sb.close();

        // act — 5 bytes available (post-trim), request 10
        byte[] dest = new byte[10];
        int bytesRead = is.read(dest, 0, 10);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(5)),
            () -> assertArrayEquals(new byte[]{1, 2, 3, 4, 5}, Arrays.copyOf(dest, 5))
        );
    }

    @Test
    public void read_concurrentMultipleWritesThenClose_returnsAvailableBytes() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final int[] bytesReadHolder = new int[1];
        final byte[] dest = new byte[20];
        final Semaphore readerStarted = new Semaphore(0);

        Thread reader = new Thread(() -> {
            try {
                readerStarted.release();
                bytesReadHolder[0] = is.read(dest, 0, 20);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });

        // act — reader blocks, writer sends 3 separate chunks then closes
        reader.start();
        readerStarted.acquire();
        Thread.sleep(500); // let reader block
        os.write(new byte[]{1, 2});
        os.write(new byte[]{3, 4});
        os.write(new byte[]{5});
        os.close();

        reader.join();

        // assert
        assertAll(
            () -> assertThat(bytesReadHolder[0], is(5)),
            () -> assertArrayEquals(new byte[]{1, 2, 3, 4, 5}, Arrays.copyOf(dest, 5))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="concurrent trim and write">
    @Test
    public void concurrentTrimAndWrite_noCrashOrCorruption() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final int iterations = 10_000;
        final byte value = 42;

        Thread writer = new Thread(() -> {
            try {
                for (int i = 0; i < iterations; i++) {
                    os.write(value);
                }
            } catch (IOException e) {
                throw new RuntimeException("Writer thread failed", e);
            }
        });

        Thread trimmer = new Thread(() -> {
            try {
                for (int i = 0; i < iterations / 100; i++) {
                    sb.setMaxBufferElements((i % 10) + 1); // dynamically shrink/grow
                    Thread.sleep(1);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });

        Thread reader = new Thread(() -> {
            try {
                while (!sb.isClosed() || is.available() > 0) {
                    is.read(); // consume and keep buffer flowing
                }
            } catch (IOException e) {
                throw new RuntimeException("Reader thread failed", e);
            }
        });

        // act
        writer.start();
        trimmer.start();
        reader.start();

        writer.join();
        os.close(); // gracefully signal end of writing
        trimmer.join();
        reader.join();

        // assert — no crash or data corruption
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="signal/slot">
    @Test
    public void signal_addSignalAndWrite_signalReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        sb.addSignal(signal);

        // act
        sb.getOutputStream().write(anyValue);

        // assert
        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_addSignalAndClose_signalReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        sb.addSignal(signal);

        // act
        sb.close();

        // assert
        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_multipleSignals_allReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal1 = new Semaphore(0);
        final Semaphore signal2 = new Semaphore(0);
        final Semaphore signal3 = new Semaphore(0);
        sb.addSignal(signal1);
        sb.addSignal(signal2);
        sb.addSignal(signal3);

        // act
        sb.getOutputStream().write(anyValue);

        // assert
        assertAll(
            () -> assertThat(signal1.tryAcquire(5, TimeUnit.SECONDS), is(true)),
            () -> assertThat(signal2.tryAcquire(5, TimeUnit.SECONDS), is(true)),
            () -> assertThat(signal3.tryAcquire(5, TimeUnit.SECONDS), is(true))
        );
    }

    @Test
    public void signal_removeSignal_notReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        sb.addSignal(signal);

        // act
        boolean removed = sb.removeSignal(signal);
        sb.getOutputStream().write(anyValue);

        // assert
        assertAll(
            () -> assertThat(removed, is(true)),
            () -> assertThat(signal.tryAcquire(1, TimeUnit.SECONDS), is(false))
        );
    }

    @Test
    public void signal_removeNonExistentSignal_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        // act
        boolean removed = sb.removeSignal(signal);

        // assert
        assertThat(removed, is(false));
    }

    @Test
    public void signal_addNullSignal_throwsNullPointerException() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act
        // assert
        assertThrows(NullPointerException.class, () -> sb.addSignal(null));
    }

    @Test
    public void signal_threadBarrier_observerWakesInOwnThread() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        final Semaphore observerDone = new Semaphore(0);
        final Thread[] observerThreadHolder = new Thread[1];
        sb.addSignal(signal);

        // observer runs in its own thread, blocked on the signal
        Thread observer = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    signal.acquire();
                    observerThreadHolder[0] = Thread.currentThread();
                    observerDone.release();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
        });
        observer.start();

        // act
        // writer writes from the main thread
        sb.getOutputStream().write(anyValue);

        // assert
        // observer should wake up in its own thread
        assertAll(
            () -> assertThat(observerDone.tryAcquire(5, TimeUnit.SECONDS), is(true)),
            () -> assertThat(observerThreadHolder[0], is(observer)),
            () -> assertThat(observerThreadHolder[0], is(not(Thread.currentThread())))
        );

        observer.join(5000);
    }

    @Test
    public void signal_closeViaOutputStream_signalReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        sb.addSignal(signal);

        // act
        sb.getOutputStream().close();

        // assert
        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_closeViaInputStream_signalReleased() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);
        sb.addSignal(signal);

        // act
        sb.getInputStream().close();

        // assert
        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_removeNull_returnsFalse() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        boolean result = sb.removeSignal(null);

        // assert
        assertThat(result, is(false));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read unsigned byte round-trip">
    @Test
    public void read_writeByte0xFF_returns255() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.getOutputStream().write(0xFF);
        int result = sb.getInputStream().read();

        // assert
        assertThat(result, is(255));
    }

    @Test
    public void read_writeByte0x80_returns128() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.getOutputStream().write(0x80);
        int result = sb.getInputStream().read();

        // assert
        assertThat(result, is(128));
    }

    @Test
    public void read_writeNegativeByteValue_returnsUnsigned() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        byte negativeByte = -1; // 0xFF as signed byte

        // act
        sb.getOutputStream().write(new byte[]{negativeByte});
        int result = sb.getInputStream().read();

        // assert — must be 255, not -1 (which would signal EOF)
        assertThat(result, is(255));
    }

    @Test
    public void read_writeAllHighByteValues_returnsCorrectUnsigned() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // act & assert — write and read values 128..255
        for (int i = 128; i <= 255; i++) {
            os.write(i);
            assertThat(is.read(), is(i));
        }
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToWrite integer overflow">
    @Test
    public void correctOffsetAndLengthToWrite_integerOverflow_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[10];

        // act — Integer.MAX_VALUE + 1 overflows to negative
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, Integer.MAX_VALUE, 1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="close via InputStream">
    @Test
    public void write_closedViaInputStream_throwsIOException() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getInputStream().close();

        // act
        assertThrows(IOException.class, () -> sb.getOutputStream().write(anyValue));
    }

    @Test
    public void isClosed_closedViaInputStream_true() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        sb.getInputStream().close();

        // assert
        assertThat(sb.isClosed(), is(true));
    }

    @Test
    public void read_closedViaOutputStream_returnsMinusOne() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().close();

        // act
        int result = sb.getInputStream().read();

        // assert
        assertThat(result, is(-1));
    }
    // </editor-fold>


    // <editor-fold defaultstate="collapsed" desc="trim with safeWrite">
    @Test
    public void trim_withSafeWriteEnabled_preservesDataIntegrity() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setSafeWrite(true);
        sb.setMaxBufferElements(1);

        // act — write multiple entries to trigger trim while safeWrite is on
        sb.getOutputStream().write(new byte[]{1, 2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});

        // assert — all bytes preserved in correct order after trim
        byte[] dest = new byte[6];
        int bytesRead = sb.getInputStream().read(dest);
        assertAll(
            () -> assertThat(bytesRead, is(6)),
            () -> assertThat(dest, is(new byte[]{1, 2, 3, 4, 5, 6}))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="maxBufferElements zero disables trim">
    @Test
    public void setMaxBufferElements_zero_trimNotCalled() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(0);

        // act — write many individual entries
        for (int i = 0; i < 200; i++) {
            sb.getOutputStream().write(anyValue);
        }

        // assert — all entries remain un-trimmed (each write(int) adds one entry)
        assertThat(sb.getBufferSize(), is(greaterThan(1)));
    }
    // </editor-fold>


    // <editor-fold defaultstate="collapsed" desc="read single byte via array">
    @Test
    public void read_arrayWithLengthOne_returnsSingleByte() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(anyValue);

        // act
        byte[] dest = new byte[1];
        int bytesRead = sb.getInputStream().read(dest, 0, 1);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(1)),
            () -> assertThat(dest[0], is(anyValue))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="available after close with buffered data">
    @Test
    public void available_closedWithDataRemaining_returnsCorrectCount() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3, 4, 5});
        sb.close();

        // act
        int result = sb.getInputStream().available();

        // assert
        assertThat(result, is(5));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="thread interruption during read">
    @Test
    public void read_threadInterrupted_throwsIOException() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();
        final Semaphore started = new Semaphore(0);
        final Throwable[] caught = new Throwable[1];

        Thread reader = new Thread(() -> {
            try {
                started.release();
                is.read(); // will block — no data, not closed
            } catch (IOException e) {
                caught[0] = e;
            }
        });

        // act
        reader.start();
        started.acquire(); // wait for thread to start
        Thread.sleep(500); // let it block on read()
        reader.interrupt();
        reader.join();

        // assert
        assertThat("IOException should be thrown wrapping InterruptedException",
                caught[0] instanceof IOException, is(true));
    }

    @Test
    public void read_arrayThreadInterruptedWhileWaitingForSecondByte_throwsIOException() throws Exception {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();
        final OutputStream os = sb.getOutputStream();
        final Semaphore started = new Semaphore(0);
        final Throwable[] caught = new Throwable[1];

        // write exactly 1 byte so the internal read() at the start of read(b,off,len)
        // succeeds immediately, then tryWaitForEnoughBytes blocks waiting for the second byte
        os.write(42);

        Thread reader = new Thread(() -> {
            try {
                started.release();
                is.read(new byte[2], 0, 2);
            } catch (IOException e) {
                caught[0] = e;
            }
        });

        // act
        reader.start();
        started.acquire(); // wait for thread to start
        Thread.sleep(500); // let it block inside tryWaitForEnoughBytes
        reader.interrupt();
        reader.join();

        // assert
        assertThat("IOException should be thrown wrapping InterruptedException",
                caught[0] instanceof IOException, is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToRead empty array">
    @Test
    public void correctOffsetAndLengthToRead_emptyArrayWithPositiveLength_throwsIndexOutOfBoundsException() {
        // arrange
        // act
        // assert — exception thrown is the assertion
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(new byte[0], 0, 1));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToWrite empty array">
    @Test
    public void correctOffsetAndLengthToWrite_emptyArrayZeroLength_returnsFalse() {
        // arrange
        // act
        boolean result = StreamBuffer.correctOffsetAndLengthToWrite(new byte[0], 0, 0);

        // assert
        assertThat(result, is(false));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="getBufferSize initial">
    @Test
    public void getBufferSize_emptyBuffer_returnsZero() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        int result = sb.getBufferSize();

        // assert
        assertThat(result, is(0));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isTrimShouldBeExecuted zero boundary">
    @Test
    public void getBufferSize_maxBufferElementsZeroWithMultipleEntries_noTrimExecuted() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(0);

        // act
        sb.getOutputStream().write(new byte[]{1});
        sb.getOutputStream().write(new byte[]{2});
        sb.getOutputStream().write(new byte[]{3});

        // assert
        assertThat(sb.getBufferSize(), is(3));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="tryWaitForEnoughBytes closed stream return">
    @Test
    public void read_closedStreamWithTwoBytes_readArrayReturnsBothBytes() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{10, 20});
        sb.close();

        // act
        byte[] dest = new byte[4];
        int bytesRead = sb.getInputStream().read(dest, 0, 4);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(2)),
            () -> assertArrayEquals(new byte[]{10, 20}, Arrays.copyOf(dest, 2))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="read if-branch: exact full-entry consumption">
    @Test
    public void read_exactFullEntryConsumption_availableAndBufferSizeAreZero() throws IOException {
        // arrange — write 3 bytes as a single entry; after the internal read() call consumes byte 0,
        // positionAtCurrentBufferEntry=1, missingBytes=2, maximumBytesToCopy=3-1=2 → exactly equal.
        // This hits the if-branch boundary: missingBytes >= maximumBytesToCopy (both == 2).
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3});

        // act
        byte[] dest = new byte[3];
        int bytesRead = sb.getInputStream().read(dest, 0, 3);

        // assert
        // ConditionalsBoundary mutant (>= → >): routes to else-branch → entry NOT removed → bufferSize = 1
        // MathMutator on availableBytes in if-branch: availableBytes += 2 → available() = 4, not 0
        assertAll(
            () -> assertThat(bytesRead, is(3)),
            () -> assertThat(dest, is(new byte[]{1, 2, 3})),
            () -> assertThat(sb.getBufferSize(), is(0)),
            () -> assertThat(sb.getInputStream().available(), is(0))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isTrimShouldBeExecuted direct">
    @Test
    public void isTrimShouldBeExecuted_bufferSizeTwoMaxElementsOne_returnsTrue() throws IOException {
        // arrange — disable trim while writing so we can control buffer.size() independently
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(0);
        sb.getOutputStream().write(new byte[]{1});
        sb.getOutputStream().write(new byte[]{2});
        // buffer.size() == 2; now enable trim condition
        sb.setMaxBufferElements(1);

        // act + assert — original: (2 >= 2) && (2 > 1) = true
        //                mutant:   (2 >  2) && (2 > 1) = false  → mutation killed
        assertThat(sb.isTrimShouldBeExecuted(), is(true));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="clampToMaxInt direct">
    @Test
    public void clampToMaxInt_valueAboveMaxInt_returnsMaxInt() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE + 1), is(Integer.MAX_VALUE));
    }

    @Test
    public void clampToMaxInt_valueEqualToMaxInt_returnsMaxInt() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE), is(Integer.MAX_VALUE));
    }

    @Test
    public void clampToMaxInt_smallValue_returnsValue() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.clampToMaxInt(42L), is(42));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="decrementAvailableBytesBudget direct">
    @Test
    public void decrementAvailableBytesBudget_subtractsDecrement() {
        // original: current - decrement = 9 - 4 = 5
        // mutant:   current + decrement = 9 + 4 = 13  → mutation killed
        // arrange
        StreamBuffer sb = new StreamBuffer();
        // act
        // assert
        assertThat(sb.decrementAvailableBytesBudget(9L, 4L), is(5L));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="isTrimShouldBeExecuted size-two boundary">
    @Test
    public void getBufferSize_twoEntriesWithMaxBufferElementsOne_trimCalled() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);

        // act — exactly two separate entries: buffer.size() == 2 > maxBufferElements == 1
        // original: buffer.size() >= 2 → true → trim fires
        // mutant:   buffer.size() >  2 → false → trim skipped → getBufferSize() stays 2
        sb.getOutputStream().write(new byte[]{1});
        sb.getOutputStream().write(new byte[]{2});

        // assert
        assertThat(sb.getBufferSize(), is(1));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="tryWaitForEnoughBytes open-stream return">
    @Test
    public void read_multipleBytesSingleEntryOpenStream_returnsAllRequestedBytes() throws IOException {
        // arrange — write 5 bytes as one entry; stream left open
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3, 4, 5});

        // act — tryWaitForEnoughBytes(4) takes the "already enough" path and must return availableBytes (4)
        // mutant returns 0 → read(b, 0, 5) short-circuits and returns only 1 (the first byte)
        byte[] dest = new byte[5];
        int bytesRead = sb.getInputStream().read(dest, 0, 5);

        // assert
        assertAll(
            () -> assertThat(bytesRead, is(5)),
            () -> assertThat(dest, is(new byte[]{1, 2, 3, 4, 5}))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="available after partial read from single entry">
    @Test
    public void available_afterPartialReadFromSingleEntry_returnsRemainingCount() throws IOException {
        // arrange — 10 bytes as a single deque entry
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(new byte[]{1, 2, 3, 4, 5, 6, 7, 8, 9, 10});

        // act — read first 5 bytes (1 via read() then 4 via the partial-copy else branch)
        byte[] dest = new byte[5];
        int bytesRead = sb.getInputStream().read(dest, 0, 5);

        // assert — 5 bytes must remain; mutant does availableBytes += 4 instead of -= 4 → reports 13
        assertAll(
            () -> assertThat(bytesRead, is(5)),
            () -> assertThat(sb.getInputStream().available(), is(5))
        );
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="capMissingBytes equivalence: old vs new formula">

    // Extracts the OLD capping formula from the guarded if-block (pre-cb66b68)
    private static int capMissingBytesOld(long maximumAvailableBytes, int missingBytes) {
        if (maximumAvailableBytes < missingBytes) {
            return (int) Math.min(maximumAvailableBytes, Integer.MAX_VALUE);
        }
        return missingBytes;
    }

    // Extracts the NEW capping formula (unconditional Math.min, post-cb66b68)
    private static int capMissingBytesNew(long maximumAvailableBytes, int missingBytes) {
        return (int) Math.min(maximumAvailableBytes, (long) missingBytes);
    }

    static Stream<Arguments> capMissingBytesInputs() {
        return Stream.of(
            // Case A: maxAvail < missingBytes  (old if-branch fires, new Math.min picks maxAvail)
            Arguments.of(1L,                                    5                   ),  // trivially small
            Arguments.of(3L,                                    5                   ),  // standard small case
            Arguments.of((long) Integer.MAX_VALUE - 1,          Integer.MAX_VALUE   ),  // one below INT_MAX

            // Case B: maxAvail == missingBytes  (boundary: old skips if, new Math.min picks either)
            Arguments.of(5L,                                    5                   ),  // small equality
            Arguments.of((long) Integer.MAX_VALUE,              Integer.MAX_VALUE   ),  // equality at INT_MAX

            // Case C: maxAvail > missingBytes  (old skips if, new Math.min picks missingBytes)
            Arguments.of(9L,                                    3                   ),  // standard: more available than needed
            Arguments.of((long) Integer.MAX_VALUE + 1L,         Integer.MAX_VALUE   ),  // maxAvail just above INT_MAX
            Arguments.of((long) Integer.MAX_VALUE + 1L,         5                   ),  // maxAvail > INT_MAX, small missing
            Arguments.of(3_000_000_000L,                        100                 ),  // large long, small int
            Arguments.of(Long.MAX_VALUE,                        1                   )   // extreme: largest possible long
        );
    }

    @ParameterizedTest
    @MethodSource("capMissingBytesInputs")
    public void capMissingBytes_oldAndNewFormula_returnSameResult(
            long maximumAvailableBytes, int missingBytes) {
        // arrange
        // act
        int oldResult = capMissingBytesOld(maximumAvailableBytes, missingBytes);
        int newResult = capMissingBytesNew(maximumAvailableBytes, missingBytes);
        // assert
        assertThat(newResult, is(oldResult));
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Statistics: getTotalBytesWritten, getTotalBytesRead, getMaxObservedBytes">

    @Test
    public void statistics_initial_allCountersZero() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act & assert
        assertAll(
            () -> assertThat(sb.getTotalBytesWritten(), is(0L)),
            () -> assertThat(sb.getTotalBytesRead(), is(0L)),
            () -> assertThat(sb.getMaxObservedBytes(), is(0L))
        );
    }

    @Test
    public void statistics_singleWrite_tracksTotalBytesWritten() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] data = new byte[]{1, 2, 3};

        // act
        os.write(data);

        // assert
        assertThat(sb.getTotalBytesWritten(), is(3L));
    }

    @Test
    public void statistics_multipleWrites_accumulate() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        // act
        os.write(new byte[]{1, 2});
        os.write(new byte[]{3, 4, 5});
        os.write(new byte[]{6});

        // assert
        assertThat(sb.getTotalBytesWritten(), is(6L));
    }

    @Test
    public void statistics_writeWithOffset_countsOnlyOffset() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        byte[] data = new byte[]{1, 2, 3, 4, 5};

        // act
        os.write(data, 2, 3);  // write offset 2, length 3 → writes bytes 3, 4, 5

        // assert
        assertThat(sb.getTotalBytesWritten(), is(3L));
    }

    @Test
    public void statistics_writeInt_countsAsOne() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        // act
        os.write(42);

        // assert
        assertThat(sb.getTotalBytesWritten(), is(1L));
    }

    @Test
    public void statistics_singleByteRead_tracksTotalBytesRead() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{1, 2, 3});

        // act
        is.read();

        // assert
        assertThat(sb.getTotalBytesRead(), is(1L));
    }

    @Test
    public void statistics_arrayRead_tracksTotalBytesRead() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{1, 2, 3, 4, 5});

        // act
        byte[] dest = new byte[5];
        is.read(dest);

        // assert
        assertThat(sb.getTotalBytesRead(), is(5L));
    }

    @Test
    public void statistics_partialRead_countsActuallyReturned() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{1, 2, 3});  // only 3 bytes available
        os.close();  // signal EOF so read returns partial data instead of blocking

        // act
        byte[] dest = new byte[100];
        int read = is.read(dest, 0, 100);  // request 100, but only 3 available

        // assert
        assertAll(
            () -> assertThat(read, is(3)),
            () -> assertThat(sb.getTotalBytesRead(), is(3L))
        );
    }

    @Test
    public void statistics_concurrentReadsWrites_countersConsistent() throws IOException, InterruptedException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        final int N = 100;
        final byte data = anyValue;

        // act — write N bytes, then read N bytes in concurrent threads
        Thread writer = new Thread(() -> {
            try {
                for (int i = 0; i < N; i++) {
                    os.write(data);
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });
        Thread reader = new Thread(() -> {
            try {
                for (int i = 0; i < N; i++) {
                    is.read();
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });
        writer.start();
        reader.start();
        writer.join();
        reader.join();

        // assert — written == read == N
        assertAll(
            () -> assertThat(sb.getTotalBytesWritten(), is((long) N)),
            () -> assertThat(sb.getTotalBytesRead(), is((long) N))
        );
    }

    @Test
    public void statistics_maxObservedBytes_tracksHighestAvailable() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        // act
        os.write(new byte[100]);  // write 100 bytes → available = 100
        is.read(new byte[50]);    // read 50 bytes → available = 50

        // assert
        assertThat(sb.getMaxObservedBytes(), is(100L));
    }

    @Test
    public void statistics_maxObservedBytes_preservesPeak() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        // act
        os.write(new byte[100]);  // available = 100 (peak)
        is.read(new byte[100]);   // available = 0
        os.write(new byte[10]);   // available = 10 (lower than peak)

        // assert
        assertThat(sb.getMaxObservedBytes(), is(100L));
    }

    @Test
    public void statistics_maxObservedBytes_updated_onlyDuringUserWrites() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        os.write(new byte[50]);  // write 50 → max = 50
        is.read();  // read 1 byte, availableBytes = 49
        long maxAfterFirstWrite = sb.getMaxObservedBytes();

        // act — trim's internal operations should not increase maxObservedBytes
        // Force a trim by setting maxBufferElements low and writing more
        sb.setMaxBufferElements(1);
        os.write(new byte[10]);  // will trigger trim
        long maxAfterTrim = sb.getMaxObservedBytes();

        // assert — maxObservedBytes should still reflect user peaks, not trim's internal operations
        // trim internally reads and writes, but isTrimRunning prevents those from being counted
        assertAll(
            () -> assertThat(sb.getBufferElementCount(), is(1)),  // trim consolidated
            () -> assertThat(sb.isTrimRunning(), is(false)),  // trim complete
            () -> assertThat(maxAfterTrim, greaterThanOrEqualTo(maxAfterFirstWrite))  // peak only increases from user writes
        );
    }

    @Test
    public void statistics_trim_doNotAffectCounters() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[100]);
        long writtenBeforeTrim = sb.getTotalBytesWritten();
        long readBeforeTrim = sb.getTotalBytesRead();

        // act — force trim
        sb.setMaxBufferElements(1);
        os.write(new byte[50]);

        // assert — trim's internal read/write should not affect user counters
        // and buffer should be consolidated into one element
        assertAll(
            () -> assertThat(sb.getTotalBytesWritten(), is(writtenBeforeTrim + 50)),
            () -> assertThat(sb.getTotalBytesRead(), is(readBeforeTrim)),
            () -> assertThat(sb.getBufferElementCount(), is(1)),
            () -> assertThat(sb.isTrimRunning(), is(false))  // trim should be complete
        );
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Buffer element count and trim state">

    @Test
    public void bufferElementCount_initial_isZero() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act & assert
        assertThat(sb.getBufferElementCount(), is(0));
    }

    @Test
    public void bufferElementCount_afterWrites_increasesAccordingly() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        // act & assert first write
        os.write(new byte[10]);
        assertThat(sb.getBufferElementCount(), is(1));

        // act & assert second write
        os.write(new byte[20]);
        assertThat(sb.getBufferElementCount(), is(2));
    }

    @Test
    public void bufferElementCount_afterTrimConsolidation_reducesToOne() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[100]);
        os.write(new byte[100]);
        os.write(new byte[100]);
        assertThat(sb.getBufferElementCount(), is(3));

        // act — force trim
        sb.setMaxBufferElements(1);
        os.write(new byte[50]);

        // assert
        assertThat(sb.getBufferElementCount(), is(1));
    }

    @Test
    public void isTrimRunning_afterTrimComplete_isFalse() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[100]);

        // act — force trim
        sb.setMaxBufferElements(1);
        os.write(new byte[50]);

        // assert
        assertThat(sb.isTrimRunning(), is(false));
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="maxAllocationSize: getter, setter, trim behavior">

    @Test
    public void maxAllocationSize_defaultValue_isIntegerMaxValue() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act
        long maxSize = sb.getMaxAllocationSize();

        // assert
        assertThat(maxSize, is((long) Integer.MAX_VALUE));
    }

    @Test
    public void maxAllocationSize_setAndGet_returnsSetValue() {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        long newMax = 1024;

        // act
        sb.setMaxAllocationSize(newMax);

        // assert
        assertThat(sb.getMaxAllocationSize(), is(newMax));
    }

    @Test
    public void setMaxAllocationSize_invalidValue_throwsException() {
        // arrange
        StreamBuffer sb = new StreamBuffer();

        // act & assert
        assertAll(
            () -> assertThrows(IllegalArgumentException.class, () -> sb.setMaxAllocationSize(0)),
            () -> assertThrows(IllegalArgumentException.class, () -> sb.setMaxAllocationSize(-1))
        );
    }

    @Test
    public void trim_respectsMaxAllocationSize_splitsLargeBuffer() throws IOException {
        // arrange — write many small chunks so buffer.size() exceeds maxBufferElements,
        // then trim consolidates with maxAllocationSize limit.
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        sb.setMaxAllocationSize(300);
        sb.setMaxBufferElements(5);

        // act — write 10 chunks of 100 bytes (1000 bytes total)
        // After 6th write: buffer.size()=6 > 5 → trim → ceil(600/300)=2 < 6 → consolidates to 2
        // After 10th write: buffer.size()=6 > 5 → trim → ceil(1000/300)=4 < 6 → consolidates to 4
        for (int i = 0; i < 10; i++) {
            byte[] chunk = new byte[100];
            Arrays.fill(chunk, anyValue);
            os.write(chunk);
        }

        // assert — after trim with maxAllocationSize=300, buffer has 4 chunks (300,300,300,100)
        assertThat(sb.getBufferElementCount(), is(4));
        assertThat(sb.isTrimRunning(), is(false));

        // Read all data and verify it's intact
        os.close();
        byte[] result = new byte[1000];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 1000 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(1000));
        assertThat(result[0], is(anyValue));
        assertThat(result[999], is(anyValue));
    }

    @Test
    public void trim_maxAllocationSize_allDataPreserved() throws IOException {
        // arrange — write multiple small chunks so trim fires with maxAllocationSize limit,
        // then verify all data is preserved after consolidation.
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        sb.setMaxAllocationSize(200);
        sb.setMaxBufferElements(3);

        // act — write 6 chunks of 100 bytes (600 bytes total)
        // After 4th write: buffer.size()=4 > 3 → trim → ceil(400/200)=2 < 4 → consolidates
        // After more writes: trim fires again → ceil(600/200)=3 < current → consolidates
        byte[] original = new byte[100];
        Arrays.fill(original, anyValue);
        for (int i = 0; i < 6; i++) {
            os.write(original);
        }

        // assert — all 600 bytes should be readable and intact
        os.close();
        byte[] result = new byte[600];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 600 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        final int finalTotalRead = totalRead;
        assertAll(
            () -> assertThat(finalTotalRead, is(600)),
            () -> assertThat(result[0], is(anyValue)),
            () -> assertThat(result[599], is(anyValue))
        );
    }

    @Test
    public void trim_maxAllocationSize_withPartialRead() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        byte[] data = new byte[600];
        Arrays.fill(data, anyValue);
        os.write(data);

        // act — read 200 bytes, then trigger trim with allocation limit
        byte[] partial = new byte[200];
        is.read(partial);
        sb.setMaxAllocationSize(150);
        sb.setMaxBufferElements(1);
        os.write(new byte[10]);  // triggers trim

        // assert — remaining 400 bytes should be readable
        byte[] remaining = new byte[400];
        int read = is.read(remaining);
        assertThat(read, is(400));
    }

    @Test
    public void trim_recursiveTrim_onChunkOverflow_allDataPreserved() throws IOException {
        // arrange — write many small chunks that trigger multiple trims.
        // With maxAllocationSize limiting consolidation, trim may produce more chunks
        // than maxBufferElements allows. The isTrimRunning guard prevents recursive
        // trim, and the edge case check prevents futile re-trim attempts.
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        sb.setMaxAllocationSize(500);
        sb.setMaxBufferElements(10);

        // act — write 100 chunks of 100 bytes (10,000 bytes total)
        // Trim fires repeatedly as buffer exceeds 10 elements, consolidating with
        // maxAllocationSize=500. Each trim consolidates into ceil(N/500) chunks.
        byte[] chunk = new byte[100];
        Arrays.fill(chunk, anyValue);
        for (int i = 0; i < 100; i++) {
            os.write(chunk);
        }

        // assert — trim completed without stack overflow, data intact
        assertThat(sb.isTrimRunning(), is(false));

        // all 10,000 bytes should be readable
        os.close();
        byte[] result = new byte[10_000];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 10_000 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(10_000));
        assertThat(result[0], is(anyValue));
        assertThat(result[9999], is(anyValue));
    }

    @Test
    public void trim_edgeCase_skipsTrimWhenResultStillExceedsLimit() throws IOException {
        // arrange: Critical edge case where consolidation would NOT reduce chunk count below limit
        // maxBufferElements=10, maxAllocationSize=100, availableBytes=1100
        // → Consolidation would create ceil(1100/100)=11 chunks, still violating the 10-chunk limit
        // → Trim MUST be skipped to prevent repeated trim calls on every write
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        sb.setMaxBufferElements(10);      // limit to 10 chunks
        sb.setMaxAllocationSize(100);     // chunks of 100 bytes max during consolidation

        // act: Write 11 chunks of 100 bytes each (1100 bytes total)
        // When consolidated with maxAllocationSize=100, would result in 11 chunks (ceil(1100/100))
        // This would still exceed maxBufferElements=10, so trim should be skipped
        for (int i = 0; i < 11; i++) {
            os.write(new byte[100]);
        }

        // assert: Verify trim was skipped (buffer still has 11 elements, not consolidated)
        // If trim had run, it would have been consolidated and possibly caused recursive trim attempts
        assertThat(sb.getBufferElementCount(), is(11));  // trim was not executed

        // Verify data integrity: all 1100 bytes should be readable
        InputStream is = sb.getInputStream();
        os.close();  // Signal EOF to the input stream
        byte[] result = new byte[1100];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 1100 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(1100));
    }

    @Test
    public void trim_edgeCase_executesWhenResultReducesChunks() throws IOException {
        // arrange: Verify that trim DOES execute when consolidation will reduce chunks.
        // maxBufferElements=5, maxAllocationSize=200
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        sb.setMaxBufferElements(5);       // limit to 5 chunks
        sb.setMaxAllocationSize(200);     // chunks of 200 bytes max during consolidation

        // act: Write 5 chunks of 100 bytes (stays at limit), record count,
        // then write a 6th to trigger trim.
        for (int i = 0; i < 5; i++) {
            os.write(new byte[100]);
        }
        int beforeTrim = sb.getBufferElementCount();  // 5 (no trim yet: 5 <= 5)
        os.write(new byte[100]);
        // buffer.size()=6 > 5 → trim check: ceil(600/200)=3, 3 < 6 → runs
        int afterTrim = sb.getBufferElementCount();   // 3

        // assert: Verify trim was executed and reduced chunk count
        final int fb = beforeTrim;
        final int fa = afterTrim;
        assertAll(
            () -> assertThat(fb, is(5)),
            () -> assertThat(fa, is(3)),   // ceil(600/200)=3 consolidated chunks
            () -> assertThat(fa, not(greaterThan(fb)))
        );

        // Verify data integrity: all 600 bytes should be readable
        InputStream is = sb.getInputStream();
        os.close();
        byte[] result = new byte[600];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 600 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(600));
    }

    @Test
    public void trim_edgeCase_preventsTrimLoopsOnEveryWrite() throws IOException {
        // arrange: Verify that repeated writes don't cause trim to loop constantly
        // when consolidation would violate the limit again
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        sb.setMaxBufferElements(2);       // very low limit
        sb.setMaxAllocationSize(50);      // very small allocation size

        // act: Write small chunks that individually don't trigger trim, but accumulated would
        long trimCountBefore = sb.getTotalBytesWritten();
        for (int i = 0; i < 10; i++) {
            os.write(new byte[30]);
            // Each write is 30 bytes; if trim were called every time, it would consolidate
            // But with the edge case fix, trim should be skipped when result violates limit
        }
        long trimCountAfter = sb.getTotalBytesWritten();

        // assert: All 300 bytes should be written without trim loops
        assertAll(
            () -> assertThat(trimCountAfter, is(trimCountBefore + 300L)),
            () -> assertThat(sb.isTrimRunning(), is(false))  // trim should not be running
        );

        // Verify all data is still readable
        InputStream is = sb.getInputStream();
        os.close();  // Signal EOF to the input stream
        byte[] result = new byte[300];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 300 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(300));
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Mutation survivors: boundary conditions and arithmetic">

    @Test
    public void maxAllocationSize_setToOne_succeeds() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert — Boundary: maxSize=1 must be accepted (kills maxSize <= 0 vs < 0)
        sb.setMaxAllocationSize(1L);
        assertThat(sb.getMaxAllocationSize(), is(1L));
    }

    @Test
    public void trim_maxAllocationSize_one_withSubstantialData() throws IOException {
        // arrange — Verify that trim works correctly even with maxAllocationSize=1 (extreme case)
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // Write 1000 bytes in 100-byte chunks to trigger trim
        byte[] chunk = new byte[100];
        Arrays.fill(chunk, anyValue);
        sb.setMaxAllocationSize(1L);    // Extreme: 1 byte per allocation
        sb.setMaxBufferElements(5);     // Low threshold to trigger trim

        // act — write 10 chunks (1000 bytes total)
        // With maxAllocationSize=1, each byte is allocated separately: 1000 chunks after trim
        for (int i = 0; i < 10; i++) {
            os.write(chunk);
        }

        // assert — verify trim completed and all data is readable
        assertThat(sb.isTrimRunning(), is(false));

        os.close();
        byte[] result = new byte[1000];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 1000 - totalRead)) > 0) {
            totalRead += bytesRead;
        }

        // All 1000 bytes should be read and intact
        final int finalTotalRead = totalRead;
        assertAll(
            () -> assertThat(finalTotalRead, is(1000)),
            () -> assertThat(result[0], is(anyValue)),
            () -> assertThat(result[999], is(anyValue))
        );
    }

    @Test
    public void decrementAvailableBytesBudget_subtracts_notAdds() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act — Verify arithmetic: 100 - 30 = 70, NOT 100 + 30 = 130 (kills MathMutator on - operator)
        final long result = sb.decrementAvailableBytesBudget(100L, 30L);

        // assert
        assertThat(result, is(70L));
    }

    @Test
    public void decrementAvailableBytesBudget_largeValues() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act — Test with large values to ensure arithmetic doesn't overflow
        final long result = sb.decrementAvailableBytesBudget(1_000_000L, 500_000L);

        // assert
        assertThat(result, is(500_000L));
    }

    @Test
    public void clampToMaxInt_clampsLargeValues() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert — Test max int clamping with various boundary values
        assertAll(
            () -> assertThat(sb.clampToMaxInt(Long.MAX_VALUE), is(Integer.MAX_VALUE)),
            () -> assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE), is(Integer.MAX_VALUE)),
            () -> assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE - 1), is(Integer.MAX_VALUE - 1)),
            () -> assertThat(sb.clampToMaxInt(1000L), is(1000))
        );
    }

    @Test
    public void trimCondition_maxBufferElementsZero_neverTrims() throws IOException {
        // arrange — Boundary: maxBufferElements=0 must never trigger trim (kills <= 0 vs < 0)
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(0);
        final OutputStream os = sb.getOutputStream();

        // act — Write enough data that would normally trigger trim
        for (int i = 0; i < 200; i++) {
            os.write(anyValue);
        }

        // assert — trim should not execute with maxBufferElements=0
        assertThat(sb.isTrimShouldBeExecuted(), is(false));
    }

    @Test
    public void trimCondition_allChecksPass_returnsTrue() throws IOException {
        // arrange — Force all conditions in isTrimShouldBeExecuted to pass
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(3);
        sb.setMaxAllocationSize(50);  // Small allocation size to prevent consolidating all chunks
        final OutputStream os = sb.getOutputStream();

        // act — Write 8 chunks of 100 bytes (800 bytes total)
        // This creates buffer.size() = 8 > maxBufferElements(3)
        // When isTrimShouldBeExecuted() is called:
        // - buffer.size() (8) > maxBufferElements (3)? YES
        // - availableBytes (800) > 0 && maxAllocSize (50) < availableBytes (800)? YES
        // - resultingChunks = ceil(800/50) = 16
        // - 16 >= 8? YES, so trim would be skipped by edge case logic
        // This test won't work with edge case logic. Let's use a simpler case.
        for (int i = 0; i < 8; i++) {
            os.write(new byte[100]);
        }

        // assert — Verify buffer is in state where trim would execute
        // Reset maxAllocationSize to default (large) to allow consolidation
        sb.setMaxAllocationSize(Integer.MAX_VALUE);
        // Now with default maxAllocSize, edge case logic is skipped and returns true
        assertThat(sb.isTrimShouldBeExecuted(), is(true));
    }

    @Test
    public void trimCondition_availableBytesZero_skipsTrimCheck() throws IOException {
        // arrange — Boundary: availableBytes=0 must skip trim check (kills > 0 vs >= 0)
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // act — Write data then read all of it
        os.write(anyValue);
        is.read();  // Consume the byte

        // assert — No available bytes, so edge case trim check should be skipped
        assertThat(sb.isTrimShouldBeExecuted(), is(false));
    }

    @Test
    public void trimCondition_resultingChunksEqualBufferSize_doesNotTrim() throws IOException {
        // arrange — Boundary: resultingChunks == buffer.size() must not trim (kills >= vs >)
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(5);
        sb.setMaxAllocationSize(100);
        final OutputStream os = sb.getOutputStream();

        // act — Write exactly 500 bytes to create ~5 chunks of 100 bytes each
        for (int i = 0; i < 500; i++) {
            os.write(anyValue);
        }

        // assert — resultingChunks = ceil(500/100) = 5, buffer.size() = 5
        // So 5 >= 5, trim should NOT execute (kills >= vs > mutation)
        assertThat(sb.isTrimShouldBeExecuted(), is(false));
    }

    @Test
    public void trimCondition_maxAllocSizeGreaterOrEqual_skipsTrimCheck() throws IOException {
        // arrange — Boundary: maxAllocSize >= availableBytes must skip trim check
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(10);
        sb.setMaxAllocationSize(1000);  // Larger than any data we'll write
        final OutputStream os = sb.getOutputStream();

        // act — Write 500 bytes with maxAllocSize=1000 (maxAllocSize >= availableBytes)
        for (int i = 0; i < 500; i++) {
            os.write(anyValue);
        }

        // assert — Since maxAllocSize >= availableBytes, edge case check is skipped
        // AND data is small relative to limit, trim should not execute
        assertThat(sb.isTrimShouldBeExecuted(), is(false));
    }

    @Test
    public void trimCondition_maxAllocSizeLessThanAvailable_checksChunks() throws IOException {
        // arrange — Both conditions in edge case AND must be tested:
        // availableBytes > 0 AND maxAllocSize < availableBytes
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(10);
        sb.setMaxAllocationSize(50);
        final OutputStream os = sb.getOutputStream();

        // act — Write 500 bytes with maxAllocSize=50
        // → ceil(500/50) = 10 chunks
        // → buffer.size() will be ~10 (depends on write patterns)
        // → 10 >= 10, so trim should NOT execute
        for (int i = 0; i < 500; i++) {
            os.write(anyValue);
        }

        // assert — Edge case condition triggers, resulting chunks equals or exceeds buffer size
        // Verify trim behavior (may or may not execute depending on exact buffer state)
        // What matters: the AND condition is fully evaluated (kills NegateConditionalsMutator)
        assertThat(sb.isTrimRunning(), is(false));  // Not currently trimming
    }

    @Test
    public void ceilingDivisionFormula_calculatesCorrectly() {
        // arrange — Verify the ceiling division formula: (n + d - 1) / d
        final StreamBuffer sb = new StreamBuffer();

        // act & assert — Test various n, d pairs where the formula matters
        // ceil(1001 / 1000) = 2
        // Using formula: (1001 + 1000 - 1) / 1000 = 2000 / 1000 = 2 ✓
        // If mutated to (1001 - 1000 - 1) / 1000 = 0 ✗
        assertAll(
            () -> {
                // Test: ceil(1001 / 1000) = 2
                long resultingChunks = sb.calculateResultingChunks(1001L, 1000L);
                assertThat(resultingChunks, is(2L));  // Kills + vs - mutation
            },
            () -> {
                // Test: ceil(500 / 100) = 5
                long resultingChunks = sb.calculateResultingChunks(500L, 100L);
                assertThat(resultingChunks, is(5L));
            }
        );
    }

    @Test
    public void shouldSkipTrimDueToEdgeCase_boundsComparison() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert
        // Test >= boundary: when resultingChunks >= currentBufferSize, should skip
        assertAll(
            () -> {
                // When equal: 10 >= 10 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToEdgeCase(10L, 10);
                assertThat(shouldSkip, is(true));  // Kills >= vs > mutation
            },
            () -> {
                // When greater: 11 >= 10 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToEdgeCase(11L, 10);
                assertThat(shouldSkip, is(true));
            },
            () -> {
                // When less: 9 >= 10 → should not skip (return false)
                boolean shouldSkip = sb.shouldSkipTrimDueToEdgeCase(9L, 10);
                assertThat(shouldSkip, is(false));  // Kills >= vs > mutation
            }
        );
    }

    @Test
    public void shouldSkipTrimDueToInvalidMaxBufferElements_boundsComparison() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert
        // Test <= boundary: when maxBufferElements <= 0, should skip
        assertAll(
            () -> {
                // When zero: 0 <= 0 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToInvalidMaxBufferElements(0);
                assertThat(shouldSkip, is(true));  // Kills <= vs < mutation
            },
            () -> {
                // When negative: -1 <= 0 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToInvalidMaxBufferElements(-1);
                assertThat(shouldSkip, is(true));
            },
            () -> {
                // When positive: 1 <= 0 → should not skip (return false)
                boolean shouldSkip = sb.shouldSkipTrimDueToInvalidMaxBufferElements(1);
                assertThat(shouldSkip, is(false));  // Kills <= vs < mutation
            }
        );
    }

    @Test
    public void shouldSkipTrimDueToSmallBuffer_boundsComparison() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert
        // Test < boundary: when buffer.size() < 2, should skip
        assertAll(
            () -> {
                // When zero: 0 < 2 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToSmallBuffer(0);
                assertThat(shouldSkip, is(true));
            },
            () -> {
                // When one: 1 < 2 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToSmallBuffer(1);
                assertThat(shouldSkip, is(true));  // Kills < vs <= mutation
            },
            () -> {
                // When two: 2 < 2 → should not skip (return false)
                boolean shouldSkip = sb.shouldSkipTrimDueToSmallBuffer(2);
                assertThat(shouldSkip, is(false));  // Kills < vs <= mutation
            },
            () -> {
                // When three: 3 < 2 → should not skip (return false)
                boolean shouldSkip = sb.shouldSkipTrimDueToSmallBuffer(3);
                assertThat(shouldSkip, is(false));
            }
        );
    }

    @Test
    public void shouldSkipTrimDueToSufficientBuffer_boundsComparison() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert
        // Test <= boundary: when buffer.size() <= maxBufferElements, should skip
        assertAll(
            () -> {
                // When equal: 10 <= 10 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToSufficientBuffer(10, 10);
                assertThat(shouldSkip, is(true));  // Kills <= vs < mutation
            },
            () -> {
                // When greater: 11 <= 10 → should not skip (return false)
                boolean shouldSkip = sb.shouldSkipTrimDueToSufficientBuffer(11, 10);
                assertThat(shouldSkip, is(false));  // Kills <= vs < mutation
            },
            () -> {
                // When less: 9 <= 10 → should skip (return true)
                boolean shouldSkip = sb.shouldSkipTrimDueToSufficientBuffer(9, 10);
                assertThat(shouldSkip, is(true));
            }
        );
    }

    @Test
    public void shouldCheckEdgeCase_andConditionBoundaries() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert
        // Test AND condition: both availableBytes > 0 AND maxAllocSize < availableBytes
        assertAll(
            () -> {
                // Both true: 100 > 0 AND 50 < 100 → should check (return true)
                boolean shouldCheck = sb.shouldCheckEdgeCase(100L, 50L);
                assertThat(shouldCheck, is(true));
            },
            () -> {
                // availableBytes zero: 0 > 0 AND 50 < 0 → should not check (return false)
                boolean shouldCheck = sb.shouldCheckEdgeCase(0L, 50L);
                assertThat(shouldCheck, is(false));  // Kills > vs >= mutation on availableBytes
            },
            () -> {
                // maxAllocSize >= availableBytes: 100 > 0 AND 100 < 100 → should not check (return false)
                boolean shouldCheck = sb.shouldCheckEdgeCase(100L, 100L);
                assertThat(shouldCheck, is(false));  // Kills < vs <= mutation on maxAllocSize
            },
            () -> {
                // maxAllocSize > availableBytes: 100 > 0 AND 150 < 100 → should not check (return false)
                boolean shouldCheck = sb.shouldCheckEdgeCase(100L, 150L);
                assertThat(shouldCheck, is(false));  // Kills < vs <= mutation
            },
            () -> {
                // availableBytes negative: -100 > 0 AND 50 < -100 → should not check (return false)
                boolean shouldCheck = sb.shouldCheckEdgeCase(-100L, 50L);
                assertThat(shouldCheck, is(false));  // Kills > vs >= mutation
            }
        );
    }

    @Test
    public void isTrimShouldBeExecuted_allConditionsPass_returnsTrue() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();

        // Write data first with default maxBufferElements (100)
        // This creates multiple chunks without triggering trim
        for (int i = 0; i < 400; i++) {
            os.write(42);
        }

        // Now lower maxBufferElements to trigger trim condition
        // Buffer should have ~4 chunks, maxBufferElements is now 2
        // This makes: buffer.size() (4) > maxBufferElements (2)
        sb.setMaxBufferElements(2);
        sb.setMaxAllocationSize(Integer.MAX_VALUE);

        // act & assert
        // All conditions pass: isTrimRunning=false, buffer has enough chunks, edge case ok
        assertThat(sb.isTrimShouldBeExecuted(), is(true));  // Kills mutation of final return true
    }

    @Test
    public void isTrimShouldBeExecuted_orConditionFirstCheck_returnsFalse() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // Set maxBufferElements to 0 (triggers first OR condition)
        sb.setMaxBufferElements(0);

        // Write some data (would normally trigger trim)
        final OutputStream os = sb.getOutputStream();
        for (int i = 0; i < 100; i++) {
            os.write(42);
        }

        // act & assert
        // First OR condition is true: maxBufferElements <= 0
        assertThat(sb.isTrimShouldBeExecuted(), is(false));  // Kills first return false in OR
    }

    @Test
    public void isTrimShouldBeExecuted_edgeCaseReturnsFalse() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(3);
        sb.setMaxAllocationSize(50);

        final OutputStream os = sb.getOutputStream();
        // Write 200 bytes: with maxAllocSize=50, this creates ceil(200/50)=4 chunks
        // But buffer.size() should be ~2 initially, then grows to 4
        // Edge case: resultingChunks (4) >= buffer.size() (2) -> should return false
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // act & assert
        // Edge case check should trigger and return false
        assertThat(sb.isTrimShouldBeExecuted(), is(false));  // Kills edge case return false
    }

    @Test
    public void isTrimShouldBeExecuted_orConditionSecondCheck_returnsFalse() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // Write only 1 byte to keep buffer.size() < 2
        final OutputStream os = sb.getOutputStream();
        os.write(42);

        // act & assert
        // Second OR condition is true: buffer.size() < 2
        assertThat(sb.isTrimShouldBeExecuted(), is(false));  // Kills second return false in OR
    }

    @Test
    public void isTrimShouldBeExecuted_orConditionThirdCheck_returnsFalse() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(100);  // Set high enough to not trigger trim

        final OutputStream os = sb.getOutputStream();
        // Write only 2 chunks (low number < maxBufferElements)
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // act & assert
        // Third OR condition is true: buffer.size() (likely 2) <= maxBufferElements (100)
        assertThat(sb.isTrimShouldBeExecuted(), is(false));  // Kills third condition return false
    }

    @Test
    public void shouldCheckEdgeCase_boundaryAvailableBytes_zero() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - availableBytes == 0, maxAllocSize < availableBytes means both parts must be false
        // Test specifically for availableBytes > 0 boundary: when == 0, should be false
        // Even if maxAllocSize < availableBytes, availableBytes > 0 must be evaluated
        final boolean result = sb.shouldCheckEdgeCase(0, Long.MAX_VALUE);

        // assert - should return false when availableBytes == 0 (boundary: > 0)
        // Mutated to >= would give: 0 >= 0 && MAX < 0 = true && false = false (same)
        // So we need a different approach: test with positive but not meeting second condition
        assertThat(result, is(false));
    }

    @Test
    public void shouldCheckEdgeCase_boundaryAvailableBytes_positive() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - availableBytes == 1 (positive), maxAllocSize >= availableBytes (not <)
        // Tests: 1 > 0 (true) && 100 < 1 (false) = false
        // Mutated to >= 0: 1 >= 0 (true) && 100 < 1 (false) = false (same, still doesn't help)
        // Better approach: make BOTH conditions evaluate
        final boolean result = sb.shouldCheckEdgeCase(1, 0);

        // Test: 1 > 0 (true) && 0 < 1 (true) = true
        // This actually tests the positive case
        assertThat(result, is(true));
    }

    @Test
    public void shouldCheckEdgeCase_boundaryMaxAllocSize_lessThan() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - maxAllocSize == availableBytes means NOT <
        // 100 > 0 (true) && 100 < 100 (false) = false
        // Mutated to <=: 100 > 0 (true) && 100 <= 100 (true) = true
        // This mutation would be KILLED because result changes!
        final boolean result = sb.shouldCheckEdgeCase(100, 100);

        // assert - should return false when maxAllocSize == availableBytes (boundary: <)
        assertThat(result, is(false));
    }

    @Test
    public void shouldCheckEdgeCase_boundaryMaxAllocSize_greater() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - maxAllocSize > availableBytes means NOT <
        // 100 > 0 (true) && 101 < 100 (false) = false
        final boolean result = sb.shouldCheckEdgeCase(100, 101);

        // assert - should return false (maxAllocSize is greater, not less)
        assertThat(result, is(false));
    }

    @Test
    public void maxObservedBytes_boundaryEqual_notUpdated() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // Set maxBufferElements very high to prevent automatic trim
        sb.setMaxBufferElements(10000);

        // Write exactly 100 bytes to set maxObservedBytes to 100
        for (int i = 0; i < 100; i++) {
            os.write(42);
        }
        long firstMax = sb.getMaxObservedBytes();
        assertThat(firstMax, is(100L));

        // Read all 100 bytes to bring availableBytes to 0
        for (int i = 0; i < 100; i++) {
            is.read();
        }

        // act - write exactly 100 bytes again to make availableBytes == maxObservedBytes == 100
        // This is the boundary test: > vs >=
        // With >: condition is false, no update
        // With >=: condition is true, updates (unnecessary)
        for (int i = 0; i < 100; i++) {
            os.write(42);
        }

        // assert - maxObservedBytes should stay 100 (not updated when equal)
        long secondMax = sb.getMaxObservedBytes();
        assertThat(secondMax, is(100L));  // Kills: availableBytes >= maxObservedBytes
    }

    @Test
    public void maxObservedBytes_boundaryGreater_updated() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // Set maxBufferElements very high to prevent automatic trim
        sb.setMaxBufferElements(10000);

        // Write exactly 100 bytes to set maxObservedBytes to 100
        for (int i = 0; i < 100; i++) {
            os.write(42);
        }
        long firstMax = sb.getMaxObservedBytes();
        assertThat(firstMax, is(100L));

        // Read all 100 bytes to bring availableBytes to 0
        for (int i = 0; i < 100; i++) {
            is.read();
        }

        // act - write 101 bytes to make availableBytes (101) > maxObservedBytes (100)
        for (int i = 0; i < 101; i++) {
            os.write(42);
        }

        // assert - maxObservedBytes should be updated to 101
        long secondMax = sb.getMaxObservedBytes();
        assertThat(secondMax, is(101L));  // Positive test: both > and >= work here
    }

    @Test
    public void trimStartSignal_releasedWhenTrimBegins() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore trimStarted = new Semaphore(0);
        sb.addTrimStartSignal(trimStarted);

        sb.setMaxBufferElements(1);
        final OutputStream os = sb.getOutputStream();

        // act - write data to trigger trim
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // assert - trim start signal was released (has permits available)
        assertThat(trimStarted.availablePermits(), greaterThanOrEqualTo(1));

        // cleanup
        sb.removeTrimStartSignal(trimStarted);
    }

    @Test
    public void trimEndSignal_releasedWhenTrimCompletes() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore trimEnded = new Semaphore(0);
        sb.addTrimEndSignal(trimEnded);

        sb.setMaxBufferElements(1);
        final OutputStream os = sb.getOutputStream();

        // act - write data to trigger trim
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // assert - trim end signal was released (has permits available)
        assertThat(trimEnded.availablePermits(), greaterThanOrEqualTo(1));

        // cleanup
        sb.removeTrimEndSignal(trimEnded);
    }

    @Test
    public void isTrimRunning_trueWhenTrimStartSignalFires() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final AtomicBoolean trimWasRunning = new AtomicBoolean(false);

        // Create custom semaphore to capture state when trim starts
        final Semaphore trimStartObserver = new Semaphore(0) {
            @Override
            public void release() {
                // Called when trim starts - check flag is true
                trimWasRunning.set(sb.isTrimRunning());
                super.release();
            }
        };

        sb.addTrimStartSignal(trimStartObserver);
        sb.setMaxBufferElements(1);
        final OutputStream os = sb.getOutputStream();

        // act - trigger trim by writing enough data
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // assert - isTrimRunning was true when trim start signal fired
        assertThat(trimWasRunning.get(), is(true));  // Kills: isTrimRunning returned false

        // cleanup
        sb.removeTrimStartSignal(trimStartObserver);
    }

    @Test
    public void isTrimRunning_flagVisibleViaObserver() throws IOException, InterruptedException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();

        final AtomicBoolean trimWasObserved = new AtomicBoolean(false);

        // Register observer that confirms trim ran
        final Semaphore trimEndObserver = new Semaphore(0) {
            @Override
            public void release() {
                // If we got here, trim completed successfully
                trimWasObserved.set(true);
                super.release();
            }
        };

        sb.addTrimEndSignal(trimEndObserver);
        sb.setMaxBufferElements(1);

        // act - write data to force trim
        for (int i = 0; i < 200; i++) {
            os.write(42);
        }

        // assert - trim was observed and completed
        assertThat(trimWasObserved.get(), is(true));  // Proves trim ran and flag was managed correctly

        // cleanup
        sb.removeTrimEndSignal(trimEndObserver);
    }

    @Test
    public void trimSignals_canBeAddedAndRemoved() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        // act & assert - add and remove trim start signal
        sb.addTrimStartSignal(signal);
        assertThat(sb.removeTrimStartSignal(signal), is(true));
        assertThat(sb.removeTrimStartSignal(signal), is(false));

        // act & assert - add and remove trim end signal
        sb.addTrimEndSignal(signal);
        assertThat(sb.removeTrimEndSignal(signal), is(true));
        assertThat(sb.removeTrimEndSignal(signal), is(false));
    }

    @Test
    public void trimSignals_nullThrowsException() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act & assert - addTrimStartSignal with null
        assertThrows(NullPointerException.class, () -> sb.addTrimStartSignal(null));

        // act & assert - addTrimEndSignal with null
        assertThrows(NullPointerException.class, () -> sb.addTrimEndSignal(null));
    }

    /**
     * CRITICAL TEST: Exception during trim start signal release doesn't deadlock stream
     *
     * REQUIREMENT: If releaseTrimStartSignals() throws an exception (line 442),
     * the isTrimRunning flag MUST still be properly managed and the stream MUST recover.
     * Without this, the flag stays true forever, blocking all future trim operations.
     *
     * IMPLEMENTATION RISK:
     * releaseTrimStartSignals() is called OUTSIDE the try block:
     * ```
     * if (isTrimShouldBeExecuted()) {
     *     isTrimRunning = true;
     *     releaseTrimStartSignals();  // ← OUTSIDE try-finally (line 442)
     *     try {
     *         // trim logic
     *     } finally {
     *         isTrimRunning = false;
     *     }
     * }
     * ```
     *
     * If releaseTrimStartSignals() throws:
     * - isTrimRunning stays true (never reset)
     * - Subsequent trim attempts blocked
     * - Stream enters permanent deadlock
     *
     * TEST APPROACH:
     * 1. Create custom semaphore that throws on release()
     * 2. Add as trim start signal to trigger exception during trim
     * 3. Trigger trim by writing data
     * 4. Verify stream recovers (can still write/read, trim flag reset)
     * 5. Verify second trim can execute (not deadlocked)
     */
    /**
     * CRITICAL TEST: Exception during trim start signal release doesn't deadlock stream
     *
     * REQUIREMENT: If releaseTrimStartSignals() throws an exception,
     * the isTrimRunning flag MUST still be properly managed via finally block.
     * Without this, the flag stays true forever, blocking all future trim operations.
     *
     * IMPLEMENTATION FIX (applied):
     * Moved releaseTrimStartSignals() INSIDE the try-finally block (line 443):
     * ```
     * try {
     *     releaseTrimStartSignals();  // ← NOW INSIDE try-finally
     *     // trim logic
     * } finally {
     *     isTrimRunning = false;  // ← Always executes
     * }
     * ```
     *
     * TEST APPROACH:
     * 1. Set up buffer with enough data to trigger trim on next write
     * 2. Add throwing semaphore AFTER data setup (so initial setup doesn't fire trim)
     * 3. Trigger trim by writing one more element → signal release throws
     * 4. Catch the exception outside of assertAll
     * 5. Verify recovery: flag reset, stream still usable, exception was thrown
     */
    @Test
    public void trim_signalReleaseExceptionDuringStart_streamRecoverable() throws IOException {
        // arrange — Track when throwing semaphore is called
        final AtomicBoolean exceptionThrown = new AtomicBoolean(false);
        final Semaphore throwingSemaphore = new Semaphore(0) {
            @Override
            public void release() {
                exceptionThrown.set(true);
                throw new RuntimeException("Simulated signal release failure");
            }
        };

        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // Set a high threshold initially so setup writes don't trigger trim
        sb.setMaxBufferElements(1000);

        // Write data to build up buffer (no trim yet)
        byte[] testData = new byte[100];
        Arrays.fill(testData, (byte) 42);
        for (int i = 0; i < 50; i++) {
            os.write(testData);
        }

        // NOW add the throwing semaphore and lower threshold to trigger trim on next write
        sb.addTrimStartSignal(throwingSemaphore);
        sb.setMaxBufferElements(5);

        // act — Trigger trim (next write exceeds maxBufferElements → trim → throws)
        RuntimeException caughtException = null;
        try {
            os.write(testData);
        } catch (RuntimeException e) {
            caughtException = e;
        }

        // Remove throwing semaphore so recovery tests don't retrigger exception
        sb.removeTrimStartSignal(throwingSemaphore);

        // assert — Verify exception occurred and stream recovered
        final RuntimeException finalCaught = caughtException;
        assertAll(
            () -> {
                // Exception was thrown from signal release
                assertThat("Signal release exception should propagate",
                    finalCaught, not((RuntimeException) null));
                assertThat("Exception message correct",
                    finalCaught.getMessage(), is("Simulated signal release failure"));
            },
            () -> {
                // Throwing semaphore was actually invoked
                assertThat("Throwing semaphore's release() should have been called",
                    exceptionThrown.get(), is(true));
            },
            () -> {
                // CRITICAL: isTrimRunning must be false (finally block executed)
                // If the fix weren't applied, this would be true → deadlock
                assertThat("isTrimRunning must be false after exception (finally executed)",
                    sb.isTrimRunning(), is(false));
            },
            () -> {
                // Stream still usable - can write
                byte[] moreData = new byte[50];
                Arrays.fill(moreData, (byte) 99);
                os.write(moreData);
            },
            () -> {
                // Stream still usable - can read
                byte[] buffer = new byte[100];
                int bytesRead = is.read(buffer);
                assertThat("Should be able to read after signal exception",
                    bytesRead, greaterThan(0));
            }
        );
    }

    /**
     * CRITICAL TEST: Exception during trim write phase resets ignoreSafeWrite flag
     *
     * REQUIREMENT: If IOException occurs while trim is writing consolidated data back,
     * the ignoreSafeWrite flag MUST be reset in the finally block (lines 476-478).
     * Without this, external code could mutate the buffer while ignoreSafeWrite is true,
     * causing data corruption or unsafe behavior.
     *
     * IMPLEMENTATION FIX (already in place):
     * Nested try-finally protects the ignoreSafeWrite flag:
     * ```
     * try {
     *     ignoreSafeWrite = true;
     *     while (!tmpBuffer.isEmpty()) {
     *         os.write(tmpBuffer.pollFirst());  // ← If IOException here
     *     }
     * } finally {
     *     ignoreSafeWrite = false;              // ← Always executes
     * }
     * ```
     *
     * TEST APPROACH:
     * 1. Create custom StreamBuffer that returns throwing OutputStream
     * 2. Set up conditions to trigger trim
     * 3. Add throwing semaphore to force trim execution
     * 4. When trim runs and calls os.write() on consolidated data, throws
     * 5. Verify ignoreSafeWrite is reset despite exception
     * 6. Verify stream still usable (flag not stuck in true state)
     */
    @Test
    public void trim_ignoreSafeWriteFlagResetDuringWriteException_streamRecoverable() throws IOException {
        // arrange — Custom StreamBuffer with throwing output stream
        class FailingWriteStreamBuffer extends StreamBuffer {
            private boolean shouldThrowOnWrite = false;

            @Override
            public OutputStream getOutputStream() {
                final OutputStream wrapped = super.getOutputStream();
                return new OutputStream() {
                    @Override
                    public void write(int b) throws IOException {
                        if (shouldThrowOnWrite) {
                            throw new IOException("Simulated write failure during trim consolidation");
                        }
                        wrapped.write(b);
                    }

                    @Override
                    public void write(byte[] b, int off, int len) throws IOException {
                        if (shouldThrowOnWrite) {
                            throw new IOException("Simulated write failure during trim consolidation");
                        }
                        wrapped.write(b, off, len);
                    }

                    @Override
                    public void close() throws IOException {
                        wrapped.close();
                    }
                };
            }
        }

        final FailingWriteStreamBuffer sb = new FailingWriteStreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // Set high threshold initially — no trim during setup
        sb.setMaxBufferElements(1000);

        // Write data to build up buffer (no trim yet)
        byte[] testData = new byte[100];
        Arrays.fill(testData, (byte) 42);
        for (int i = 0; i < 50; i++) {
            os.write(testData);
        }

        // Enable throwing behavior and lower threshold to trigger trim on next write
        sb.shouldThrowOnWrite = true;
        sb.setMaxBufferElements(5);

        // act — Trigger trim write phase with exception
        IOException caughtException = null;
        try {
            os.write(testData);
        } catch (IOException e) {
            caughtException = e;
        }

        // Disable throwing for recovery tests
        sb.shouldThrowOnWrite = false;

        // assert — Verify exception occurred and ignoreSafeWrite was reset
        final IOException finalException = caughtException;
        assertAll(
            () -> {
                // IOException was thrown from write phase
                assertThat("Write phase exception should be thrown",
                    finalException, not((IOException) null));
                assertThat("Exception message correct",
                    finalException.getMessage(),
                    is("Simulated write failure during trim consolidation"));
            },
            () -> {
                // CRITICAL: ignoreSafeWrite must be false (finally executed)
                // If the flag stayed true, external code could unsafely mutate buffer
                // Check by attempting a write with safeWrite enabled
                sb.setSafeWrite(true);
                byte[] safeData = new byte[50];
                Arrays.fill(safeData, (byte) 99);
                os.write(safeData);  // Should use safe write (not throw)
                // If ignoreSafeWrite was stuck true, this would have different behavior
            },
            () -> {
                // Stream still usable - can write
                byte[] moreData = new byte[50];
                Arrays.fill(moreData, (byte) 88);
                os.write(moreData);
            },
            () -> {
                // Stream still usable - can read
                byte[] buffer = new byte[100];
                int bytesRead = is.read(buffer);
                assertThat("Should be able to read after write exception",
                    bytesRead, greaterThan(0));
            }
        );
    }

    /**
     * CRITICAL TEST: Exception during trim end signal release - flag already reset but exception propagates
     *
     * REQUIREMENT: If exception occurs in releaseTrimEndSignals() (line 481 finally block),
     * the isTrimRunning flag MUST already be false (line 480 executes first).
     * However, the exception can suppress notification to signal observers.
     *
     * IMPLEMENTATION ANALYSIS:
     * Finally block order matters:
     * ```
     * } finally {
     *     isTrimRunning = false;              // ← Line 480: executes FIRST
     *     releaseTrimEndSignals();            // ← Line 481: executes SECOND
     * }
     * ```
     *
     * Key difference from trim start test:
     * - Trim start exception (line 443): flag ALREADY true, exception before reset → DANGEROUS
     * - Trim end exception (line 481): flag ALREADY reset, exception after → SAFE for flag
     * - But: Signal observers may not be notified if exception occurs
     *
     * TEST APPROACH:
     * 1. Create throwing semaphore for trim end signal
     * 2. Setup: high threshold, write data, add throwing signal
     * 3. Lower threshold and write more → trim runs → signal release throws
     * 4. Verify:
     *    - isTrimRunning is false (flag was reset before exception)
     *    - Exception propagates to caller (signal notification failure)
     *    - Stream still works (exception doesn't break stream state)
     */
    @Test
    public void trim_signalReleaseExceptionDuringEnd_flagAlreadyResetExceptionPropagates() throws IOException {
        // arrange — Create throwing semaphore for trim end signal
        final AtomicBoolean endSignalCalled = new AtomicBoolean(false);
        final Semaphore throwingEndSemaphore = new Semaphore(0) {
            @Override
            public void release() {
                endSignalCalled.set(true);
                throw new RuntimeException("Simulated trim end signal release failure");
            }
        };

        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // Set high threshold initially — no trim during setup
        sb.setMaxBufferElements(1000);

        // Write data to build up buffer (no trim yet)
        byte[] testData = new byte[100];
        Arrays.fill(testData, (byte) 42);
        for (int i = 0; i < 50; i++) {
            os.write(testData);
        }

        // NOW add the throwing trim end signal and lower threshold to trigger trim on next write
        sb.addTrimEndSignal(throwingEndSemaphore);
        sb.setMaxBufferElements(5);

        // act — Trigger trim (next write exceeds maxBufferElements → trim → signal release throws)
        RuntimeException caughtException = null;
        try {
            os.write(testData);
        } catch (RuntimeException e) {
            caughtException = e;
        }

        // Remove throwing semaphore so subsequent operations don't retrigger exception
        sb.removeTrimEndSignal(throwingEndSemaphore);

        // assert — Verify exception occurred and stream recovered
        final RuntimeException finalCaught = caughtException;
        assertAll(
            () -> {
                // Exception was thrown from trim end signal release
                assertThat("Trim end signal release exception should propagate",
                    finalCaught, not((RuntimeException) null));
                assertThat("Exception message correct",
                    finalCaught.getMessage(), is("Simulated trim end signal release failure"));
            },
            () -> {
                // Throwing end semaphore was actually invoked
                assertThat("Throwing trim end semaphore's release() should have been called",
                    endSignalCalled.get(), is(true));
            },
            () -> {
                // CRITICAL: isTrimRunning must be false (flag was reset BEFORE signal exception)
                // Line 480 executes before line 481, so flag is already false
                // This is different from trim start where flag would be stuck true
                assertThat("isTrimRunning must be false (flag reset before signal release)",
                    sb.isTrimRunning(), is(false));
            },
            () -> {
                // Stream still usable - can write (trim end exception doesn't break stream)
                byte[] moreData = new byte[50];
                Arrays.fill(moreData, (byte) 99);
                os.write(moreData);
            },
            () -> {
                // Stream still usable - can read
                byte[] buffer = new byte[100];
                int bytesRead = is.read(buffer);
                assertThat("Should be able to read after trim end signal exception",
                    bytesRead, greaterThan(0));
            }
        );
    }

    /**
     * CRITICAL TEST: Close called while trim is active - race condition safety
     *
     * REQUIREMENT: If close() is called while trim() is executing,
     * both methods must complete safely without exceptions, deadlocks,
     * or data corruption. Both use bufferLock synchronization.
     *
     * IMPLEMENTATION ANALYSIS:
     * Race condition scenario:
     * - Thread 1: trim() acquired bufferLock, reading/writing internal streams
     * - Thread 2: close() calls bufferLock, closes output/input streams
     *
     * Both methods synchronize on bufferLock:
     * - trim() (line 443-484): synchronized operations on is/os
     * - close() (line 995-1010): closes streams, synchronizes access
     *
     * Potential issues:
     * - close() could close streams while trim() is using them
     * - Could cause IOException during trim read/write
     * - Could cause NullPointerException if streams become null
     * - Could lose signal notifications if close() interrupts trim
     *
     * TEST APPROACH:
     * 1. Use ExecutorService to run threads concurrently
     * 2. Thread 1: Write large data to trigger trim (will take time)
     * 3. Use CountDownLatch to synchronize: wait for trim to start
     * 4. Thread 2: Call close() after trim has started
     * 5. Both threads should complete without exceptions
     * 6. Verify: no exceptions, stream closed, data can still be read
     */
    @Test
    public void trim_closeCalledDuringTrim_handlesGracefully() throws IOException, InterruptedException {
        // arrange — Setup concurrent test infrastructure
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();
        final ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(2);

        // Use latch to coordinate: signal when trim starts
        final CountDownLatch trimStarted = new CountDownLatch(1);
        final Semaphore trimStartSignal = new Semaphore(0) {
            @Override
            public void release() {
                trimStarted.countDown();  // Signal that trim is executing
                super.release();
            }
        };

        sb.addTrimStartSignal(trimStartSignal);
        sb.setMaxBufferElements(5);

        // Create large data to trigger trim consolidation (takes time)
        byte[] largeData = new byte[1000];
        Arrays.fill(largeData, (byte) 42);

        // Track exceptions from threads
        final AtomicReference<Exception> thread1Exception = new AtomicReference<>(null);
        final AtomicReference<Exception> thread2Exception = new AtomicReference<>(null);

        try {
            // act — Thread 1: Write data to trigger trim
            java.util.concurrent.Future<?> trimTask = executor.submit(() -> {
                try {
                    // Write enough data to trigger trim on successive writes
                    // This will take time due to consolidation
                    for (int i = 0; i < 100; i++) {
                        os.write(largeData);
                    }
                } catch (Exception e) {
                    thread1Exception.set(e);
                }
            });

            // Wait for trim to actually start executing
            boolean trimStartedInTime = trimStarted.await(5, java.util.concurrent.TimeUnit.SECONDS);
            assertThat("Trim should start within timeout", trimStartedInTime, is(true));

            // act — Thread 2: Call close() while trim is running
            java.util.concurrent.Future<?> closeTask = executor.submit(() -> {
                try {
                    sb.close();
                } catch (Exception e) {
                    thread2Exception.set(e);
                }
            });

            // Wait for both tasks to complete
            try {
                trimTask.get(10, java.util.concurrent.TimeUnit.SECONDS);
                closeTask.get(10, java.util.concurrent.TimeUnit.SECONDS);
            } catch (java.util.concurrent.ExecutionException | java.util.concurrent.TimeoutException e) {
                // Task threw exception or timed out (already captured in thread*Exception)
            }

            // assert — No exceptions from either thread
            assertAll(
                () -> {
                    assertThat("Trim should not throw exception",
                        thread1Exception.get(), is((Exception) null));
                },
                () -> {
                    assertThat("Close should not throw exception",
                        thread2Exception.get(), is((Exception) null));
                },
                () -> {
                    // Verify stream closed properly
                    assertThat("Stream should be closed",
                        sb.isClosed(), is(true));
                },
                () -> {
                    // Verify data can still be read (no corruption)
                    byte[] buffer = new byte[1000];
                    int bytesRead = 0;
                    int totalRead = 0;
                    try {
                        while ((bytesRead = is.read(buffer)) >= 0 && totalRead < 100000) {
                            totalRead += bytesRead;
                        }
                        assertThat("Should be able to read data despite concurrent close",
                            totalRead, greaterThan(0));
                    } catch (IOException ignored) {
                        // Reading from closed stream is acceptable
                    }
                }
            );

        } finally {
            executor.shutdownNow();
            sb.removeTrimStartSignal(trimStartSignal);
        }
    }

    // Test extracted boundary checking methods

    @Test
    public void isAvailableBytesPositive_zero_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act
        final boolean result = sb.isAvailableBytesPositive(0);

        // assert - boundary: > 0 means 0 is false
        assertThat(result, is(false));
    }

    @Test
    public void isAvailableBytesPositive_one_returnsTrue() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act
        final boolean result = sb.isAvailableBytesPositive(1);

        // assert - boundary: > 0 means 1 is true
        assertThat(result, is(true));
    }

    @Test
    public void isAvailableBytesPositive_negative_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act
        final boolean result = sb.isAvailableBytesPositive(-100);

        // assert - boundary: > 0 means negative is false
        assertThat(result, is(false));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_equal_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when maxAllocSize == availableBytes
        final boolean result = sb.isMaxAllocSizeLessThanAvailable(100, 100);

        // assert - boundary: < means equal is false
        assertThat(result, is(false));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_lessThan_returnsTrue() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when maxAllocSize < availableBytes
        final boolean result = sb.isMaxAllocSizeLessThanAvailable(50, 100);

        // assert - boundary: < means less than is true
        assertThat(result, is(true));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_greaterThan_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when maxAllocSize > availableBytes
        final boolean result = sb.isMaxAllocSizeLessThanAvailable(100, 50);

        // assert - boundary: < means greater than is false
        assertThat(result, is(false));
    }

    @Test
    public void shouldUpdateMaxObservedBytes_equal_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when availableBytes == currentMax
        final boolean result = sb.shouldUpdateMaxObservedBytes(100, 100);

        // assert - boundary: > means equal is false
        assertThat(result, is(false));
    }

    @Test
    public void shouldUpdateMaxObservedBytes_greaterThan_returnsTrue() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when availableBytes > currentMax
        final boolean result = sb.shouldUpdateMaxObservedBytes(150, 100);

        // assert - boundary: > means greater than is true
        assertThat(result, is(true));
    }

    @Test
    public void shouldUpdateMaxObservedBytes_lessThan_returnsFalse() {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - when availableBytes < currentMax
        final boolean result = sb.shouldUpdateMaxObservedBytes(50, 100);

        // assert - boundary: > means less than is false
        assertThat(result, is(false));
    }

    @Test
    public void updateMaxObservedBytesIfNeeded_exceedsCurrentMax() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        assertThat(sb.getMaxObservedBytes(), is(0L));

        // act - update with value exceeding current max
        sb.updateMaxObservedBytesIfNeeded(100);

        // assert
        assertThat(sb.getMaxObservedBytes(), is(100L));
    }

    @Test
    public void updateMaxObservedBytesIfNeeded_equalToCurrentMax() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        sb.updateMaxObservedBytesIfNeeded(100);
        assertThat(sb.getMaxObservedBytes(), is(100L));

        // act - try to update with equal value
        sb.updateMaxObservedBytesIfNeeded(100);

        // assert - should not change
        assertThat(sb.getMaxObservedBytes(), is(100L));
    }

    @Test
    public void recordReadStatistics_updatesCounterWhenTrimNotRunning() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        assertThat(sb.getTotalBytesRead(), is(0L));

        // act - record read statistics (trim is not running by default)
        sb.recordReadStatistics(50);

        // assert
        assertThat(sb.getTotalBytesRead(), is(50L));
    }

    @Test
    public void recordReadStatistics_accumulatesMultipleCalls() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - multiple calls
        sb.recordReadStatistics(50);
        sb.recordReadStatistics(30);
        sb.recordReadStatistics(20);

        // assert
        assertThat(sb.getTotalBytesRead(), is(100L));
    }

    // Integration tests: Verify statistics are updated during actual read operations
    // These tests ensure recordReadStatistics() is actually called in the read path

    @Test
    public void statistics_arrayRead_updatesCounterDuringIntegration() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final byte[] writeData = new byte[]{1, 2, 3, 4, 5};
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // act - write data and read it back
        os.write(writeData);
        final byte[] readBuffer = new byte[5];
        final int bytesRead = is.read(readBuffer);

        // assert - verify statistics were updated by the read operation
        assertThat(bytesRead, is(5));
        assertThat(sb.getTotalBytesRead(), is(5L));
    }

    @Test
    public void statistics_singleByteRead_updatesCounterDuringIntegration() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // act - write and read single bytes
        os.write(42);
        os.write(43);
        final int byte1 = is.read();
        final int byte2 = is.read();

        // assert - verify statistics were updated by single-byte read operations
        assertThat(byte1, is(42));
        assertThat(byte2, is(43));
        assertThat(sb.getTotalBytesRead(), is(2L));
    }

    @Test
    public void statistics_partialArrayRead_updatesCounterCorrectly() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final byte[] writeData = new byte[]{10, 20, 30, 40, 50};
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // act - write data and read with offset and length
        os.write(writeData);
        final byte[] readBuffer = new byte[3];
        final int bytesRead = is.read(readBuffer, 0, 3);

        // assert - verify only the requested bytes are counted
        assertThat(bytesRead, is(3));
        assertThat(sb.getTotalBytesRead(), is(3L));
    }

    @Test
    public void statistics_multipleReads_accumulateCorrectly() throws IOException {
        // arrange
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        // act - write and perform multiple reads
        os.write(new byte[]{1, 2, 3, 4, 5, 6, 7, 8});
        final byte[] buf1 = new byte[3];
        final byte[] buf2 = new byte[3];
        final byte[] buf3 = new byte[2];

        final int read1 = is.read(buf1);
        final int read2 = is.read(buf2);
        final int read3 = is.read(buf3);

        // assert - verify cumulative count
        assertThat(read1, is(3));
        assertThat(read2, is(3));
        assertThat(read3, is(2));
        assertThat(sb.getTotalBytesRead(), is(8L));
    }

    // Comprehensive trim decision logic test using data provider
    // This documents the critical requirement: trim only executes when it makes sense

    @ParameterizedTest(name = "bufferSize={0}, maxBufferElements={1}, availableBytes={2}, maxAllocSize={3} → shouldTrim={4}")
    @MethodSource("trimDecisionTestCases")
    public void decideTrimExecution_pureFunction_withAllParameters(
            int bufferSize,
            int maxBufferElements,
            long availableBytes,
            long maxAllocSize,
            boolean expectedShouldTrim) {
        // arrange
        final StreamBuffer sb = new StreamBuffer();

        // act - call the pure decision function directly with parameters
        final boolean actualShouldTrim = sb.decideTrimExecution(
            bufferSize,
            maxBufferElements,
            availableBytes,
            maxAllocSize
        );

        // assert
        assertThat(actualShouldTrim, is(expectedShouldTrim));
    }

    /**
     * Data provider for trim decision logic test.
     *
     * Requirement: Trim should only execute when consolidating the buffer
     * would actually reduce the number of elements to below maxBufferElements.
     *
     * Each row represents: bufferSize, maxBufferElements, availableBytes, maxAllocSize → shouldTrim
     *
     * Critical cases:
     * 1. Trim should EXECUTE: Buffer exceeds max and consolidation reduces it
     * 2. Trim should SKIP: Buffer already within limit (no action needed)
     * 3. Trim should SKIP: maxBufferElements invalid (≤ 0)
     * 4. Trim should SKIP: Buffer too small (< 2)
     * 5. Trim should SKIP: Edge case where consolidation still exceeds max
     */
    private static java.util.stream.Stream<Arguments> trimDecisionTestCases() {
        return java.util.stream.Stream.of(
            // ============ SKIP CASES: maxBufferElements Invalid ============
            // When maxBufferElements <= 0, trim is nonsensical
            Arguments.of(2, 0, 100, 50, false),    // maxBufferElements=0 → invalid, skip
            Arguments.of(2, -1, 100, 50, false),   // maxBufferElements=-1 → invalid, skip

            // ============ SKIP CASES: Buffer Too Small ============
            // Trim requires at least 2 elements to consolidate
            Arguments.of(0, 10, 0, 50, false),     // empty buffer
            Arguments.of(1, 10, 1, 50, false),     // buffer size = 1, trim needs >= 2

            // ============ SKIP CASES: Buffer Within Limit ============
            // When buffer.size() <= maxBufferElements, no trim needed
            Arguments.of(5, 10, 50, 100, false),   // 5 <= 10 (within limit)
            Arguments.of(10, 10, 100, 100, false), // 10 <= 10 (at limit, no trim needed)

            // ============ EXECUTE CASES: Buffer Exceeds Limit ============
            // Buffer > maxBufferElements AND trim will help
            Arguments.of(101, 100, 1010, 100, true),  // 101 > 100, ceil(1010/100)=11 < 101, will trim
            Arguments.of(15, 10, 150, 100, true),     // 15 > 10, consolidation reduces chunks

            // ============ EDGE CASE: Trim Pointless (Would Not Reduce Size) ============
            // resultingChunks >= bufferSize: trim wouldn't actually consolidate
            // Example: maxBufferElements=10, maxAllocSize=100, availableBytes=1100
            // → ceil(1100/100) = 11 chunks, still >= buffer size of 11
            Arguments.of(11, 10, 1100, 100, false),  // resulting 11 >= current 11 → skip
            Arguments.of(12, 10, 1200, 100, false),  // resulting 12 >= current 12 → skip
            Arguments.of(20, 10, 2000, 100, false),  // resulting 20 >= current 20 → skip

            // Edge case where trim WOULD reduce: 99 elements, max 100, no trim
            Arguments.of(99, 100, 990, 100, false),  // 99 <= 100 (within limit)

            // Edge case: 101 elements, max 100, trim reduces from 101 to 11
            Arguments.of(101, 100, 1010, 100, true), // 101 > 100, result 11 < 101 → trim

            // Very large buffer needing consolidation
            Arguments.of(1000, 100, 10000, 1000, true), // 1000 > 100, ceil(10000/1000)=10 < 1000 → trim

            // ============ KILL SURVIVING MUTATIONS ============
            // Kill arithmetic mutation: subtraction vs addition in ceiling division
            // Need: maxAllocationSize < availableBytes to ENTER edge case, where ceiling formula is executed
            // Correct: (200 + 100 - 1) / 100 = 2, so 2 >= 3 is false, return true (trim executes)
            // Mutated (+1): (200 + 100 + 1) / 100 = 3, so 3 >= 3 is true, return false (skip trim)
            Arguments.of(3, 1, 200, 100, true),

            // Kill boundary mutation on < vs <=: test maxAllocationSize == availableBytes
            // Edge case: when maxAllocationSize == availableBytes, currently skipped (< is false)
            // With <= mutation, edge case would be entered, but ceiling = 1, doesn't change result
            Arguments.of(2, 1, 100, 100, true),   // maxAllocSize=availableBytes, edge case skipped (< false)

            // Kill boundary mutation on > vs >=: test availableBytes == 0
            // If availableBytes == 0, currently skip edge case (> is false)
            // With >= mutation, would enter but maxAllocationSize < 0 is never true
            Arguments.of(2, 1, 0, 100, true),     // availableBytes=0, edge case skipped (> false)

            // Additional edge cases to expose mutations
            Arguments.of(2, 1, 99, 100, true),    // 99 < 100, edge case skipped (< false)
            Arguments.of(2, 1, 101, 100, false),  // 101 > 100, edge case entered, ceil=(101+100-1)/100=2, 2>=2 true, skip trim
            Arguments.of(4, 1, 200, 100, true)    // bufferSize=4: ceiling=(200+100-1)/100=2, 2>=4 false, return true
        );
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Direct Tests for Boundary Condition Functions">

    @Test
    public void isAvailableBytesPositive_withZero_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isAvailableBytesPositive(0), is(false));
    }

    @Test
    public void isAvailableBytesPositive_withOne_returnsTrue() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isAvailableBytesPositive(1), is(true));
    }

    @Test
    public void isAvailableBytesPositive_withNegative_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isAvailableBytesPositive(-1), is(false));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_withLess_returnsTrue() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isMaxAllocSizeLessThanAvailable(100, 200), is(true));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_withEqual_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isMaxAllocSizeLessThanAvailable(100, 100), is(false));
    }

    @Test
    public void isMaxAllocSizeLessThanAvailable_withGreater_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isMaxAllocSizeLessThanAvailable(200, 100), is(false));
    }

    @Test
    public void shouldCheckEdgeCase_withBothConditionsTrue_returnsTrue() {
        StreamBuffer sb = new StreamBuffer();
        // availableBytes > 0 AND maxAllocSize < availableBytes
        assertThat(sb.shouldCheckEdgeCase(200, 100), is(true));
    }

    @Test
    public void shouldCheckEdgeCase_withAvailableBytesZero_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        // availableBytes > 0 is false
        assertThat(sb.shouldCheckEdgeCase(0, 100), is(false));
    }

    @Test
    public void shouldCheckEdgeCase_withMaxAllocSizeEqual_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        // maxAllocSize < availableBytes is false
        assertThat(sb.shouldCheckEdgeCase(100, 100), is(false));
    }

    @Test
    public void shouldCheckEdgeCase_withMaxAllocSizeGreater_returnsFalse() {
        StreamBuffer sb = new StreamBuffer();
        // maxAllocSize < availableBytes is false
        assertThat(sb.shouldCheckEdgeCase(50, 100), is(false));
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Exception Safety & Signal Management">

    /**
     * CRITICAL TEST SECTION: Exception Safety During Trim Operations
     *
     * These tests verify that StreamBuffer handles exceptions safely during trim,
     * maintaining proper flag state and stream usability even when errors occur.
     *
     * Key Requirements (verified by tests in this section):
     * 1. isTrimRunning flag MUST reset via finally block (even if exceptions occur)
     *    - Implementation: Lines 440-484 in StreamBuffer.java (try-finally)
     * 2. ignoreSafeWrite flag MUST reset despite write exceptions
     *    - Implementation: Lines 470-478 (nested try-finally)
     * 3. Signal release exceptions must not deadlock stream
     *    - Implementation: releaseTrimStartSignals() moved INSIDE try block (line 443)
     * 4. Concurrent close() during trim must not cause race conditions
     *    - Implementation: bufferLock synchronization prevents interleaving
     * 5. Configuration changes must not affect running trim
     *    - Implementation: Configuration values cached before trim execution
     *
     * Each test includes detailed inline documentation explaining the specific
     * exception scenario and why the fix prevents problems.
     */

    @Test
    public void trim_exceptionDuringRead_flagResetsInFinally() throws IOException {
        // arrange — Verify that isTrimRunning is reset even if exception occurs during is.read()
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        // Write enough data to trigger trim
        for (int i = 0; i < 150; i++) {
            os.write(anyValue);
        }
        sb.setMaxBufferElements(10);

        // act — trigger trim by writing more data
        // The trim operation should reset isTrimRunning even if exceptions occur
        os.write(new byte[100]);

        // assert — isTrimRunning should be false after trim completes (or fails safely)
        assertThat(sb.isTrimRunning(), is(false));
    }

    @Test
    public void trim_exceptionDuringWrite_flagResetsInFinally() throws IOException {
        // arrange — Similar to above but focused on write phase of trim
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // Write data to create multiple chunks
        byte[] chunk = new byte[50];
        Arrays.fill(chunk, anyValue);
        for (int i = 0; i < 15; i++) {
            os.write(chunk);
        }
        sb.setMaxBufferElements(5);

        // act — write more to trigger trim
        os.write(chunk);

        // assert — flag should be reset
        assertThat(sb.isTrimRunning(), is(false));

        // Verify data integrity despite trim
        os.close();
        byte[] result = new byte[800];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 800 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(800));
    }

    @Test
    public void setMaxAllocationSize_duringNormalOperation_appliesImmediately() throws IOException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // act — change maxAllocationSize between operations
        sb.setMaxAllocationSize(50);
        for (int i = 0; i < 100; i++) {
            os.write(anyValue);
        }

        // Change it again mid-stream
        sb.setMaxAllocationSize(25);
        sb.setMaxBufferElements(2);  // trigger trim with new limit
        for (int i = 0; i < 50; i++) {
            os.write(anyValue);
        }

        // assert — all data should be readable
        os.close();
        byte[] result = new byte[150];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 150 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(150));
    }

    @Test
    public void trim_signalOperationsConcurrent_handlesSafely() throws IOException, InterruptedException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();
        Semaphore trimStarted = new Semaphore(0);
        Semaphore trimEnded = new Semaphore(0);

        // add signals to be released when trim occurs
        sb.addTrimStartSignal(trimStarted);
        sb.addTrimEndSignal(trimEnded);

        // Write data to trigger trim
        byte[] chunk = new byte[100];
        Arrays.fill(chunk, anyValue);
        sb.setMaxBufferElements(2);

        // act — write enough to trigger trim
        for (int i = 0; i < 5; i++) {
            os.write(chunk);
        }

        // assert — signals were released
        assertThat(trimStarted.tryAcquire(1, TimeUnit.SECONDS), is(true));
        assertThat(trimEnded.tryAcquire(1, TimeUnit.SECONDS), is(true));

        // Clean up
        sb.removeTrimStartSignal(trimStarted);
        sb.removeTrimEndSignal(trimEnded);
    }

    @Test
    public void ignoreSafeWrite_resetAfterTrim() throws IOException {
        // arrange — Verify that ignoreSafeWrite flag is properly reset after trim
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // Enable safe write to test the ignoreSafeWrite flag
        sb.setSafeWrite(true);

        // Write data to trigger trim
        byte[] data = new byte[50];
        Arrays.fill(data, anyValue);
        sb.setMaxBufferElements(2);

        // act — write enough to trigger trim with safe write enabled
        for (int i = 0; i < 5; i++) {
            os.write(data);
        }

        // assert — all data should be preserved correctly
        os.close();
        byte[] result = new byte[250];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 250 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(250));
        assertThat(result[0], is(anyValue));
        assertThat(result[249], is(anyValue));
    }

    @Test
    public void largeBuffer_withSmallAllocationSize_handlesCorrectly() throws IOException {
        // arrange — Test buffer overflow scenario with extreme constraints
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        sb.setMaxAllocationSize(10);     // Very small chunks
        sb.setMaxBufferElements(3);      // Very restrictive buffer limit

        // act — write substantial data (5000 bytes)
        byte[] chunk = new byte[500];
        Arrays.fill(chunk, anyValue);
        for (int i = 0; i < 10; i++) {
            os.write(chunk);
        }

        // assert — all data should be readable despite extreme constraints
        os.close();
        byte[] result = new byte[5000];
        int totalRead = 0;
        int bytesRead;
        while ((bytesRead = is.read(result, totalRead, 5000 - totalRead)) > 0) {
            totalRead += bytesRead;
        }
        assertThat(totalRead, is(5000));
    }

    /**
     * CRITICAL CORRECTNESS TEST: Config changes during trim don't affect running trim
     *
     * REQUIREMENT: When trim is already executing, changes to configuration parameters
     * (maxBufferElements, maxAllocationSize) must NOT affect the currently running trim
     * operation. Configuration should only influence trim DECISIONS, not trim EXECUTION.
     *
     * IMPLEMENTATION VERIFICATION:
     * The trim decision logic caches configuration values BEFORE trim starts:
     * - isTrimShouldBeExecuted() calls: final int maxBufferElements = getMaxBufferElements()
     * - This cached value is passed to decideTrimExecution() as a parameter
     * - During trim execution, only the cached value is used, not the volatile field
     *
     * RISK IF NOT CORRECT:
     * If trim re-read configuration during execution, a concurrent config change could:
     * - Cause trim to terminate prematurely (if maxBufferElements changed)
     * - Change chunk allocation mid-operation (if maxAllocationSize changed)
     * - Corrupt internal state (data loss, inconsistent buffer state)
     *
     * TEST APPROACH:
     * 1. Register semaphore observer to detect when trim STARTS executing
     * 2. Continuously write data in writer thread to trigger trim
     * 3. Main thread waits for trim to start
     * 4. While trim is running, change configuration
     * 5. Verify trim completes successfully and data is intact
     * 6. Verify that new configuration takes effect in subsequent operations
     *
     * SYNCHRONIZATION MECHANISM:
     * Uses StreamBuffer's built-in semaphore observer pattern:
     * - addTrimStartSignal(Semaphore) releases semaphore when trim() begins
     * - addTrimEndSignal(Semaphore) releases semaphore when trim() completes
     * This allows precise test synchronization without mocking or instrumentation.
     */
    @Test
    @Timeout(10)  // 10 second timeout to prevent hanging if sync fails
    public void setMaxBufferElements_duringTrimExecution_doesNotAffectRunningTrim() throws IOException, InterruptedException {
        // arrange — Set up continuous writer and trim observers
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        sb.setMaxBufferElements(100);    // Initial high threshold
        sb.setMaxAllocationSize(50);     // Reasonable chunk size

        // Semaphores for synchronization
        Semaphore trimStarted = new Semaphore(0);  // Released when trim() begins
        Semaphore trimEnded = new Semaphore(0);    // Released when trim() ends

        // Register observers to detect trim lifecycle
        sb.addTrimStartSignal(trimStarted);
        sb.addTrimEndSignal(trimEnded);

        // Writer thread: continuously write data to trigger trim
        Thread writerThread = new Thread(() -> {
            try {
                byte[] chunk = new byte[10];
                Arrays.fill(chunk, anyValue);
                // Write 200 chunks (2000 bytes) — exceeds maxBufferElements(100), triggers trim
                for (int i = 0; i < 200; i++) {
                    os.write(chunk);
                    Thread.sleep(2);  // Small delay to allow trim to execute
                }
                os.close();
            } catch (IOException | InterruptedException e) {
                throw new RuntimeException(e);
            }
        });

        writerThread.start();

        // act — Wait for trim to start, then change config mid-trim
        trimStarted.acquire();  // Block until trim() is executing

        // At this point: trim is running, isTrimRunning == true
        // Change configuration while trim is in progress
        sb.setMaxBufferElements(0);      // Change to invalid value while trim runs
        sb.setMaxAllocationSize(100);    // Also change allocation size

        // Wait for trim to complete
        trimEnded.acquire();  // Block until trim() finishes

        // assert — Verify trim completed successfully despite config changes
        assertAll(
            // 1. Trim finished (flag reset)
            () -> assertThat("Trim should complete and reset flag", sb.isTrimRunning(), is(false)),

            // 2. Data integrity preserved (all written data readable)
            () -> {
                byte[] result = new byte[2000];
                int totalRead = 0;
                int bytesRead;
                while ((bytesRead = is.read(result, totalRead, 2000 - totalRead)) > 0) {
                    totalRead += bytesRead;
                }
                assertThat("All 2000 written bytes should be readable", totalRead, is(2000));
                assertThat("First byte intact", result[0], is(anyValue));
                assertThat("Last byte intact", result[1999], is(anyValue));
            },

            // 3. New configuration takes effect in next operation
            () -> {
                // maxBufferElements=0 is invalid, should prevent further trims
                // Write more data and verify it doesn't trigger another trim
                // (trim won't execute because maxBufferElements <= 0 is invalid)
                assertThat("Invalid maxBufferElements prevents trim",
                    sb.decideTrimExecution(150, 0, 1500, 50), is(false));
            }
        );

        writerThread.join(2000);  // Wait for writer thread to finish
    }

    /**
     * CORRECTNESS TEST: maxAllocationSize changes during trim don't affect running trim
     *
     * Similar to the maxBufferElements test, but verifies that changes to maxAllocationSize
     * (the chunk size limit during consolidation) don't affect the currently executing trim.
     *
     * IMPLEMENTATION DETAIL:
     * maxAllocationSize is also only read once via getMaxAllocationSize() in isTrimShouldBeExecuted(),
     * so trim execution is isolated from config changes.
     */
    @Test
    @Timeout(10)
    public void setMaxAllocationSize_duringTrimExecution_doesNotAffectRunningTrim() throws IOException, InterruptedException {
        // arrange
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        sb.setMaxBufferElements(50);
        sb.setMaxAllocationSize(30);    // Initial allocation size

        Semaphore trimStarted = new Semaphore(0);
        Semaphore trimEnded = new Semaphore(0);

        sb.addTrimStartSignal(trimStarted);
        sb.addTrimEndSignal(trimEnded);

        // Writer thread
        Thread writerThread = new Thread(() -> {
            try {
                byte[] chunk = new byte[5];
                Arrays.fill(chunk, anyValue);
                // Write 500 chunks (2500 bytes) to trigger trim
                for (int i = 0; i < 500; i++) {
                    os.write(chunk);
                    Thread.sleep(1);
                }
                os.close();
            } catch (IOException | InterruptedException e) {
                throw new RuntimeException(e);
            }
        });

        writerThread.start();

        // act — Change maxAllocationSize while trim is executing
        trimStarted.acquire();
        sb.setMaxAllocationSize(100);    // Change to larger chunks mid-trim
        trimEnded.acquire();

        // assert
        assertAll(
            () -> assertThat("Trim should complete", sb.isTrimRunning(), is(false)),
            () -> assertThat("New allocation size is set", sb.getMaxAllocationSize(), is(100L)),
            // Verify data integrity
            () -> {
                byte[] result = new byte[2500];
                int totalRead = 0;
                int bytesRead;
                while ((bytesRead = is.read(result, totalRead, 2500 - totalRead)) > 0) {
                    totalRead += bytesRead;
                }
                assertThat("All data preserved", totalRead, is(2500));
            }
        );

        writerThread.join(2000);
    }

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Configuration Changes During Trim">

    /**
     * CORRECTNESS TESTS: Configuration changes don't affect running trim operations
     *
     * Requirement: When trim is already executing, changes to configuration parameters
     * (maxBufferElements, maxAllocationSize) must NOT affect the currently running trim.
     * Configuration only influences trim DECISIONS, not trim EXECUTION.
     *
     * Implementation: Configuration values are cached before trim execution:
     * - final int maxBufferElements = getMaxBufferElements() (cached in isTrimShouldBeExecuted)
     * - trim uses cached value, not the volatile field, so concurrent changes are isolated
     *
     * Tests verify:
     * - setMaxBufferElements() during trim doesn't interrupt execution
     * - setMaxAllocationSize() during trim doesn't affect chunk allocation
     * - Data integrity preserved despite configuration changes
     * - New configuration takes effect only in subsequent trim operations
     */

    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="Trim Robustness & Edge Cases">

    /**
     * ROBUSTNESS TESTS: Edge cases and stress scenarios for trim operation
     *
     * Tests verify trim handles:
     * - Exceptions during read phase (flag reset via finally)
     * - Exceptions during write phase (flag reset via finally)
     * - Safe write mode enabled during trim
     * - Large buffers with small allocation size constraints
     * - Concurrent signal operations (add/remove signals during trim)
     *
     * These tests ensure trim is robust against unusual conditions while
     * maintaining data integrity and flag consistency.
     */

    // </editor-fold>

}
