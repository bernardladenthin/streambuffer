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

**Run JMH benchmarks:**

JMH benchmarks live in `src/test/java/net/ladenthin/streambuffer/benchmark/` (e.g. `StreamBufferThroughputBenchmark`). They are not executed by `mvn test`; invoke them directly via the `exec-maven-plugin` whose default `mainClass` is `org.openjdk.jmh.Main`:

```bash
# All benchmarks
mvn test-compile exec:java

# Filter by regex (class or method name)
mvn test-compile exec:java -Dexec.args="StreamBufferThroughput"

# Allocation profile (built-in, no extra setup)
mvn test-compile exec:java -Dexec.args="StreamBufferThroughput -prof gc"

# CPU profile via async-profiler (set ASYNC_PROFILER_LIB to libasyncProfiler.so)
mvn test-compile exec:java \
  -Dexec.args="StreamBufferThroughput -prof async:libPath=$ASYNC_PROFILER_LIB;output=flamegraph"
```

`-prof gc` reports `gc.alloc.rate.norm` (bytes allocated per op) — useful for spotting hidden allocations on the read/write hot paths. `-prof async` produces flamegraphs and requires async-profiler installed locally; CI does not run it.

`mvn test` also runs:
- **jqwik properties** (`StreamBufferProperties`) — picked up by Surefire as a JUnit 5 engine.
- **Lincheck** linearizability test (`StreamBufferLincheckTest`) over the non-blocking subset (`write`, `available`, `close`, `isClosed`).

**Opt-in jcstress concurrency stress tests:**
```bash
mvn -Pjcstress test
```
jcstress tests under `net.ladenthin.streambuffer.jcstress` live behind the `jcstress` profile. The profile binds `exec-maven-plugin` to the `test` phase to run the jcstress harness in a forked JVM (`-m default`). Off by default because the harness needs annotation-processor-generated test resources that are skipped by `-DskipTests` / `-Dmaven.test.skip=true` (would otherwise NPE) and because the run is slow.

**Opt-in vmlens interleaving analysis:**
```bash
mvn -Pvmlens test
```
The `vmlens` profile pulls in `com.vmlens:api` and runs the `vmlens-maven-plugin` during the `test` phase. Tests using `com.vmlens.api.AllInterleavings` are then driven through every possible thread interleaving. The profile is off by default — vmlens overhead is too high for every build.

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
- **Buffer trimming** — when `Deque` size exceeds `maxBufferElements` (default: 100), all buffered data is consolidated into a single byte array; `shouldTrim()` controls this
- **`available()`** returns `Integer.MAX_VALUE` when `availableBytes > Integer.MAX_VALUE`, supporting >2GB buffers

### Tests

`src/test/java/net/ladenthin/streambuffer/StreamBufferTest.java` uses JUnit 5 (Jupiter) with `@Nested` / `@DisplayName` grouping. Most tests are parameterized across 3 write variants (`ByteArray`, `Int`, `ByteArrayWithParameter`) defined in `WriteMethod.java` via `@ParameterizedTest` + `@EnumSource(WriteMethod.class)`.

## Javadoc Conventions

See [`../workspace/policies/javadoc-conventions.md`](../workspace/policies/javadoc-conventions.md).

## SpotBugs Suppressions

See [`../workspace/policies/spotbugs-suppressions.md`](../workspace/policies/spotbugs-suppressions.md).

## Spotless Formatting

See [`../workspace/policies/spotless-formatting.md`](../workspace/policies/spotless-formatting.md).
Run `mvn spotless:apply` before every commit that touches `.java` files.

## jqwik Policy

See [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md).

## JPMS Module Descriptor

This repo ships a `module-info.java` compiled in a separate `release 9` execution. Javadoc
currently runs in **classpath mode** (javadoc `<source>` resolves to `8`), which is the *only*
thing keeping it clear of the JPMS module-mode javadoc trap that bit BAF. **Before raising the
Java / javadoc source level to ≥ 9, read**
[`../workspace/policies/jpms-module-descriptor.md`](../workspace/policies/jpms-module-descriptor.md).

## Open TODOs

Open TODOs for this repo live in [`TODO.md`](TODO.md). Cross-repo status
tracking lives in [`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md).
