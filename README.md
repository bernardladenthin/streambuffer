[![Travis build status](https://travis-ci.org/bernardladenthin/streambuffer.svg)](https://travis-ci.org/bernardladenthin/streambuffer)
[![Maven Central](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer/badge.svg)](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer)
[![Coverage Status](https://coveralls.io/repos/github/bernardladenthin/streambuffer/badge.svg)](https://coveralls.io/github/bernardladenthin/streambuffer)
[![codecov](https://codecov.io/gh/bernardladenthin/streambuffer/graph/badge.svg?token=BIO6krrehu)](https://codecov.io/gh/bernardladenthin/streambuffer)
[![Coverity Scan Build Status](https://scan.coverity.com/projects/5453/badge.svg)](https://scan.coverity.com/projects/5453)
[![Known Vulnerabilities](https://snyk.io/test/github/bernardladenthin/streambuffer/badge.svg?targetFile=pom.xml)](https://snyk.io/test/github/bernardladenthin/streambuffer?targetFile=pom.xml)
[![Code Quality: Java](https://img.shields.io/lgtm/grade/java/g/bernardladenthin/streambuffer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/bernardladenthin/streambuffer/context:java)
[![Total Alerts](https://img.shields.io/lgtm/alerts/g/bernardladenthin/streambuffer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/bernardladenthin/streambuffer/alerts)
[![License](http://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fbernardladenthin%2Fstreambuffer.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fbernardladenthin%2Fstreambuffer?ref=badge_shield)

# streambuffer

`StreamBuffer` is a single-class Java library that bridges an `OutputStream` and an `InputStream` through a dynamic, unbounded FIFO queue — solving the fixed-buffer and potential deadlock limitations of Java's built-in `PipedInputStream`/`PipedOutputStream`.

- GitHub: [https://github.com/bernardladenthin/streambuffer](https://github.com/bernardladenthin/streambuffer)

## Getting Started

Pull it from the central Maven repositories:

```xml
<dependency>
  <groupId>net.ladenthin</groupId>
  <artifactId>streambuffer</artifactId>
  <version>1.1.0</version>
</dependency>
```

### Basic Usage

```java
StreamBuffer sb = new StreamBuffer();
OutputStream os = sb.getOutputStream();
InputStream  is = sb.getInputStream();

os.write(new byte[]{1, 2, 3});

byte[] buf = new byte[3];
is.read(buf); // reads [1, 2, 3]

sb.close();
```

Closing via `sb.close()`, `os.close()`, or `is.close()` all close the entire buffer.

## Motivation

Since JDK 1.0, `PipedInputStream`/`PipedOutputStream` has been available for connecting streams across threads, but it has notable limitations:

- Write operations block when the fixed circular buffer is full, potentially deadlocking the writing thread.
- The circular buffer has a fixed, 32-bit maximum size and does not grow or shrink dynamically.
- Every written byte array is copied into the circular buffer, doubling memory usage in the worst case.
- The buffer does not shrink after reads — a large circular buffer stays large.
- A pipe is considered broken if the thread that provided data is no longer alive, even if data remains in the buffer.

It is also not recommended to use both ends of a pipe from a single thread, as this may deadlock.

## Solution

`StreamBuffer` holds references to written byte arrays directly in a `Deque<byte[]>` (FIFO), without copying data into a secondary circular buffer. This avoids the fixed-size constraint and eliminates write-blocking caused by buffer saturation.

### Similar Solutions

- [Gradle: StreamByteBuffer](https://github.com/gradle/gradle/blob/master/platforms/core-runtime/io/src/main/java/org/gradle/internal/io/StreamByteBuffer.java)

## Features

### Dynamic FIFO Buffer

Instead of a fixed circular buffer, `StreamBuffer` uses a `Deque<byte[]>` that grows as data is written and shrinks as data is read. There is no upper bound on buffered data size at the FIFO level.

### Full `InputStream`/`OutputStream` Compatibility

`StreamBuffer` exposes a standard `InputStream` (via `getInputStream()`) and a standard `OutputStream` (via `getOutputStream()`). Both are full subclass implementations and can be used anywhere those types are accepted.

### Thread Safety

The `InputStream` and `OutputStream` can be used concurrently from different threads without additional synchronization:

- All `Deque` accesses are guarded by a `bufferLock` object.
- State fields (`streamClosed`, `safeWrite`, `availableBytes`, `positionAtCurrentBufferEntry`, `maxBufferElements`) are `volatile`.
- A `Semaphore signalModification` blocks reading threads until data is written or the stream is closed, avoiding busy-waiting. External semaphores can be registered via `addSignal` for thread-decoupled notification.

### No Write Deadlock

In contrast to `PipedOutputStream`, write operations on `StreamBuffer` never block or deadlock — the FIFO grows as needed.

### Smart Partial Reads

`StreamBuffer` tracks a `positionAtCurrentBufferEntry` index within the head byte array. Partial reads consume bytes from the current head entry without copying the remaining data. The trim operation accounts for this index and only copies the unread remainder.

### Safe Write (Immutable Byte Arrays)

By default, `StreamBuffer` stores a direct reference to the written byte array (`safeWrite = false`). If the caller modifies the array after writing, the buffered content may be affected.

Enable safe write mode to clone every written byte array before buffering:

```java
sb.setSafeWrite(true);
```

When writing with an offset (e.g., `write(b, off, len)`), a new byte array of exactly `len` bytes is always created, regardless of the `safeWrite` setting, since only the relevant portion is stored.

### Buffer Trimming

When the `Deque` grows beyond `maxBufferElements` entries (default: `100`), the next write operation consolidates all buffered data into a single byte array. This bounds the number of FIFO elements and can improve read performance for large accumulated buffers.

```java
sb.setMaxBufferElements(50);  // trim when more than 50 elements are queued
sb.setMaxBufferElements(0);   // disable trimming entirely
```

Trimming is triggered by writes, not by `setMaxBufferElements`. The trim internally bypasses `safeWrite` (via an `ignoreSafeWrite` flag) because the byte arrays it produces are not reachable from outside the buffer.

### Large Buffer Support

`available()` returns `Integer.MAX_VALUE` when the number of buffered bytes exceeds `Integer.MAX_VALUE`, correctly handling buffers larger than 2 GB.

### Signal/Slot Notifications

Register external `Semaphore` objects to receive thread-decoupled notifications when the buffer is modified (data written or stream closed). Each registered semaphore is released using the same "max 1 permit" pattern as the internal reader/writer semaphore, enabling observers to block in their own threads and wake up when something changes:

```java
Semaphore mySignal = new Semaphore(0);
sb.addSignal(mySignal);

// Observer's own thread:
while (!done) {
    mySignal.acquire();  // blocks until writer signals
    // process in MY thread — fully decoupled from writer
    if (sb.isClosed()) {
        done = true;
    }
}
```

**API:**

| Method | Description |
|--------|-------------|
| `addSignal(Semaphore)` | Registers an external semaphore; throws `NullPointerException` if null |
| `removeSignal(Semaphore)` | Removes a semaphore; returns `false` if not found or null |

Signals are stored in a `CopyOnWriteArrayList` for thread-safe iteration. The "max 1 permit" pattern means rapid writes collapse into a single wake-up — the observer should check buffer state (e.g., `isClosed()`, `available()`) after waking to determine what changed.

## API Reference

### `StreamBuffer`

```java
public class StreamBuffer implements Closeable
```

| Method | Description |
|--------|-------------|
| `StreamBuffer()` | Constructs a new buffer |
| `getInputStream()` | Returns the `InputStream` end |
| `getOutputStream()` | Returns the `OutputStream` end |
| `close()` | Closes both ends of the buffer |
| `isClosed()` | Returns `true` if the buffer is closed |
| `isSafeWrite()` | Returns the current `safeWrite` flag |
| `setSafeWrite(boolean)` | Enables or disables safe write (byte array cloning) |
| `getMaxBufferElements()` | Returns the current trim threshold |
| `setMaxBufferElements(int)` | Sets the trim threshold; `<= 0` disables trimming |
| `getBufferSize()` | Returns the current number of byte array entries in the FIFO |
| `addSignal(Semaphore)` | Registers an external semaphore for thread-decoupled notification |
| `removeSignal(Semaphore)` | Removes a registered semaphore |
| `blockDataAvailable()` | **Deprecated.** Blocks until at least one byte is available |

### Static Validation Methods

```java
public static boolean correctOffsetAndLengthToRead(byte[] b, int off, int len)
public static boolean correctOffsetAndLengthToWrite(byte[] b, int off, int len)
```

Both methods mirror the parameter validation performed by `InputStream.read(byte[], int, int)` and `OutputStream.write(byte[], int, int)`. They throw `NullPointerException` for null arrays, `IndexOutOfBoundsException` for invalid offsets or lengths (including integer overflow: `off + len < 0`), and return `false` for zero-length operations.

### Signal/Slot Pattern

External observers register `java.util.concurrent.Semaphore` objects via `addSignal(Semaphore)`. When the buffer is modified (write or close), each registered semaphore is released using the "max 1 permit" pattern — a permit is released only if the semaphore currently has zero permits. The observer blocks on `semaphore.acquire()` in its own thread and wakes up when data is available or the stream is closed. This provides full thread decoupling between writer and observer.

## Deadlock Behavior

### Read

If no data is available and the stream is not closed, `read()` blocks the calling thread. To avoid blocking, only read as many bytes as `available()` reports. The `blockDataAvailable()` method (deprecated) can be used to wait before reading; `tryWaitForEnoughBytes` is the internal successor.

### Write

Write operations never block, regardless of how much data is already buffered.

## Build

Requires Java 8 and Maven 3.3.9+.

```bash
mvn compile          # Compile
mvn test             # Run all tests with coverage
mvn package          # Build JAR
mvn install -Dgpg.skip=true  # Install locally without GPG signing
```

Run a single test:

```bash
mvn test -Dtest=StreamBufferTest#testSimpleRoundTrip
```

Run mutation tests:

```bash
mvn org.pitest:pitest-maven:mutationCoverage
```

## Testing

Tests are in `StreamBufferTest` using JUnit 4 with `DataProviderRunner` from `junit-dataprovider`. Most behavioral tests are parameterized across three write strategies:

| `WriteMethod` | Description |
|---------------|-------------|
| `ByteArray` | `os.write(byte[])` |
| `Int` | `os.write(int)` |
| `ByteArrayWithParameter` | `os.write(byte[], int, int)` |

Test coverage includes:

- Simple and parameterized round-trip reads/writes
- Unsigned byte values (0–255), including high-byte values 128–255 and the `& 0xff` mask
- Partial reads with offset tracking
- Safe write with and without trim interaction
- Trim with boundary conditions (empty buffer, single entry, `maxBufferElements = 0`)
- Buffer trimming and byte-order preservation
- Close via `sb.close()`, `os.close()`, and `is.close()` — all paths tested
- `available()` behavior before and after close, including with buffered data remaining
- Thread interruption during blocked reads (wraps `InterruptedException` in `IOException`)
- Concurrent read/write stress tests
- Parallel close without deadlock
- Signal/slot notification via external semaphores on write and all close paths
- `removeSignal(null)` returning `false` without throwing
- `addSignal(null)` throwing `NullPointerException`
- Thread-decoupled signal barrier — observer wakes in its own thread
- `correctOffsetAndLengthToRead` and `correctOffsetAndLengthToWrite` — all branches including integer overflow
- `getBufferSize()` on an empty buffer
- `blockDataAvailable()` with data written before and after the call

## License

Code is under the [Apache Licence v2](https://www.apache.org/licenses/LICENSE-2.0.txt).

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fbernardladenthin%2Fstreambuffer.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fbernardladenthin%2Fstreambuffer?ref=badge_large)
