# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
mvn compile          # Compile
mvn test             # Run all tests with coverage
mvn package          # Build JAR
mvn install -Dgpg.skip=true  # Install to local repo without GPG signing
```

`mvn verify` also runs the **API compatibility gate** (japicmp, `japicmp.baseline.version` in `pom.xml` =
the last release on Maven Central): it fails when the version step is too small for the change under
semantic versioning (a removed or changed public member needs a new major version). The report is in
`target/japicmp/`. Raise the baseline after every release (`docs/RELEASE.md`).

**Run a single test:**
```bash
mvn test -Dtest=StreamBufferTest#testSimpleRoundTrip
```

**Run mutation tests** (the `test-compile` prefix is required — see the
[PIT policy](../workspace/policies/pit-mutation-testing.md)):
```bash
mvn test-compile org.pitest:pitest-maven:mutationCoverage
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

`mvn test` also runs `StreamBufferVirtualThreadsTest` (64 virtual readers, 4 virtual writers; a JFR
`jdk.VirtualThreadPinned` check that requires no pinning inside `StreamBuffer` on JDK 24+ and only
reports on 21-23, see the `virtual-threads-jdk21` job) and the Lincheck tests (`StreamBufferLincheckTest`,
`StreamBufferTrimLincheckTest` with `maxBufferElements` 2; reads in one `nonParallelGroup`).
The contended JMH benchmark `StreamBufferContendedBenchmark` (platform vs virtual threads, 1/4 writers
and readers) is a report, the baseline for roadmap A8.

