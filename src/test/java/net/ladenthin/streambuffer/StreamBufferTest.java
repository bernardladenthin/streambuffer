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
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import java.io.*;
import java.util.Arrays;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.not;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.number.OrderingComparison.greaterThan;
import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

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

    @Test
    public void testSimpleRoundTrip() throws IOException {
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

        byte[] target = new byte[12];
        is.read(target);

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

        // Read 2 bytes at an offset of 2 bytes.
        final int read = is.read(fromMemory, 2, 2);

        // Ensure only 2 values have been read.
        assertEquals(2, read);

        // Ensure 1 value is remaining in the stream.
        assertEquals(1, is.available());

        // Ensure the initial values were placed at the correct offset.
        // The first 2 values should be 0 (unwritten).
        // The last 2 values should be the initial value 4.
        assertArrayEquals(new byte[]{0, 0, anyNumber, anyNumber}, fromMemory);
    }

    @Test
    public void testMultipleArray() throws IOException {
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

        byte[] t0 = new byte[6];
        byte[] t1 = new byte[6];
        byte[] t2 = new byte[3];
        is.read(t0);
        is.read(t1);
        is.read(t2);

        assertEquals((4 + 5 + 6) - (6 + 6 + 3), is.available());

        assertAll(
            () -> assertArrayEquals(new byte[]{4, 4, 4, 4, 5, 5}, t0),
            () -> assertArrayEquals(new byte[]{5, 5, 5, 6, 6, 6}, t1),
            () -> assertArrayEquals(new byte[]{6, 6, 6}, t2)
        );
    }

    @Test
    public void testLoopedRoundtrip() throws IOException {
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

        ByteArrayOutputStream baosReadFromTwist = new ByteArrayOutputStream(size);
        long readBytes = 0;
        for (int i = 255; i >= 1; --i) {
            readBytes += i;
            byte[] array = new byte[i];

            is.read(array);
            assertEquals(size - readBytes, is.available());
            baosReadFromTwist.write(array);
        }

        assertEquals(size, readBytes);

        assertEquals(0, is.available());

        byte[] byteChain = baosReadFromTwist.toByteArray();
        
        assertEquals(size, byteChain.length);
        assertArrayEquals(originalData, byteChain);
    }

    @Test
    public void testDataInputOutput() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        DataInput din = new DataInputStream(is);
        DataOutput dout = new DataOutputStream(os);

        final String testString = "test string";

        dout.writeUTF(testString);
        String readUTF = din.readUTF();
        assertEquals(testString, readUTF);
    }

    @Test
    public void constructor_noArguments_NoExceptionThrown() {
        new StreamBuffer();
    }

    @Test
    public void getMaxBufferElements_initialValue_GreaterZero() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.getMaxBufferElements(), is(greaterThan(0)));
    }

    @Test
    public void getMaxBufferElements_afterSet_Zero() {
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(0);
        assertThat(sb.getMaxBufferElements(), is(0));
    }

    @Test
    public void isSafeWrite_initialValue_false() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isSafeWrite(), is(false));
    }

    @Test
    public void isSafeWrite_afterSet_true() {
        StreamBuffer sb = new StreamBuffer();
        sb.setSafeWrite(true);
        assertThat(sb.isSafeWrite(), is(true));
    }

    @Test
    public void isClosed_afterConstruct_false() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.isClosed(), is(false));
    }

    @Test
    public void isClosed_afterClose_true() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.close();
        assertThat(sb.isClosed(), is(true));
    }

    /**
     * This test verifies that when the option safeWrite is disabled, the buffer
     * can be modified externally (the write method does not create clones of the
     * written arrays).
     *
     * @throws IOException
     */
    @Test
    public void read_changeBufferFromOutside_hasChanged() throws IOException {
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
        // Read the content out of the stream.
        sb.getInputStream().read(fromStream);

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
        // Read the content out of the stream.
        sb.getInputStream().read(fromStream);

        assertThat(fromStream[0], is((byte) anyValue));
    }

    @Test
    public void getBufferSize_reachMaxBufferElements_trimCalled() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(1);

        // Write more than one element to the stream to force a trim call.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        int result = sb.getBufferSize();

        assertThat(result, is(1));
    }

    @Test
    public void getBufferSize_reachMaxBufferElements_trimBufferRightValues() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        sb.setMaxBufferElements(2);

        // Write more than one element to the stream to force a trim call.
        sb.getOutputStream().write(1);
        sb.getOutputStream().write(new byte[]{2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});

        byte[] read = new byte[is.available()];
        is.read(read);

        assertThat(read, is(new byte[]{1, 2, 3, 4, 5, 6}));
    }

    @Test
    public void getBufferSize_writeSomeElements_trimNotCalled() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(4);

        // Write fewer than four elements to the stream.
        // The trim method should not be called.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        assertThat(sb.getBufferSize(), is(3));
    }

    @Test
    public void setMaxBufferElements_writeNegativeValue_equalsToGetter() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(-1);
        assertThat(-1, is(sb.getMaxBufferElements()));
    }

    @Test
    public void setMaxBufferElements_useNegativeValue_trimNotCalled() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(-1);

        // Write fewer than four elements to the stream.
        // The trim method should not be called.
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        assertThat(sb.getBufferSize(), is(3));
    }

    @Test
    public void read_closedStreamBeforeWrite_ReturnMinusOne() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.close();
        assertThat(is.read(), is(-1));
    }

    @Test
    public void read_closedStreamAfterWrite_ReturnMinusOne() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(anyValue);
        os.close();
        // Read the previously written value from the buffer.
        is.read();
        assertThat(is.read(), is(-1));
    }

    @Test
    public void read_readWithOffset_useOffset() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{anyValue, anyValue, anyValue});

        byte[] dest = new byte[9];
        is.read(dest, 3, 3);
        assertThat(dest, is(new byte[]{0, 0, 0, anyValue, anyValue, anyValue, 0, 0, 0}));
    }

    @Test
    public void read_zeroLength_unmodifiedByteArray() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.write(new byte[]{anyValue, anyValue, anyValue});

        byte[] dest = new byte[1];
        is.read(dest, 0, 0);
        assertThat(dest, is(new byte[]{0}));
    }

    @Test
    public void read_nothingWritten_returnMinusOne() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        os.close();
        byte[] dest = new byte[1];
        int read = is.read(dest, 0, 1);
        assertThat(read, is(-1));
    }

    @Test
    public void read_nullDestGiven_throwNullPointerException() {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        assertThrows(NullPointerException.class, () -> is.read(null, 0, 0));
    }

    @Test
    public void read_useInvalidOffset_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 3, 1));
    }

    @Test
    public void read_lengthGreaterThanDestination_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 0, 2));
    }

    @Test
    public void read_negativeLength_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, 0, -1));
    }

    @Test
    public void read_negativeOffset_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        assertThrows(IndexOutOfBoundsException.class, () -> is.read(dest, -1, 1));
    }

    @Test
    public void write_nullDestGiven_throwNullPointerException() {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        assertThrows(NullPointerException.class, () -> os.write(null, 0, 0));
    }

    @Test
    public void write_useInvalidOffset_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 3, 1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_lengthGreaterThanDestination_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 0, 2));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_negativeLength_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, 0, -1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_negativeOffset_throwIndexOutOfBoundsException() {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> os.write(from, -1, 1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void write_withValidOffset_partialWriteSuccessful() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[]{anyValue, anyValue};
        os.write(from, 1, 1);

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
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        assertThrows(IOException.class, () -> {
            os.close();
            writeAnyValue(writeMethod, os);
        });
    }
    
    @Test
    public void write_invalidOffset_notWritten() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        int invalidOffset = 1;
        os.write(new byte[]{anyValue}, invalidOffset, 0);
        
        assertThat( sb.getBufferSize(), is(0));
    }
    
    @Test
    public void write_invalidLength_notWritten() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        int invalidLength = 0;
        os.write(new byte[]{anyValue}, 0, invalidLength);
        
        assertThat( sb.getBufferSize(), is(0));
    }

    @Test
    public void available_bufferContainsMoreBytesAsMaxInt_returnMaxValue() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        
        int chunks = 16;

         // It's not a good idea to allocate a very big array at once.
         // Allocate a small piece instead and write this again and again to the stream.
         // I have chosen 16 pieces and written this value 17 times
         // to trigger an overflow in the available() method.
        byte[] chunk = new byte[Integer.MAX_VALUE / chunks];
        for (int i = 0; i < chunks; i++) {
            os.write(chunk);
        }
        // write one additional
        os.write(chunk);

        assertThat(is.available(), is(Integer.MAX_VALUE));
    }
    
    @ParameterizedTest
    @MethodSource("writeMethods")
    public void blockDataAvailable_dataWrittenBefore_noWaiting(WriteMethod writeMethod) throws IOException, InterruptedException {
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
        consumer.start();
        sleepOneSecond();

        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }
    
    @Test
    public void blockDataAvailable_dataWrittenBeforeAndReadAfterwards_waiting() throws IOException, InterruptedException {
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
        consumer.start();
        sleepOneSecond();

        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(false));
    }
    
    @Test
    public void blockDataAvailable_streamUntouched_waiting() throws IOException, InterruptedException {
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
        consumer.start();
        sleepOneSecond();
        after.drainPermits();

        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(false));
    }
    
    @ParameterizedTest
    @MethodSource("writeMethods")
    public void blockDataAvailable_writeToStream_return(WriteMethod writeMethod) throws IOException, InterruptedException {
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
        consumer.start();
        sleepOneSecond();
        after.drainPermits();
        writeAnyValue(writeMethod, os);

        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }
    
    /**
     * Sleep one second to allow the method to block the thread correctly.
     */
    private void sleepOneSecond() throws InterruptedException {
        Thread.sleep(1000);
    }
    
    @Test
    public void blockDataAvailable_closeStream_return() throws IOException, InterruptedException {
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
        consumer.start();
        sleepOneSecond();
        after.drainPermits();
        os.close();

        assertThat(after.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }
    
    @Test
    public void blockDataAvailable_streamAlreadyClosed_return() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();

        sb.close();
        sb.blockDataAvailable();
    }

    @Test
    public void read_closeStream_returnsWrittenBytes() throws IOException, InterruptedException {
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
        consumer.start();
        byte[] dest = new byte[3];
        int read = is.read(dest);

        assertThat(read, is(1));
    }

    @Test
    public void mark_useBufferedInputStream_resetPosition() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        OutputStream os = sb.getOutputStream();
        
        int size = 3;
        BufferedInputStream bis = new BufferedInputStream(is, size);
        for (int i = 0; i < size; i++) {
            os.write(anyValue);
        }
        bis.mark(1);
        bis.read();
        bis.reset();
        
        int result = bis.available();
        
        assertThat(result, is(size));
    }
    
    @Test
    public void blockDataAvailable_dataAlreadyAvailable_onlyOneWakeup() throws Exception {
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

        consumer1.start();
        consumer2.start();
        ready.acquire(2); // wait for both threads to be ready
        done.tryAcquire(1, TimeUnit.SECONDS); // one should proceed
        Thread.sleep(100); // give it some time
        int acquired = done.drainPermits(); // number of threads that actually returned

        assertThat("Only one thread should proceed due to single permit", acquired, is(1));
    }
    
    @Test
    public void concurrentReadWrite_stressTest_noCrashOrInconsistency() throws Exception {
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

        writer.start();
        reader.start();
        writer.join();
        reader.join();

        assertArrayEquals(written, read, "Read data should match written data");
    }
    
    @Test
    public void blockDataAvailable_multipleWritesBeforeCall_doesNotBlock() throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        os.write(anyValue);
        os.write(anyValue);

        // Should not block since data is already written
        sb.blockDataAvailable();
    }
    
    @Test
    public void trim_preservesAllBytesInCorrectOrder() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(2);

        byte[] input = new byte[10];
        for (int i = 0; i < 10; i++) input[i] = (byte) i;
        for (int i = 0; i < 10; i++) {
            sb.getOutputStream().write(new byte[]{input[i]});
        }

        byte[] output = new byte[10];
        sb.getInputStream().read(output);

        assertArrayEquals(input, output, "Trimmed buffer should preserve all byte order");
    }
    
    @Test
    public void read_afterTrimAndClose_returnsRemainingBytesThenEOF() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);

        sb.getOutputStream().write(new byte[]{1, 2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});
        sb.close();

        byte[] buffer = new byte[6];
        int read = sb.getInputStream().read(buffer);

        assertThat("Should read all bytes", read, is(6));
        assertThat("Should return EOF", sb.getInputStream().read(), is(-1));
    }
    
    @Test
    public void close_multipleCalls_noExceptionThrown() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.close();
        sb.close(); // Should not throw
    }
    
    @Test
    public void trim_emptyBuffer_noExceptionThrown() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.setMaxBufferElements(1);
        // nothing written yet, but trim should not fail
        sb.getOutputStream().write(new byte[0]);
    }
    
    @Test
    public void read_afterImmediateClose_returnsEOF() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.close();
        assertThat(sb.getInputStream().read(), is(-1));
    }

    @Test
    public void write_nullArrayWithOffset_throwsNPE() {
        StreamBuffer sb = new StreamBuffer();
        assertThrows(NullPointerException.class, () -> sb.getOutputStream().write(null, 0, 1));
    }

    @Test
    @Timeout(3)
    public void read_parallelClose_noDeadlock() throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final InputStream is = sb.getInputStream();

        Thread reader = new Thread(() -> {
            try {
                is.read(); // Should block initially, then unblock on close
            } catch (IOException e) {
                // Expected when stream is closed
            }
        });

        reader.start();
        Thread.sleep(500); // Let the read() call block
        sb.close();        // Should unblock the reader
        reader.join();     // Ensure thread completes
    }
    
    @Test
    public void available_afterMultipleWrites_correctCount() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        // Write 5 chunks, each of 2 bytes
        for (int i = 0; i < 5; i++) {
            os.write(new byte[]{1, 2});
        }

        assertThat("available() should reflect the correct byte count", is.available(), is(10));
    }
    
    @Test
    public void alternatingReadWrite_smallChunks_correctOrder() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        for (int i = 0; i < 100; i++) {
            os.write(i);
            assertThat(is.read(), is(i));
        }

        assertThat("Stream should be empty after balanced writes/reads", is.available(), is(0));
    }
    
    @Test
    public void blockDataAvailable_afterBytesConsumed_blocksAgain() throws Exception {
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
        thread.start();

        Thread.sleep(500); // give thread time to block
        assertThat("Thread should block since no new data was written", signal.tryAcquire(), is(false));

        os.write(anyValue);
        assertThat("Thread should wake up after new data", signal.tryAcquire(2, TimeUnit.SECONDS), is(true));
    }
    
    /**
     * This test documents that multiple calls to getInputStream()
     * return the same shared InputStream instance.
     * 
     * Note: StreamBuffer is designed to support a single consumer. 
     * Repeated calls return the same instance; independent parallel reads are not supported.
     */
    @Test
    public void multipleInputStream_returnsSameInstance_eachCall() {
        StreamBuffer sb = new StreamBuffer();
        InputStream first = sb.getInputStream();
        InputStream second = sb.getInputStream();

        assertSame(first, second, "StreamBuffer should return the same InputStream instance");
    }
    
    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToRead">
    @Test
    public void correctOffsetAndLengthToRead_nullArray_throwsNullPointerException() {
        // act
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
    }

    @Test
    public void correctOffsetAndLengthToRead_negativeLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(b, 0, -1));
    }

    @Test
    public void correctOffsetAndLengthToRead_lengthExceedsRemainingArray_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(b, 3, 3));
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
        // act
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
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_negativeLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 0, -1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_offsetExceedsArrayLength_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[1];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 2, 1));
        assertThat(ex.getMessage(), is(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION));
    }

    @Test
    public void correctOffsetAndLengthToWrite_lengthExceedsRemainingArray_throwsIndexOutOfBoundsException() {
        // arrange
        byte[] b = new byte[5];

        // act
        IndexOutOfBoundsException ex = assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToWrite(b, 3, 3));
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
    @Timeout(5)
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
    @Timeout(5)
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

    @Test
    @Timeout(10)
    public void concurrentTrimAndWrite_noCrashOrCorruption() throws Exception {
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

        writer.start();
        trimmer.start();
        reader.start();

        writer.join();
        os.close(); // gracefully signal end of writing
        trimmer.join();
        reader.join();
    }

    // <editor-fold defaultstate="collapsed" desc="signal/slot">
    @Test
    public void signal_addSignalAndWrite_signalReleased() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        sb.addSignal(signal);
        sb.getOutputStream().write(anyValue);

        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_addSignalAndClose_signalReleased() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        sb.addSignal(signal);
        sb.close();

        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_multipleSignals_allReleased() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal1 = new Semaphore(0);
        final Semaphore signal2 = new Semaphore(0);
        final Semaphore signal3 = new Semaphore(0);

        sb.addSignal(signal1);
        sb.addSignal(signal2);
        sb.addSignal(signal3);
        sb.getOutputStream().write(anyValue);

        assertAll(
            () -> assertThat(signal1.tryAcquire(5, TimeUnit.SECONDS), is(true)),
            () -> assertThat(signal2.tryAcquire(5, TimeUnit.SECONDS), is(true)),
            () -> assertThat(signal3.tryAcquire(5, TimeUnit.SECONDS), is(true))
        );
    }

    @Test
    public void signal_removeSignal_notReleased() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        sb.addSignal(signal);
        boolean removed = sb.removeSignal(signal);
        sb.getOutputStream().write(anyValue);

        assertAll(
            () -> assertThat(removed, is(true)),
            () -> assertThat(signal.tryAcquire(1, TimeUnit.SECONDS), is(false))
        );
    }

    @Test
    public void signal_removeNonExistentSignal_returnsFalse() {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        boolean removed = sb.removeSignal(signal);
        assertThat(removed, is(false));
    }

    @Test
    public void signal_addNullSignal_throwsNullPointerException() {
        final StreamBuffer sb = new StreamBuffer();

        assertThrows(NullPointerException.class, () -> sb.addSignal(null));
    }

    @Test
    public void signal_threadBarrier_observerWakesInOwnThread() throws IOException, InterruptedException {
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

        // writer writes from the main thread
        sb.getOutputStream().write(anyValue);

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
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        sb.addSignal(signal);
        sb.getOutputStream().close();

        assertThat(signal.tryAcquire(5, TimeUnit.SECONDS), is(true));
    }

    @Test
    public void signal_closeViaInputStream_signalReleased() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore signal = new Semaphore(0);

        sb.addSignal(signal);
        sb.getInputStream().close();

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
    @Timeout(5)
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
    @Timeout(5)
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
        // act
        assertThrows(IndexOutOfBoundsException.class,
            () -> StreamBuffer.correctOffsetAndLengthToRead(new byte[0], 0, 1));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="correctOffsetAndLengthToWrite empty array">
    @Test
    public void correctOffsetAndLengthToWrite_emptyArrayZeroLength_returnsFalse() {
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
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE + 1), is(Integer.MAX_VALUE));
    }

    @Test
    public void clampToMaxInt_valueEqualToMaxInt_returnsMaxInt() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.clampToMaxInt((long) Integer.MAX_VALUE), is(Integer.MAX_VALUE));
    }

    @Test
    public void clampToMaxInt_smallValue_returnsValue() {
        StreamBuffer sb = new StreamBuffer();
        assertThat(sb.clampToMaxInt(42L), is(42));
    }
    // </editor-fold>

    // <editor-fold defaultstate="collapsed" desc="decrementAvailableBytesBudget direct">
    @Test
    public void decrementAvailableBytesBudget_subtractsDecrement() {
        // original: current - decrement = 9 - 4 = 5
        // mutant:   current + decrement = 9 + 4 = 13  → mutation killed
        StreamBuffer sb = new StreamBuffer();
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
        int oldResult = capMissingBytesOld(maximumAvailableBytes, missingBytes);
        int newResult = capMissingBytesNew(maximumAvailableBytes, missingBytes);
        assertThat(newResult, is(oldResult));
    }

    // </editor-fold>
}
