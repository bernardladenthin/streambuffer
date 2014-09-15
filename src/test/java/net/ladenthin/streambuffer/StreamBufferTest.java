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
import org.junit.Assert;
import static org.junit.Assert.assertEquals;
import org.junit.Test;

public class StreamBufferTest {

    @Test
    public void testSimpleRoundTrip() throws IOException {
        byte testValue = 99;

        StreamBuffer sb = new StreamBuffer();
        sb.os.write(0);
        byte[] b0 = new byte[10];
        for (int i = 0; i < b0.length; ++i) {
            b0[i] = testValue;
        }
        sb.os.write(b0);
        sb.os.write(0);

        assertEquals(12, sb.is.available());

        byte[] target = new byte[12];
        sb.is.read(target);

        assertEquals((long) 0, (long) target[0]);
        assertEquals((long) 0, (long) target[11]);

        for (int i = 1; i < target.length - 1; ++i) {
            assertEquals((long) testValue, (long) target[i]);
        }
    }

    @Test
    public void testDestinationOffset() throws IOException {
        byte testValue = 99;

        StreamBuffer sb = new StreamBuffer();
        byte[] b0 = new byte[6];
        for (int i = 0; i < b0.length; ++i) {
            b0[i] = testValue;
        }
        sb.os.write(b0);

        assertEquals(6, sb.is.available());

        byte[] target0 = new byte[4];
        sb.is.read(target0, 2, 2);

        byte[] target1 = new byte[4];
        sb.is.read(target1, 2, 2);

        byte[] target2 = new byte[4];
        sb.is.read(target2, 2, 2);

        assertEquals((long) target0[0], (long) 0);
        assertEquals((long) target0[1], (long) 0);
        for (int i = 2; i < target0.length; ++i) {
            assertEquals((long) testValue, (long) target0[i]);
        }

        assertEquals((long) target1[0], (long) 0);
        assertEquals((long) target1[1], (long) 0);
        for (int i = 2; i < target1.length; ++i) {
            assertEquals((long) testValue, (long) target1[i]);
        }

        assertEquals((long) target2[0], (long) 0);
        assertEquals((long) target2[1], (long) 0);
        for (int i = 2; i < target2.length; ++i) {
            assertEquals((long) testValue, (long) target2[i]);
        }
    }

    @Test(expected = IOException.class)
    public void testWriteOnClosedStream() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(-1);
        // test closed stream
        sb.os.close();

        final int v0 = sb.is.read();
        assertEquals(255, v0);
        int read = sb.is.read();
        assertEquals(-1, read);

        sb.os.write(-1);
    }

    @Test
    public void testClosedStream() throws IOException {
        StreamBuffer sb = new StreamBuffer();
        sb.os.write(-1);
        sb.os.write(-1);
        sb.os.write(-1);

        final int v0 = sb.is.read();
        final int v1 = sb.is.read();
        final int v2 = sb.is.read();
        assertEquals(255, v0);
        assertEquals(255, v1);
        assertEquals(255, v2);

        // test closed stream
        sb.os.close();
        int read = sb.is.read();
        assertEquals(-1, read);
    }

    @Test
    public void testSafeWriteSimpleOffset() throws IOException {
        StreamBuffer sb = new StreamBuffer(false);
        byte[] content = new byte[]{4, 4, 4};
        sb.os.write(content);

        byte[] fromMemory = new byte[4];
        int read = sb.is.read(fromMemory, 2, 2);

        assertEquals(0, fromMemory[0]);
        assertEquals(0, fromMemory[1]);
        assertEquals(4, fromMemory[2]);
        assertEquals(4, fromMemory[3]);
    }

    @Test
    public void testSafeWriteFalse() throws IOException {
        StreamBuffer sb = new StreamBuffer(false);
        byte[] notImmutable = new byte[]{4, 4};
        sb.os.write(notImmutable);

        // change the memory from outside
        notImmutable[0] = 5;
        notImmutable[1] = 5;

        byte[] fromMemory = new byte[2];
        int read = sb.is.read(fromMemory);

        assertEquals(5, fromMemory[0]);
        assertEquals(5, fromMemory[1]);
    }

    @Test
    public void testSafeWriteTrue() throws IOException {
        StreamBuffer sb = new StreamBuffer(true);
        byte[] notImmutable = new byte[]{4, 4};
        sb.os.write(notImmutable);

        // change the memory from outside
        notImmutable[0] = 5;
        notImmutable[1] = 5;

        byte[] fromMemory = new byte[2];
        int read = sb.is.read(fromMemory);

        assertEquals(4, fromMemory[0]);
        assertEquals(4, fromMemory[1]);
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
    public void testTrim() throws IOException {
        StreamBuffer sb = new StreamBuffer(333);
        final byte value = 55;
        final int numberElements = 1_000;
        // write all values to the buffer
        for (int i = 0; i < numberElements; ++i) {
            sb.os.write(value);
        }

        assertEquals(numberElements, sb.is.available());

        // read all values from the buffer and compare the value
        for (int i = 0; i < numberElements; ++i) {
            int read = sb.is.read();
            assertEquals(value, read);
        }

        assertEquals(0, sb.is.available());
    }
}