`mvn test` also runs:
- **jqwik properties** (`StreamBufferProperties`) — a JUnit Platform engine; Surefire runs the class
  only because `pom.xml` adds `**/*Properties.java` to its include patterns (until 2026-10-19 it ran
  in no build, since the name matches none of Surefire's defaults). Under `-Pjml-rac` they run with
  100 tries instead of 1000 (`jqwik.tries.default`).
- **Lincheck** linearizability test (`StreamBufferLincheckTest`) over the non-blocking subset (`write`, `available`, `close`, `isClosed`).

**Opt-in jcstress concurrency stress tests:**
```bash
mvn -Pjcstress test
```
jcstress tests under `net.ladenthin.streambuffer.jcstress` live behind the `jcstress` profile. The profile binds `exec-maven-plugin` to the `test` phase to run the jcstress harness in a forked JVM (`-m default`). Off by default because the harness needs annotation-processor-generated test resources that are skipped by `-DskipTests` / `-Dmaven.test.skip=true` (would otherwise NPE) and because the run is slow. The mode is `jcstress.mode`: `quick` by default (every pull request's Test job), `default` in the scheduled `jcstress-default` job and the dispatch-only `arm64-jcstress-benchmark` job of `formal-verification.yml` (`-Djcstress.mode=default` locally).

**Opt-in vmlens interleaving analysis:**
```bash
mvn -Pvmlens test
```
The `vmlens` profile pulls in `com.vmlens:api` and runs the `vmlens-maven-plugin` during the `test` phase. Tests using `com.vmlens.api.AllInterleavings` are then driven through every possible thread interleaving. The profile is off by default — vmlens overhead is too high for every build. The plugin **fails the build on any data race** (`There are N data races`), which makes the `vmlens` job the race gate of the data-race-freedom argument (README). The profile sets `jacoco.skip`: JaCoCo's unsynchronized coverage arrays made two threads in the same method look like a race. Restrict a local run with `-Dtest=...`.

## Formal Verification

Two layers, run in a **separate** CI pipeline (`.github/workflows/formal-verification.yml` —
deliberately not part of the synchronous Publish pipeline and never a required check):

1. **OpenJML ESC** (deductive proof): the 15 static sequential-core methods (2 validators +
   13 pure helpers) are proven against full functional contracts, **twice**: with Z3 and again with
   cvc5 (both bundled with OpenJML), so no proof rests on one solver. Yices2, also bundled, fails
   every obligation with `ERROR` and is not used. Local: `--prover=cvc5`.
2. **OpenJML RAC**: the existing JUnit suite runs against RAC-instrumented classes
   (violations throw), checking the static contracts plus the instance/stream-adapter contracts.
3. **JPF interleavings** (`src/test/jpf/`, scheduled/dispatch CI job `jpf-interleavings`): Java
   PathFinder exhaustively model-checks the concurrent read/write/close protocol with six harnesses:
   `StreamBuffer.jpf` (a writer that closes after its writes, a reader), `WriteClose.jpf` (writer,
   closer and reader in three threads -- the order of write and close, which the first cannot see;
   red before bug-hunt fix F149), `TwoReaders.jpf` (a writer that closes, two readers on one
   stream; red before bug-hunt fix F278) and `RecordReaders.jpf` (two readers of 2-byte records written
   fragmented across the record boundary; red before `read(b, off, len)` took its bytes in one step),
   `WaitAndRead.jpf` (a `waitForAtLeast(2)` caller next to a reader; red before F278) and
   `TrimReentrancy.jpf` (a trim start signal writing from inside the trim, a reader).
   Requires JDK 11; builds jpf-core from a pinned commit with a
   one-file `AtomicLong` model patch; the harnesses are compiled at `--release 8` and run under JPF. Local recipe (Docker+JDK 11) in
   `src/test/jpf/README.md`. Never touches the shipped jar.

4. **TLA+ model** (`src/test/tla/`, scheduled/dispatch CI job `tla-model`): `StreamBuffer.tla` models
   the wait/wake-up/close protocol and the reads; TLC checks safety and liveness. `check.sh` compares
   ten models with their expected outcomes: the current code checks clean (`read()` with 1, 2, 3
   readers, `read(b, 0, 2)` records with 2), the older code fails with its counterexamples (F278: an
   empty take, a deadlock after the close; #212: a torn record; F279: a count from the middle of a
   read). Constants `Protocol`, `ReCheck`, `AtomicRead`, `CountOnce` select the code version. `tla2tools.jar` v1.7.4 is
   pinned by SHA-256. When the wait/signal code changes, change the model with it.

The `@GuardedBy("bufferLock")` lock discipline is gated separately by Error Prone in the default
build. The Checker Framework Lock Checker was evaluated as a further layer and deferred — see
TODO.md "Formal verification".

**Local commands** (OpenJML 21.0.29, pinned in the workflow; native Windows builds exist since 21.0.27;
`<openjml>` = unzipped release dir, `<cp>` = output of
`mvn dependency:build-classpath -Dmdep.outputFile=... -DincludeScope=compile`):

```bash
# ESC — the --method list is the verified scope; it is mirrored in ESC_METHODS in the workflow
<openjml>/openjml --esc --progress --timeout 300 --spec-math=bigint \
  --class-path "<cp>" --specs-path src/main/jml \
  --method "<ESC_METHODS from the workflow>" \
  src/main/java/net/ladenthin/streambuffer/StreamBuffer.java

# RAC — compile instrumented classes (Java math both sides), then run the suite against them.
# The suite MUST fork OpenJML's own JVM (it carries the org.jmlspecs bigint runtime class that
# the bundled JDK specs reference); the profile does this via -Dopenjml.jdk.java.
<openjml>/openjml --rac --code-math=java --spec-math=java --class-path "<cp>" \
  --specs-path src/main/jml -d target/rac-classes \
  src/main/java/net/ladenthin/streambuffer/StreamBuffer.java
mvn -P jml-rac -Dopenjml.home=<openjml> -Dopenjml.jdk.java=<openjml>/jdk/bin/java test
```

**Rules that keep this sound — read before touching `StreamBuffer.java` or the specs:**

- Specs live ONLY in `src/main/jml/net/ladenthin/streambuffer/StreamBuffer.jml`. A `.jml` file
  **replaces** all class-level JML in the `.java` (which therefore stays JML-free), and OpenJML
  errors on any signature mismatch — so every signature change in `StreamBuffer.java` must be
  mirrored there, and the verification workflow catches drift.
- The 13 pure helpers are `static` **because instance-method proof obligations are undecidable
  for Z3 in this class** (the non-static inner stream classes poison the receiver context —
  measured, not theorized). New pure helpers must be static or they cannot join the ESC scope.
- The ESC scope is guarded by an exact proof COUNT in the workflow (`ESC_EXPECTED_PROOFS`);
  adding/removing a method from the scope means updating `ESC_METHODS` + the count together.
- `validateOffsetAndLengthToWrite` and `calculateResultingChunks` are marked `code_java_math`
  in the spec file: both deliberately rely on wrap semantics (overflow-guard idiom; wrap-back
  at the ceiling-division boundary). Everything else is proven overflow-free under safe math.
- The exception-message builder `newInvalidOffsetOrLengthToWriteException` carries an ASSUMED
  (unproven) contract — string concatenation defeats the SMT encoding. Do not inline it back.
- Four class invariants live in the `.jml` (`0 <= availableBytes`, `0 <= positionAtCurrentBufferEntry`,
  `1 <= maxAllocationSize`, `0 <= maxObservedBytes`), checked by RAC. They depend on the **qualified**
  delegating calls in `SBInputStream`/`SBOutputStream` (`StreamBuffer.this.writeSingleByte(b)`): for an
  unqualified call from an inner class, OpenJML RAC (21.0.29) checks the callee's invariant on the inner
  object (`NoSuchMethodError` on `SBOutputStream.JML$INV$$<n>()`, OpenJML/OpenJML#1012). Do not drop
  the qualifier. A false invariant fails the suite (negative control 2026-11-11: 14/14 errors).
- RAC contracts reference only `\result`, parameters and **monotone** state: `isClosed()` (stays true),
  `getAvailableBytesExact()` after the close (can only fall), `getTotalBytesWritten()`/`getTotalBytesRead()`
  (only grow). Anything else can change between the method body and the postcondition check under
  concurrency and would fail spuriously. Exception clauses name `Exception` and test `instanceof`, since
  a clause for a narrower type is evaluated with an unguarded cast for every exception
  (OpenJML/OpenJML#1050).
- The read/write contracts sit on the private outer methods (`readSingleByte`, `readIntoArray`, the
  four-argument `writeFromArray`), declared in the `.jml`; every stream call goes through them.
- `//@ nullable_by_default` at the class head is load-bearing for RAC: without it JML's
  non-null-by-default inserts an implicit non-null precondition on every reference parameter, so
  the null-argument tests hit `JmlAssertionError.Precondition` instead of the specified NPE.
  Non-null intent is still enforced where it matters via explicit `requires ... != null`.
- `validateOffsetAndLengthToWrite` uses a manual `if (b == null) throw new NPE(...)` rather than
  `Objects.requireNonNull`: under `nullable_by_default` the bundled `Objects.requireNonNull`
  contract leaves ESC an unprovable ExceptionList goal. Behaviour is identical.
- The stream logic lives in `private` OUTER methods (`availableClamped`, `readSingleByte`,
  `readIntoArray`, `writeSingleByte`, `writeFromArray`); the inner `SBInputStream`/
  `SBOutputStream` are pure delegating shells. Required: OpenJML RAC miscompiles outer-field
  access from inside non-static inner classes (`NoSuchFieldError` at runtime). Do not move field
  access back into the inner classes.
- RAC forks OpenJML's OWN JVM (`-Dopenjml.jdk.java`), because the bundled JDK library specs pull
  in `org.jmlspecs.lang.internal.bigint`, a class present only in OpenJML's patched JDK image.
  The setup action also patches `jdk/release` to add the `JAVA_VERSION` key surefire needs to
  fork that JVM (missing in 21.0.27/21.0.28, present again in 21.0.29; the guarded step is a no-op
  there and stays as a regression guard).
- No bundled OpenJML JDK spec is deleted at install any more (fixups v3). Up to 21.0.28 two were
  broken under RAC and deleted by `.github/actions/setup-openjml`: `ArrayDeque.jml` (undeclared
  `containsNull`, fixed via [OpenJML/OpenJML#1012](https://github.com/OpenJML/OpenJML/issues/1012))
  and `atomic/AtomicLong.jml` (RAC read the private field `value` → `IllegalAccessError`, fixed by
  [OpenJML/Specs#29](https://github.com/OpenJML/Specs/pull/29) +
  [OpenJML/OpenJML#982](https://github.com/OpenJML/OpenJML/pull/982)). Both fixes are in 21.0.29;
  the suite passes against the unmodified distribution (285/285).
- Under `-Pjml-rac` the stress loops of `StreamBufferTest` and the jqwik tries are scaled down
  (`streambuffer.test.rac`, `jqwik.tries.default` 100): RAC prints a ~10 KB stack trace for every
  `System.arraycopy`/`clone` (an uncompiled model method of the bundled JDK spec,
  [OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050)), and unscaled the job ran
  into its timeout with every contract holding. Do not remove the scaling before a release fixes it.
- RAC classes are class-file 65 and live only under `target/rac-classes` — they never enter the
  shipped jar, so the Java 8 bytecode floor is unaffected.

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
- `ReentrantLock waitLock` + `Condition modified` — a reader waits on `modified` until data is written or
  the stream is closed; every write and the close `signalAll()` (bug-hunt finding F278: a semaphore with
  at most one permit woke one of several readers). A waiter never holds `bufferLock`, and every read
  checks `availableBytes` again under `bufferLock` after the wait, so several readers are safe. The
  external `addSignal` semaphores keep the max-1-permit pattern. `AtomicInteger waitingReaders` lets a
  write skip `waitLock` while no reader waits (volatile order: the writer stores `availableBytes` before
  it reads the count, a waiter increments it before it reads `availableBytes`); `waitForAtLeast` returns
  without the lock when enough bytes are buffered or the stream is closed.
- **Data-race freedom** (README "Data-Race Freedom"): every shared field is final, volatile, atomic or
  lock-guarded (the table there), and the vmlens job fails the build on any race it finds, so the
  interleaving-based results hold under the JMM (JLS §17.4.5). A new field goes into that table; a new
  concurrent scenario goes into `vmlens/StreamBufferSeveralReadersInterleavingTest`.
- Several writers and several readers are supported: each write is atomic, each byte reaches exactly one
  reader in FIFO order, no fairness. `read(b, off, len)` is atomic too: it waits until `len` bytes are
  buffered (or closed) and takes them in one `bufferLock` hold, so readers of a fixed record size get
  whole records (work queue / competing consumers, README). `StreamBufferConcurrentReadersTest` holds
  all of that, including 1429-byte records with CRC32.

### Key Behaviors

- **`positionAtCurrentBufferEntry`** — tracks read offset within the head byte array, enabling partial reads without copying
- **`safeWrite`** (default: `false`) — when `true`, clones input arrays on write to protect against external mutation
- **Buffer trimming** — when `Deque` size exceeds `maxBufferElements` (default: 100), all buffered data is consolidated into a single byte array; `shouldTrim()` controls this
- **`available()`** returns `Integer.MAX_VALUE` when `availableBytes > Integer.MAX_VALUE`, supporting >2GB buffers

### Tests

`src/test/java/net/ladenthin/streambuffer/StreamBufferTest.java` uses JUnit 6 (Jupiter) with `@Nested` / `@DisplayName` grouping. Most tests are parameterized across 3 write variants (`ByteArray`, `Int`, `ByteArrayWithParameter`) defined in `WriteMethod.java` via `@ParameterizedTest` + `@EnumSource(WriteMethod.class)`.

## Javadoc Conventions

See [`../workspace/policies/javadoc-conventions.md`](../workspace/policies/javadoc-conventions.md).

## SpotBugs Suppressions

See [`../workspace/policies/spotbugs-suppressions.md`](../workspace/policies/spotbugs-suppressions.md).

## Spotless Formatting

See [`../workspace/policies/spotless-formatting.md`](../workspace/policies/spotless-formatting.md).
Run `mvn spotless:apply` before every commit that touches `.java` files.

## jqwik Policy

See [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md).

## CI Test Diagnostics

See [`../workspace/policies/ci-test-diagnostics.md`](../workspace/policies/ci-test-diagnostics.md).

## PIT Mutation Testing

See [`../workspace/policies/pit-mutation-testing.md`](../workspace/policies/pit-mutation-testing.md).
Run PIT with the lifecycle prefix — `mvn test-compile org.pitest:pitest-maven:mutationCoverage`.

## Java 8 bytecode floor — what may ship

This artifact targets **Java 8**, so **every class a consumer's JVM can load must be class-file
major 52 or lower**. `maven.compiler.release` governs only the code *we* compile; a dependency
built for a newer Java lands in the jar untouched and surfaces as `UnsupportedClassVersionError`
on a consumer's JVM. This repo is the least exposed of the four siblings — it has no logger and
its deliverable is the plain library jar, not a fat jar — but it runs the same gate so a future
dependency cannot change that quietly.

**The gate: the `java/verify-bytecode` action of [bernardladenthin/actions](https://github.com/bernardladenthin/actions)** (its `verify-bytecode-version.sh`).
It opens every `.class` in every jar it is given and fails on any whose class-file major version
exceeds `max-major`:

```yaml
- uses: bernardladenthin/actions/java/verify-bytecode@<commit> # v1.x.y
  with:
    max-major: "52"
    paths: |          # jars or directories, one per line
      jars
    allow: |          # optional: '<jar-basename>:<entry-path>' globs to tolerate
```

Paths may be jars or directories (searched recursively for `*.jar`). `module-info.class` and
`META-INF/versions/**` are skipped unconditionally: a classpath JVM never loads either, which is
why the `release 9` `module-info` here is fine. `--allow` is a repeatable glob matched against
`<jar-basename>:<entry-path>` for anything else that must be tolerated (`allow`). Exit codes: 0 clean,
1 violations, **2 nothing to scan** (an empty input is a failure, never a pass). Wired into the
`smoke-jar` job, ahead of the smoke test itself.

## JPMS Module Descriptor

This repo ships a `module-info.java` compiled in a separate `release 9` execution. Javadoc
currently runs in **classpath mode** (javadoc `<source>` resolves to `8`), which is the *only*
thing keeping it clear of the JPMS module-mode javadoc trap that bit BAF. **Before raising the
Java / javadoc source level to ≥ 9, read**
[`../workspace/policies/jpms-module-descriptor.md`](../workspace/policies/jpms-module-descriptor.md).

## Dependency Convergence Pinning

`dependencyConvergence` is enabled (maven-enforcer). This repo has no parent POM, so its
`dependencyManagement` block (pinning `jspecify`/`hamcrest`) is the repo's only convergence
backstop — added because it previously had none. Convention + the `excludedScopes=[test,provided]`
enforcer default gotcha are in
[`../workspace/policies/dependency-convergence-pinning.md`](../workspace/policies/dependency-convergence-pinning.md).

## Release assets

The thin jar, its sources and javadoc jars and the pom are attached to the GitHub `snapshot`
pre-release and to every versioned release with the `.asc` maven-gpg wrote at deploy; no fat jar
exists here. Every publication goes through the one gate of [bernardladenthin/actions](https://github.com/bernardladenthin/actions) (full text: [docs/publication.md](https://github.com/bernardladenthin/actions/blob/main/docs/publication.md)).
`check-snapshot` / `check-tag` run `java/check-release-ref`: a release publishes only from the tag
`v<version>` of a non-SNAPSHOT version, a snapshot only a `-SNAPSHOT` version and never from a tag.
The publish jobs stage and sign the Central files locally (`-DskipUpload=true deploy`) and end in
`java/finalize-publication`, which collects what `.github/release-assets.json` names (Maven modules
are discovered from the POMs), checks it -- exact membership, every signature with `gpg --verify`,
each Central file byte-equal to its GitHub twin -- and freezes it into one package. Only after that
package is uploaded does the job output `assets_complete=true`; a missing file or signature fails
there, and nothing is published. Three pairs of consumers each need only that output, never each
other: `github-snapshot` / `github-release` (`java/publish-github`: the rolling `snapshot`
pre-release is serialized, never lets an older commit or run replace a newer one, prunes only after a
complete upload and starts as a draft; a versioned tag is refused), `central-snapshot` /
`central-release` (`java/publish-central`, no rebuild, no re-signing) and `attest-snapshot` /
`attest-release` (`java/attest-publication`). The jobs themselves stay in this workflow
(environment, permissions, concurrency); `java/check-publication` checks their wiring in every pull
request.

## Shared CI: bernardladenthin/actions (`repository-checks` job)

The CI code the four Java repositories (java-llama.cpp, BitcoinAddressFinder, srcmorph,
streambuffer) share lives once in [bernardladenthin/actions](https://github.com/bernardladenthin/actions): composite actions for single steps (`uses:
bernardladenthin/actions/<common|java>/<action>@<commit> # v1.x.y`), reusable workflows for whole
jobs (CodeQL, Maven dependency submission, REUSE, OSV-Scanner, SonarQube -- the workflow files here
only name the triggers), and templates for the files this repository has to carry itself.
Dependabot moves the pins with every release of that repository. Until 2026-10 the same code was
four byte-identical copies held together by a `.github/shared-files.sha256` manifest per repository.

The `repository-checks` job of `publish.yml` (gating both publish jobs) runs its checks, configured
in **`.github/actions-config.json`**:

- **templates**: every file this repository keeps equal to a template there (community files,
  licenses, `.editorconfig`, `.gitattributes`, `.java-version`, `.mvn/`, Dependabot, the workflow
  callers, `scorecard.yml`, the Claude workflows) still equals it, up to the repository's name and
  the action pins. To change one, change the template in bernardladenthin/actions; `python3 -m
  actionlib.common.templates --write` (with its `lib/` on `PYTHONPATH`) writes it here;
- **release gate**: every job gates both publish jobs unless `.github/release-gate-exemptions.txt`
  names it with a reason;
- **run scripts**: `bash -n` over every bash `run:` script of the workflows and local actions, so a
  broken script (a lost line continuation, say) fails here instead of in the job running it;
- **artifact timeouts**: every `upload-artifact` / `download-artifact` step times out after the
  repository variable `ARTIFACT_TIMEOUT_MINUTES`, else 20 minutes (the workflow's top-level `env`
  reads it; [`../workspace/policies/ci-artifact-timeouts.md`](../workspace/policies/ci-artifact-timeouts.md)),
  instead of GitHub's 360;
- **Dependabot**: every entry of `.github/dependabot.yml` (the template's) runs weekly on
  Saturday and has a group -- minor and patch updates as one pull request per ecosystem, a
  major update as one of its own;
- **Maven versions** (warnings only): a dependency or plugin (incl. the Spotless formatter version)
  used here in another version than in a sibling of the `java-maven` family (each sibling's POMs come
  from its own configuration), and Kotlin Gradle plugins behind the POMs' Kotlin;
- **publication**: the publication jobs are wired as the actions expect, and a dry run of
  `.github/release-assets.json` against the real POMs collects exactly what it promises.

**Dependabot pull requests do not run `publish.yml`**: its `startgate` job, which every other
job needs, is skipped for a pull request Dependabot opens or rebases (`github.actor`). The merge
to `main` runs the pipeline; a push of a person to the branch, or a dispatch on it, runs it too.

The JDK every workflow uses is `.java-version` (setup-java's `java-version-file`), a template of
the `java` set. Why a repository instead of copies:
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md).

## Open TODOs

Open TODOs for this repo live in [`TODO.md`](TODO.md). Cross-repo status
tracking lives in [`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md).
