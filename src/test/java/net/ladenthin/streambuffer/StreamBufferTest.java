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

import java.io.ByteArrayOutputStream;
import java.io.DataInput;
import java.io.DataInputStream;
import java.io.DataOutput;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.not;
import static org.hamcrest.number.OrderingComparison.*;
import org.junit.Assert;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThat;
import org.junit.Test;

public class StreamBufferTest {

    /**
     * The answer to all questions.
     */
    private final static byte anyValue = 42;

    @Test
    public void testSimpleRoundTrip() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(0);
        byte[] b0 = new byte[10];
        for (int i = 0; i < b0.length; ++i) {
            b0[i] = anyValue;
        }
        sb.os.write(b0);
        sb.os.write(0);

        assertEquals(12, sb.is.available());

        byte[] target = new byte[12];
        sb.is.read(target);

        assertEquals((long) 0, (long) target[0]);
        assertEquals((long) 0, (long) target[11]);

        for (int i = 1; i < target.length - 1; ++i) {
            assertEquals(anyValue, (long) target[i]);
        }
    }

    /**
     * This test verifies the read method of the input stream to write the
     * bytes at a specific offset.
     * @throws IOException 
     */
    @Test
    public void testSafeWriteSimpleOffset() throws IOException {
        final StreamBuffer sb = new StreamBuffer();
        sb.setSafeWrite(false);
        // the initial value
        final byte anyNumber = (byte) 4;

        /**
         * Create a new array with initial values.
         */
        final byte[] content = new byte[]{anyNumber, anyNumber, anyNumber};

        /**
         * Write the array to the stream.
         */
        sb.os.write(content);

        /**
         * Ensure the array was completly written to the stream.
         */
        assertEquals(3, sb.is.available());

        /**
         * A buffer to read the content from the stream.
         */
        final byte[] fromMemory = new byte[4];

        /**
         * Read 2 bytes to a offset of 2 bytes.
         */
        final int read = sb.is.read(fromMemory, 2, 2);

        /**
         * Ensure only 2 values have been read.
         */
        assertEquals(2, read);

        /**
         * Ensure 1 value is remaining in the stream.
         */
        assertEquals(1, sb.is.available());

        /**
         * Ensure the initial values were written at the specific offset. The
         * first 2 values should be 0 (unwritten). The last 2 values
         * should be the initial value 4.
         */
        assertEquals(0, fromMemory[0]);
        assertEquals(0, fromMemory[1]);
        assertEquals(anyNumber, fromMemory[2]);
        assertEquals(anyNumber, fromMemory[3]);
    }

    @Test
    public void testMultipleArray() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        byte[] b4 = new byte[]{4, 4, 4, 4};
        byte[] b5 = new byte[]{5, 5, 5, 5, 5};
        byte[] b6 = new byte[]{6, 6, 6, 6, 6, 6};
        sb.os.write(b4);
        sb.os.write(b5);
        sb.os.write(b6);
        assertEquals(4 + 5 + 6, sb.is.available());

        byte[] t0 = new byte[6];
        byte[] t1 = new byte[6];
        byte[] t2 = new byte[3];
        sb.is.read(t0);
        sb.is.read(t1);
        sb.is.read(t2);

        assertEquals((4 + 5 + 6) - (6 + 6 + 3), sb.is.available());

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
        for (int i = 1; i <= 255; ++i) {
            byte[] array = new byte[i];
            if (i >= 250) {
                System.out.println();
            }
            // fill up with content
            for (int j = 0; j < array.length; ++j) {
                array[j] = (byte) i;
            }

            sb.os.write(array);
            baosOriginalData.write(array);
        }

        final byte[] originalData = baosOriginalData.toByteArray();

        assertEquals(size, sb.is.available());

        ByteArrayOutputStream baosReadFromTwist = new ByteArrayOutputStream(size);
        long readBytes = 0;
        for (int i = 255; i >= 1; --i) {
            readBytes += i;
            byte[] array = new byte[i];

            sb.is.read(array);
            assertEquals(size - readBytes, sb.is.available());
            baosReadFromTwist.write(array);
        }

        assertEquals(size, readBytes);

        assertEquals(0, sb.is.available());

        byte[] byteChain = baosReadFromTwist.toByteArray();
        assertEquals(size, byteChain.length);

        for (int i = 0; i < originalData.length; ++i) {
            byte b = originalData[i];
        }

        for (int i = 0; i < byteChain.length; ++i) {
            byte b = byteChain[i];
        }

        Assert.assertArrayEquals(originalData, byteChain);

    }

    @Test
    public void testDataInputOutput() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        DataInput din = new DataInputStream(sb.is);
        DataOutput dout = new DataOutputStream(sb.os);

        final String testString = "test string";

        dout.writeUTF(testString);
        String readUTF = din.readUTF();
        assertEquals(testString, readUTF);
    }

    @Test
    public void constructor_noArguments_NoExceptionThrown() {
        StreamBuffer sb = new StreamBuffer();
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
     * could be changed from outside (the write method create no clones of the
     * written arrays).
     *
     * @throws IOException
     */
    @Test
    public void read_changeBufferFromOutside_hasChanged() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        /**
         * Disable the safe write option.
         */
        sb.setSafeWrite(false);
        /**
         * Create a new byte array which is not immutable.
         */
        byte[] notImmutable = new byte[]{anyValue};
        /**
         * Write the byte array.
         */
        sb.getOutputStream().write(notImmutable);
        /**
         * Change the byte array.
         */
        notImmutable[0]++;
        /**
         * A new byte array for the read method.
         */
        byte[] fromStream = new byte[1];
        /**
         * Read the content out of the stream.
         */
        sb.getInputStream().read(fromStream);

        assertThat(fromStream[0], is(not((byte) anyValue)));
    }

    /**
     * This test verifies that when the option safeWrite is enabled, the buffer
     * couldn't be changed from outside (the write method create clones of the
     * written arrays).
     *
     * @throws IOException
     */
    @Test
    public void read_changeBufferFromOutside_notChanged() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        /**
         * Disable the safe write option.
         */
        sb.setSafeWrite(true);
        /**
         * Create a new byte array which is not immutable.
         */
        byte[] notImmutable = new byte[]{anyValue};
        /**
         * Write the byte array.
         */
        sb.getOutputStream().write(notImmutable);
        /**
         * Change the byte array.
         */
        notImmutable[0]++;
        /**
         * A new byte array for the read method.
         */
        byte[] fromStream = new byte[1];
        /**
         * Read the content out of the stream.
         */
        sb.getInputStream().read(fromStream);

        assertThat(fromStream[0], is((byte) anyValue));
    }

    @Test
    public void getBufferSize_reachMaxBufferElements_trimCalled() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(1);

        /**
         * Write more as one element to the stream to force a trim call.
         */
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        assertThat(sb.getBufferSize(), is(1));
    }

    @Test
    public void getBufferSize_reachMaxBufferElements_trimBufferRightValues() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(2);

        /**
         * Write more as one element to the stream to force a trim call.
         */
        sb.getOutputStream().write(1);
        sb.getOutputStream().write(new byte[]{2, 3});
        sb.getOutputStream().write(new byte[]{4, 5, 6});

        byte[] read = new byte[sb.is.available()];
        sb.is.read(read);

        assertThat(read, is(new byte[]{1, 2, 3, 4, 5, 6}));
    }

    @Test
    public void getBufferSize_writeSomeElements_trimNotCalled() throws Exception {
        StreamBuffer sb = new StreamBuffer();

        sb.setMaxBufferElements(4);

        /**
         * Write less than four elements to the stream. The trim method
         * shouldn't called.
         */
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

        /**
         * Write less than four elements to the stream. The trim method
         * shouldn't called.
         */
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);
        sb.getOutputStream().write(anyValue);

        assertThat(sb.getBufferSize(), is(3));
    }

    @Test
    public void read_closedStreamBeforeWrite_ReturnMinusOne() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        sb.os.close();
        assertThat(sb.is.read(), is(-1));
    }

    @Test
    public void read_closedStreamAfterWrite_ReturnMinusOne() throws Exception {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(anyValue);
        sb.os.close();
        /**
         * Read the written value out of the buffer.
         */
        sb.is.read();
        assertThat(sb.is.read(), is(-1));
    }

    @Test(expected = IOException.class)
    public void write_closedStream_throwIOException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.close();
        sb.os.write(anyValue);
    }

    @Test
    public void read_readWithOffset_useOffset() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(new byte[]{anyValue, anyValue, anyValue});

        byte[] dest = new byte[9];
        sb.is.read(dest, 3, 3);
        assertThat(dest, is(new byte[]{0, 0, 0, anyValue, anyValue, anyValue, 0, 0, 0}));
    }

    @Test
    public void read_zeroLength_unmodifiedByteArray() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(new byte[]{anyValue, anyValue, anyValue});

        byte[] dest = new byte[1];
        sb.is.read(dest, 0, 0);
        assertThat(dest, is(new byte[]{0}));
    }

    @Test
    public void read_nothingWritten_returnMinusOne() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.close();
        byte[] dest = new byte[1];
        int read = sb.is.read(dest, 0, 1);
        assertThat(read, is(-1));
    }

    @Test(expected = NullPointerException.class)
    public void read_noDestGiven_throwNullPointerException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.is.read(null, 0, 0);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_useInvalidOffset_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] dest = new byte[1];
        sb.is.read(dest, 3, 1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_greaterLengthAsDestination_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] dest = new byte[1];
        sb.is.read(dest, 0, 2);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_negativeLength_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] dest = new byte[1];
        sb.is.read(dest, 0, -1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void read_negativeOffset_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] dest = new byte[1];
        sb.is.read(dest, -1, 1);
    }

    @Test(expected = NullPointerException.class)
    public void write_noDestGiven_throwNullPointerException() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(null, 0, 0);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void write_useInvalidOffset_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] from = new byte[1];
        sb.os.write(from, 3, 1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void write_greaterLengthAsDestination_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] from = new byte[1];
        sb.os.write(from, 0, 2);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void write_negativeLength_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] from = new byte[1];
        sb.os.write(from, 0, -1);
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void write_negativeOffset_throwIndexOutOfBoundException() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] from = new byte[1];
        sb.os.write(from, -1, 1);
    }

    @Test
    public void write_positiveOffset_bytesNotWritten() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        byte[] from = new byte[]{anyValue, anyValue};
        sb.os.write(from, 1, 1);
        assertThat(sb.is.available(), is(1));
    }

    @Test
    public void available_bufferContainsMoreBytesAsMaxInt_returnMaxValue() throws IOException {
        StreamBuffer sb = new StreamBuffer();

        /**
         * It's not a good idea to allocate a very big array at once. Allocate a
         * small piece instead and write this again and again to the stream. I
         * have choosen 16 pieces and write this value 17 times to force an
         * "overflow" for the method available.
         */
        byte[] from = new byte[Integer.MAX_VALUE / 16];
        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);

        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);

        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);

        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);
        sb.os.write(from);

        sb.os.write(from);
        assertThat(sb.is.available(), is(Integer.MAX_VALUE));
    }
    
    @Test
    public void blockDataAvailable_writeToStream_return() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore s = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    s.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });
        consumer.start();
        sb.os.write(anyValue);
        assertThat(s.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }
    
    @Test
    public void blockDataAvailable_closeStream_return() throws IOException, InterruptedException {
        final StreamBuffer sb = new StreamBuffer();
        final Semaphore s = new Semaphore(0);
        Thread consumer = new Thread(new Runnable() {

            public void run() {
                try {
                    sb.blockDataAvailable();
                    s.release();
                } catch (InterruptedException ex) {
                    throw new RuntimeException(ex);
                }
            }
        });
        consumer.start();
        sb.os.close();
        assertThat(s.tryAcquire(10, TimeUnit.SECONDS), is(true));
    }

}
