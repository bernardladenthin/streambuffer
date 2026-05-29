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
- **jcstress** tests under `net.ladenthin.streambuffer.jcstress` — executed in a forked JVM via `exec-maven-plugin` in the `test` phase (`-m quick` mode).
- **Lincheck** linearizability test (`StreamBufferLincheckTest`) over the non-blocking subset (`write`, `available`, `close`, `isClosed`).

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
- **Buffer trimming** — when `Deque` size exceeds `maxBufferElements` (default: 100), all buffered data is consolidated into a single byte array; `isTrimShouldBeExecuted()` controls this
- **`available()`** returns `Integer.MAX_VALUE` when `availableBytes > Integer.MAX_VALUE`, supporting >2GB buffers

### Tests

`src/test/java/net/ladenthin/streambuffer/StreamBufferTest.java` uses JUnit 5 (Jupiter) with `@Nested` / `@DisplayName` grouping. Most tests are parameterized across 3 write variants (`ByteArray`, `Int`, `ByteArrayWithParameter`) defined in `WriteMethod.java` via `@ParameterizedTest` + `@EnumSource(WriteMethod.class)`.

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

## SpotBugs Suppressions

`spotbugs-exclude.xml` at the repo root contains documented suppressions for findings that are by-design or false positives. **When refactoring or renaming code referenced in that file, re-check the affected `<Match>` blocks:**

- `<Class>`, `<Method>`, and `<Field>` filters use exact string matches — a rename silently disables the suppression and may either un-suppress a real bug or leave a stale entry behind.
- After refactors, run `mvn -B -ntp -DskipTests -Dgpg.skip=true verify` and confirm the BugInstance count is unchanged. A drop means a suppression is now stale and should be deleted; an increase means a new finding needs its own decision (fix vs. suppress).
- Keep the rationale comment on each `<Match>` accurate — if the original justification no longer applies to the post-refactor code, remove the suppression rather than leave outdated reasoning in place.
- Never use `--` inside `<!-- ... -->` comment bodies in `spotbugs-exclude.xml` — XML forbids it and the entire filter file silently stops loading (every previously suppressed finding reappears).

## Open TODOs

- **`@VisibleForTesting` audit.** No usages currently. Walk the production tree for package-private/protected methods or fields that exist purely so tests can reach them, and either annotate (`com.google.common.annotations.VisibleForTesting`) or move into the test source tree.
- **JSpecify null-safety annotations.** NullAway / Error Prone is already wired into the build, but the production code carries no `@Nullable` / `@NonNull` annotations (treated as non-null by default). Review whether any public API surface would benefit from explicit `@Nullable` markers (JSpecify `org.jspecify:jspecify`) for nullable return types or parameters.
- **No LogCaptor smoke test needed** — this module has no logging code (`org.slf4j.*` not used in `src/main/java/`). If logging is ever introduced, add a LogCaptor smoke test at the same time so the binding/configuration is exercised in tests.

- **`@VisibleForTesting` design-fit review.** Complement to the audit above: for every existing or planned `@VisibleForTesting` usage, ask whether widening access is the cleanest path to testability. Common alternatives that should be preferred when applicable: (a) inject the dependency through the constructor and have the test pass a stub or fake; (b) extract the tested behaviour into a separate testable helper class with public methods; (c) restructure the production API so what the test wants to verify is observable through normal public methods. Only keep the annotation where these alternatives are materially worse. `@VisibleForTesting` should be the last resort, not the first.

- **Package hierarchy review.** Walk the full `src/main/java/.../` tree and assess whether the current package layout still expresses the design intent. Look for: classes that have drifted into the wrong package as the codebase grew; flat "kitchen-sink" packages that should be split (high class count, mixed concerns); deeply nested packages that fragment cohesive components; circular dependencies between packages; missing seams where a sub-package boundary would prevent leaking implementation details. Produce a target tree as a separate planning step BEFORE making any moves — large package refactors are expensive to review and easy to do twice if the target isn't clear up front.

- **Class and method naming review (pair with the package hierarchy work).** While the package hierarchy review is in flight, also audit class and method names for the same kinds of drift: stale names that no longer describe what the class actually does after years of growth; over-abbreviated or cryptic identifiers (`Utils`, `Helper`, `Mgr`, `do*`, `process*`) that hide responsibilities; method names whose verbs do not match the actual side effects (named `get*` but writes, named `is*` but mutates, etc.); name collisions across packages that force qualified imports everywhere. Renames are far cheaper to do INSIDE a package-restructure commit than as standalone follow-ups (one IDE refactor pass touches both the move and the rename), so capture name changes in the same target tree as the package plan rather than as a separate later step.
