// SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
package net.ladenthin.streambuffer;

import net.jqwik.api.ForAll;
import net.jqwik.api.Property;
import net.jqwik.api.constraints.IntRange;
import net.jqwik.api.constraints.Size;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;

public class StreamBufferProperties {

    @Property
    boolean writeAllThenReadAvailableYieldsConcatenation(
            @ForAll @Size(min = 0, max = 32) List<@Size(min = 0, max = 256) byte[]> chunks
    ) throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        ByteArrayOutputStream expected = new ByteArrayOutputStream();
        for (byte[] chunk : chunks) {
            os.write(chunk);
            expected.write(chunk);
        }

        int available = is.available();
        if (available != expected.size()) return false;
        if (available == 0) return true;

        byte[] read = new byte[available];
        int n = is.read(read, 0, available);
        if (n != available) return false;

        return java.util.Arrays.equals(read, expected.toByteArray());
    }

    @Property
    boolean readChunkSizeDoesNotAffectContent(
            @ForAll @Size(min = 1, max = 1024) byte[] payload,
            @ForAll @IntRange(min = 1, max = 64) int writeChunk,
            @ForAll @IntRange(min = 1, max = 64) int readChunk
    ) throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        for (int off = 0; off < payload.length; off += writeChunk) {
            int len = Math.min(writeChunk, payload.length - off);
            os.write(payload, off, len);
        }

        byte[] out = new byte[payload.length];
        int read = 0;
        while (read < payload.length) {
            int len = Math.min(readChunk, payload.length - read);
            int n = is.read(out, read, len);
            if (n <= 0) return false;
            read += n;
        }

        return java.util.Arrays.equals(payload, out);
    }

    @Property
    boolean counterAccountingIsConsistent(
            @ForAll @Size(min = 0, max = 16) List<@Size(min = 0, max = 128) byte[]> writes,
            @ForAll @IntRange(min = 0, max = 16) int readChunk
    ) throws IOException {
        StreamBuffer sb = new StreamBuffer();
        OutputStream os = sb.getOutputStream();
        InputStream is = sb.getInputStream();

        long expectedWritten = 0;
        for (byte[] w : writes) {
            os.write(w);
            expectedWritten += w.length;
        }

        long expectedRead = 0;
        if (readChunk > 0) {
            byte[] buf = new byte[readChunk];
            while (is.available() > 0) {
                int n = is.read(buf, 0, Math.min(readChunk, is.available()));
                if (n <= 0) break;
                expectedRead += n;
            }
        }

        if (sb.getTotalBytesWritten() != expectedWritten) return false;
        if (sb.getTotalBytesRead() != expectedRead) return false;
        return sb.getTotalBytesWritten() == sb.getTotalBytesRead() + is.available();
    }
}
