# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
mvn compile          # Compile
mvn test             # Run all tests with coverage
mvn package          # Build JAR
mvn install -Dgpg.skip=true  # Install to local repo without GPG signing
```

**Run a single test:**
```bash
mvn test -Dtest=StreamBufferTest#testSimpleRoundTrip
```

**Run mutation tests:**
```bash
mvn org.pitest:pitest-maven:mutationCoverage
```

## Architecture

`StreamBuffer` is a single-class Java library (`net.ladenthin.streambuffer`) that connects an `OutputStream` and `InputStream` through a dynamic FIFO queue — solving the fixed-buffer and cross-thread-deadlock limitations of Java's `PipedInputStream`/`PipedOutputStream`.

### Core Class: `StreamBuffer`

`src/main/java/net/ladenthin/streambuffer/StreamBuffer.java`

- Implements `Closeable`
- Internal FIFO: `Deque<byte[]>` (stores byte array references, not copies)
- Exposes `getInputStream()` → `SBInputStream extends InputStream`
- Exposes `getOutputStream()` → `SBOutputStream extends OutputStream`

### Thread Safety Model

- `bufferLock` object — synchronizes all deque access
- `volatile` fields — `streamClosed`, `safeWrite`, `availableBytes`, `positionAtCurrentBufferEntry`, `maxBufferElements`
- `Semaphore signalModification` — blocks reading threads until data is written or stream is closed (avoids busy-waiting)

### Key Behaviors

- **`positionAtCurrentBufferEntry`** — tracks read offset within the head byte array, enabling partial reads without copying
- **`safeWrite`** (default: `false`) — when `true`, clones input arrays on write to protect against external mutation
- **Buffer trimming** — when `Deque` size exceeds `maxBufferElements` (default: 100), all buffered data is consolidated into a single byte array; `isTrimShouldBeExecuted()` controls this
- **`available()`** returns `Integer.MAX_VALUE` when `availableBytes > Integer.MAX_VALUE`, supporting >2GB buffers

### Tests

`src/test/java/net/ladenthin/streambuffer/StreamBufferTest.java` uses JUnit 4 with `DataProviderRunner`. Most tests are parameterized across 3 write variants (`ByteArray`, `Int`, `ByteArrayWithParameter`) defined in `WriteMethod.java`.

## Javadoc Conventions

### HTML Entities

In Javadoc comments, never use bare Unicode characters for operators and symbols. Use HTML entities instead:

| Symbol | HTML entity |
|---|---|
| `<` | `&lt;` |
| `>` | `&gt;` |
| `≤` | `&#x2264;` |
| `≥` | `&#x2265;` |
| `→` | `&#x2192;` |
| `←` | `&#x2190;` |
| `≠` | `&#x2260;` |

Use numeric hex entities (`&#xNNNN;`) for any Unicode symbol outside ASCII. Named entities (`&lt;`, `&gt;`) are acceptable for `<` and `>`.
