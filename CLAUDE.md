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

## jqwik Policy

See [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md).

## Open TODOs

- **jqwik pin policy** — see [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md). `jqwik.version ≤ 1.9.3` is mandatory.

- **`@VisibleForTesting` audit.** No usages currently. Walk the production tree for package-private/protected methods or fields that exist purely so tests can reach them, and either annotate (`com.google.common.annotations.VisibleForTesting`) or move into the test source tree.
- **Null-safety refinement.** JSpecify + NullAway are enforced at compile time in **strict JSpecify mode** with the following extra options: `CheckOptionalEmptiness`, `AcknowledgeRestrictiveAnnotations`, `AcknowledgeAndroidRecent`, `AssertsEnabled` (see `pom.xml`). The package carries an explicit `@NullMarked` via `package-info.java`. The production code currently has no `@Nullable` markers because every value is non-null by construction (constructors reject `null`, no `return null` sites). Open follow-up: as new public API surfaces are added, evaluate whether `@Nullable` or `Optional<T>` would be more precise than the implicit non-null default.

- **Further-strictness open points (cross-repo, not yet done).** Items below are tracked across all four Bernard-Ladenthin Java repos and can be picked up incrementally:
  - **SpotBugs `effort=Max` + `threshold=Low`** — currently default effort/threshold. Raising both surfaces more findings (and takes longer per build). Worth a one-off experiment to triage what appears before committing.
  - ~~**Error Prone bug-pattern promotions to `ERROR`** — Error Prone is already running and emits warnings during compile (`NotJavadoc`, `JdkObsolete`, `NonAtomicVolatileUpdate`, `InvalidThrows`, `MissingOverride`, `FutureReturnValueIgnored`, `EqualsGetClass`, `ReferenceEquality`, etc.). Promote the high-confidence, zero-noise-today patterns to `ERROR` via per-`-Xep:<Name>:ERROR` args.~~ **DONE for this repo** (commit `ad95d66` — Promote 12 Error Prone bug patterns to ERROR + enable -Xlint:all). Cross-repo work remains for the other three repos.
  - **`javac -Werror` + `-Xlint:all,-serial,-options`** — **DONE for this repo** (`-Werror` is on with `-Xlint:all,-serial,-options,-classfile,-processing`; commit `7a4fbf0` — Turn on javac -Werror). The ElementType.MODULE blocker is resolved by the module-level `@NullMarked` move; the remaining excluded categories are documented inline in `pom.xml`. Cross-repo: same fix applies to `llamacpp-ai-index-maven-plugin` and `java-llama.cpp`; `BitcoinAddressFinder` has 7 catalogued non-MODULE warnings to address before flipping the switch there.
  - ~~**`-parameters` javac arg** — bakes real parameter names into bytecode (visible via reflection, Jackson, OpenAPI). Useful even where reflection isn't used today.~~ **DONE for this repo** (commit `912f14b` — Trivial strictness bundle: -parameters, --release, OnlyNullMarked). Cross-repo work remains for the other three repos.
  - ~~**`--release N`** instead of `-source N -target N` — forces the API surface to actually match the target JDK; prevents accidental use of post-N JDK APIs.~~ **DONE for this repo** (commit `912f14b` — Trivial strictness bundle: -parameters, --release, OnlyNullMarked). Cross-repo work remains for the other three repos.
  - **Mutation-testing threshold enforcement (PIT)** — only `streambuffer` currently enforces 100 % mutation coverage. **Deferred for the other three repos** (`llamacpp-ai-index-maven-plugin`, `java-llama.cpp`, `BitcoinAddressFinder`); not introducing PIT thresholds there now because the ROI on the current goal set is low. Revisit when a specific repo accumulates enough hand-written code to justify the per-build cost (PIT runs are minutes long) and the threshold-bookkeeping overhead. The PIT plugin itself remains available in each pom; only the threshold gate is left off.
  - ~~**Checker Framework as a second static-nullness pass** — none of the four repos use it today. Heavier than NullAway, but generics-aware and whole-program. Worth adding *alongside* NullAway (not as a replacement) once NullAway stops surfacing new findings.~~ **DONE for this repo** (commit `5a9be1b` — Add Checker Framework Nullness Checker as a 2nd nullness-analysis pass). Cross-repo work remains for the other three repos.
  - **JPMS `module-info.java` with `@NullMarked` at module level** — **DONE for this repo**; remaining cross-repo work covers the other three. This repo's `module-info.java` exports `net.ladenthin.streambuffer` and uses the two-execution `maven-compiler-plugin` pattern (release 8 for sources, release 9 for `module-info.java`); the resulting jar carries `module-info.class` at its root and is backward-compatible with Java 8 classpath consumers (they silently ignore the descriptor). Module-level `@NullMarked` was intentionally NOT added — the per-package `package-info.java` annotation already covers the same nullness scope and avoids pulling JSpecify into the module descriptor's `requires` graph.
  - ~~**Banned-API enforcement** — add Maven Enforcer `bannedDependencies` / `dependencyConvergence` rules and a `banned-api-checker`-style rule for things like `Thread.sleep` in production, `System.exit`, etc.~~ **DONE for this repo**: Maven Enforcer with `bannedDependencies` / `dependencyConvergence` landed in commit `c0148c8` (Add Maven Enforcer with the four standard rules); the `Thread.sleep` / `System.exit` / `new Random` "banned-API" piece is enforced via ArchUnit rules in commit `eaf4337` (test(archunit): ban System.exit, new Random, Thread.sleep in production). Cross-repo work remains.
  - ~~**Additional ArchUnit rules to consider** — layered-architecture rules (`layeredArchitecture().consideringAllDependencies()`), per-module banned-imports lists, public-API-surface constraints (no public mutable static state, no public field that is not final, etc.).~~ **DONE for this repo** for the public-field-must-be-final rule (commit `5dd816d` — test(archunit): public non-static fields must be final) and the internal-JDK banned-imports rule (commit `de29bd4` — test(archunit): forbid sun.* / com.sun.* / jdk.internal.* imports in production). The `layeredArchitecture` rule is not applicable: this module is a single-package library. Cross-repo work remains.
- **No LogCaptor smoke test needed** — this module has no logging code (`org.slf4j.*` not used in `src/main/java/`). If logging is ever introduced, add a LogCaptor smoke test at the same time so the binding/configuration is exercised in tests.

- **Cross-repo code-quality TODOs** — see [`../workspace/policies/code-quality-todos.md`](../workspace/policies/code-quality-todos.md) for the canonical `@VisibleForTesting` design-fit review, package hierarchy review, and class/method naming review. This module is single-package and has no `@VisibleForTesting` usages; the package and naming reviews remain open.

- ~~**Abstract the Java and test writing guidelines to a workspace-level shared layer.**~~ **DONE.** This repo is Java 8 (production sources); follow the workspace version chain at [`../workspace/guides/src/CODE_WRITING_GUIDE-8.md`](../workspace/guides/src/CODE_WRITING_GUIDE-8.md) and [`../workspace/guides/test/TEST_WRITING_GUIDE-8.md`](../workspace/guides/test/TEST_WRITING_GUIDE-8.md). Canonical TDD skill at [`../workspace/.claude/skills/java-tdd-guide/SKILL.md`](../workspace/.claude/skills/java-tdd-guide/SKILL.md). This repo has no project-specific writing-guide supplements (production code is a single class).

- ~~**Adopt a standard `CLAUDE.md` template/tool for cross-repo consistency.**~~ **DONE.** Template at [`../workspace/templates/CLAUDE.md.template`](../workspace/templates/CLAUDE.md.template).
