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

import com.tngtech.java.junit.dataprovider.DataProvider;
import com.tngtech.java.junit.dataprovider.DataProviderRunner;
import com.tngtech.java.junit.dataprovider.UseDataProvider;
import org.junit.Test;

import java.io.*;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.not;
import static org.hamcrest.number.OrderingComparison.greaterThan;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertThat;
import static org.junit.Assert.assertArrayEquals;
import org.junit.Ignore;
import org.junit.Rule;
import org.junit.rules.ExpectedException;
import org.junit.runner.RunWith;

@RunWith(DataProviderRunner.class)
public class StreamBufferTest {
    
    private final static String DATA_PROVIDER_WRITE_METHODS = "writeMethods";

    @Rule
    public ExpectedException thrown = ExpectedException.none();
    
    @DataProvider
    public static Object[][] writeMethods() {
        return new Object[][] {
            { WriteMethod.ByteArray },
            { WriteMethod.Int },
            { WriteMethod.ByteArrayWithParameter },
        };
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

        assertEquals((long) 0, (long) target[0]);
        assertEquals((long) 0, (long) target[11]);

        for (int i = 1; i < target.length - 1; ++i) {
            assertEquals(anyValue, (long) target[i]);
        }
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
        assertEquals(0, fromMemory[0]);
        assertEquals(0, fromMemory[1]);
        assertEquals(anyNumber, fromMemory[2]);
        assertEquals(anyNumber, fromMemory[3]);
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

        assertEquals(t0[0], 4);
        assertEquals(t0[1], 4);
        assertEquals(t0[2], 4);
        assertEquals(t0[3], 4);
        assertEquals(t0[4], 5);
        assertEquals(t0[5], 5);

        assertEquals(t1[0], 5);
        assertEquals(t1[1], 5);
        assertEquals(t1[2], 5);
        assertEquals(t1[3], 6);
        assertEquals(t1[4], 6);
        assertEquals(t1[5], 6);

        assertEquals(t2[0], 6);
        assertEquals(t2[1], 6);
        assertEquals(t2[2], 6);
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

    @Test(expected = NullPointerException.class)
    public void read_nullDestGiven_throwNullPointerException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();
        is.read(null, 0, 0);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_useInvalidOffset_throwIndexOutOfBoundsException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        is.read(dest, 3, 1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_lengthGreaterThanDestination_throwIndexOutOfBoundsException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        is.read(dest, 0, 2);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_negativeLength_throwIndexOutOfBoundsException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        is.read(dest, 0, -1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_negativeOffset_throwIndexOutOfBoundsException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        InputStream is = sb.getInputStream();

        byte[] dest = new byte[1];
        is.read(dest, -1, 1);
    }

    @Test(expected = NullPointerException.class)
    public void write_nullDestGiven_throwNullPointerException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        os.write(null, 0, 0);
    }

    @Test
    public void write_useInvalidOffset_throwIndexOutOfBoundsException() throws IOException {
        thrown.expect(IndexOutOfBoundsException.class);
        thrown.expectMessage(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION);
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        os.write(from, 3, 1);
    }

    @Test
    public void write_lengthGreaterThanDestination_throwIndexOutOfBoundsException() throws IOException {
        thrown.expect(IndexOutOfBoundsException.class);
        thrown.expectMessage(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION);
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        os.write(from, 0, 2);
    }

    @Test
    public void write_negativeLength_throwIndexOutOfBoundsException() throws IOException {
        thrown.expect(IndexOutOfBoundsException.class);
        thrown.expectMessage(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION);
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        os.write(from, 0, -1);
    }

    @Test
    public void write_negativeOffset_throwIndexOutOfBoundsException() throws IOException {
        thrown.expect(IndexOutOfBoundsException.class);
        thrown.expectMessage(StreamBuffer.EXCEPTION_MESSAGE_CORRECT_OFFSET_AND_LENGTH_TO_WRITE_INDEX_OUT_OF_BOUNDS_EXCEPTION);
        
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();

        byte[] from = new byte[1];
        os.write(from, -1, 1);
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

    @Test(expected = IOException.class)
    @UseDataProvider( DATA_PROVIDER_WRITE_METHODS )
    public void write_closedStream_throwIOException(WriteMethod writeMethod) throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        os.close();
        writeAnyValue(writeMethod, os);
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
    
    @Test
    @UseDataProvider( DATA_PROVIDER_WRITE_METHODS )
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
    
    @Test
    @UseDataProvider( DATA_PROVIDER_WRITE_METHODS )
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

        assertArrayEquals("Read data should match written data", written, read);
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

        assertArrayEquals("Trimmed buffer should preserve all byte order", input, output);
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

    @Test(expected = NullPointerException.class)
    public void write_nullArrayWithOffset_throwsNPE() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.getOutputStream().write(null, 0, 1);
    }
    
    @Test(timeout = 3000)
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

        assertSame("StreamBuffer should return the same InputStream instance", first, second);
    }
    
    @Test(timeout = 10_000)
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
}
