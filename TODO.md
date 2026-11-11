# TODO — streambuffer

Open work items for this repo. Cross-cutting tracking lives in
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md);
items here are streambuffer-specific or are this repo's slice of a
cross-cutting initiative.

**Completed work is not recorded here.** It lives in git history and in
`crossrepostatus.md`; a finished item is deleted from this file rather than
annotated, so everything below is genuinely still open.

## Open

- **Verification roadmap 2026-11 — packages A1–A13.** Each package is closed on its own, ends in a
  machine-checked result and is listed with its acceptance criterion. Order: A1 and A2 first (A1
  fixes a defect, without it every later proof proves the wrong contract), then A3 + A4, A5, A6 +
  A7; A10–A12 at any time; A8 only after the A1 decision and with the A7 numbers; A13 and A9 are
  long-term. A3, A5, A6 and A7 also build infrastructure that a later memory-model project can
  reuse (jcstress on several architectures, formal tools pinned in CI, checking real executions
  against a formal model) — so pinned tool setups belong in a composite action of
  bernardladenthin/actions rather than in this workflow.

  - **A1 — Concurrent readers: defect, decision, minimal fix (1–2 days).** Every concurrency check
    today (both JPF harnesses, jcstress, vmlens, Lincheck) has exactly **one** reader. With two
    readers on the same `InputStream` there are three defects, measured 2026-11-10 on JDK 21.0.12
    against unchanged `main` (`7ce9033`):

    | Scenario | Result |
    |---|---|
    | two readers parked in `read()`, then two single-byte writes back to back | 96/100 runs (98/100 in a first run): one reader stays blocked although 1 byte is buffered, until the next write or close |
    | two readers parked in `read()`, then `close()` | **100/100** runs: one reader blocks **forever** (no write can follow a close) |
    | 1 byte buffered, two readers call `read()` at the same time (`CyclicBarrier`), 3000 runs | 5 runs: `read()` throws an unchecked `NoSuchElementException` from `ArrayDeque.getFirst()` |

    Causes: (1) the max-1-permit pattern — `signalModification()` releases only when the semaphore
    has 0 permits, so two writes before the first wake-up leave one permit for two waiters, and
    `close()` releases one permit that the first woken reader consumes; (2) check outside the lock,
    act inside it — `waitForAtLeast` reads `availableBytes` without `bufferLock`, then
    `readSingleByte`/`readIntoArray` call `buffer.getFirst()` under the lock without re-checking.
    Correct for a single consumer, not for two. For `readIntoArray` the same race inside the copy
    loop, after partial copies were already accounted, is plausible (bytes lost plus exception) —
    **not measured**. Contract today: only the Javadoc of `waitForAtLeast` says "single reader
    thread"; `getInputStream()` and README "Thread Safety" ("blocks reading threads", "can be used
    concurrently from different threads") do not. `BUGHUNT-CHECKED.md` (`95bac9a`, "no lost wakeup")
    covered one reader. Reproduction: start two daemon reader threads, spin until both are
    `Thread.State.WAITING`, then `close()` (or `write(1); write(2);`), then
    `CountDownLatch.await(100 ms)` for both — false today. A probe that re-releases the internal
    semaphore whenever `waitForAtLeast` leaves its loop (data there or closed) brought scenarios 1
    and 2 to 0/100, not scenario 3 — that needs the re-check under the lock.
    **Decision needed:** support several readers safely, or document a single-consumer contract.
    Recommended: make it safe (no hang after `close()`, no unchecked exception from `read()`)
    without a fairness promise — `close()` wakes every waiter (re-release in the `streamClosed`
    branch; a surplus permit after close is harmless), and under the lock re-check the available
    bytes and go back to waiting instead of calling `getFirst()` on an empty deque. Record it as a
    new finding in `BUGHUNT-FOUND.md` (next free ID per that file's rule).
    Done when: the three scenarios are regression tests, red on `7ce9033` and green after the fix;
    PIT stays at 100 %; `-Pjml-rac` and both JPF harnesses green; the existing JMH benchmark shows
    no measurable loss.
  - **A2 — Documentation and small hardening (hours).** The `.jml` header (line 39) names a
    Checker Framework Lock Checker pass `mvn -P lockchecker compile`; no such profile exists (the
    Lock Checker is deferred, see below). The header cites DOI 10.1145/3594729 as "Formally
    Verifying an Efficient Sorter"; that DOI is de Boer et al., "Formal Specification and
    Verification of JDK's Identity Hash Map Implementation" (iFM 2022, FAoC 2023). README "Thread
    Safety" follows the A1 contract. Interrupted reads throw `java.io.InterruptedIOException`
    (cause via `initCause`, interrupt flag kept) instead of `new IOException(InterruptedException)`
    — a subtype, so source-compatible for callers, and the conventional signal for cancellation by
    interrupt (what `StructuredTaskScope` does). Done when: Javadoc `@throws`, JML `signals` clauses
    and tests (type and interrupt flag) agree.
  - **A3 — The A1 defect in every existing tool (2–3 days).** A third JPF harness with two readers
    (a writer writes two bytes and closes) — JPF must report a deadlock or the uncaught
    `NoSuchElementException` on `7ce9033`, which is also its non-vacuity proof; the harness for the
    array-read / `waitForAtLeast` paths and one for trim re-entrancy through a trim signal (both
    formerly "JPF follow-ups" below); jcstress `Mode.Termination` tests with two readers (only if A1
    supports several readers); vmlens scenarios for two readers, close, trim with signal and
    `safeWrite`; Lincheck with the reader operations in one `nonParallelGroup` (models the single
    consumer) reading only when `available() > 0` (only the consumer removes data, so that never
    blocks), plus a setup with a small `maxBufferElements` so trim runs — first check that
    `@Operation(nonParallelGroup = …)` exists in Lincheck 3.7. Done when: every new check is red on
    `7ce9033` and green after A1 (the F149 practice).
  - **A4 — Data-race freedom as a stated argument (2–3 days).** JLS §17.4.5: if a program is
    correctly synchronized, all its executions appear sequentially consistent; "correctly
    synchronized" means no *sequentially consistent* execution has a data race. So checking SC
    executions for races is enough, and then every SC-based result (JPF, vmlens, Lincheck, the A5
    model) holds under the JMM; the JMM's known flaws (out-of-thin-air, causality) only concern
    racy programs. The theorem is machine-checked (Aspinall & Ševčík, TPHOLs 2007; Lochbihler,
    JinjaThreads, TOPLAS 2014). vmlens already traces every interleaving and reports races by the
    JMM's happens-before, so no new tool is needed: (a) write the chain down in README/CLAUDE.md,
    (b) a table of every shared field (guarded / volatile / final / atomic) plus why the `byte[]`
    contents are safe (published through `bufferLock`; with `safeWrite=false` a later change of the
    array by the caller is the caller's own race), (c) CI fails when vmlens reports a race, over the
    A3 scenarios. State the limits: it covers the executed scenarios; the JDK classes
    (`Semaphore`/AQS, `ArrayDeque`, `CopyOnWriteArrayList`) and the JVM including its JIT are the
    trusted base.
  - **A5 — TLA+/PlusCal model of the protocol (~1 week).** Writer, N readers (constant), closer,
    the max-1 semaphore, the `availableBytes` check outside the lock, trim as one atomic step under
    the lock. Safety: bytes read are a prefix of bytes written, `available = written − read`, no
    write accepted after a close was observed (F149), no removal from an empty deque. Liveness
    under weak fairness: a waiting reader returns once enough bytes are there or the buffer is
    closed. TLC in `formal-verification.yml`, `tla2tools.jar` pinned by version and SHA-256.
    TLA+ was not part of the 2026-09 evaluation below. Done when: N=2 on the
    pre-fix model yields the A1 counterexample, the fixed model is green, N=1 is green on both.
  - **A6 — Trace validation (1–2 weeks).** Record the events of real runs (JPF listener, or
    test-side wrappers / an agent — no change to production code) and check the traces against the
    A5 spec with TLC (the approach of Cirstea, Kuppe, Merz et al., 2024). Closes the gap between
    model and code. Done when: a deliberately wrong spec rejects recorded traces.
  - **A7 — Virtual threads and a contended benchmark (2–3 days).** Tests already compile at
    `testRelease` 21, so the reader/writer/close tests can run on virtual threads too. Pinning
    check with the JFR event `jdk.VirtualThreadPinned` needs a JDK 21 leg: since JDK 24 (JEP 491)
    `synchronized` no longer pins, and CI builds with 25. Known candidate: `trim()` copies the whole
    buffer under `synchronized`, so virtual readers waiting for the monitor block their carrier on
    JDK 21–23. A JMH producer/consumer benchmark (`@Group`, one `@GroupThreads` each), platform vs
    virtual threads, on x86 and on the GitHub ARM runner — the baseline for A8. Report only, not a
    gate (shared runners are too noisy).
  - **A8 — `ReentrantLock` + `Condition` instead of `synchronized` + semaphore (optional, ~1
    week).** Only if A1 wants full multi-reader support: `signalAll` on write and close, waiting
    under the lock with re-check, no carrier pinning on JDK 21–23, timeouts via `awaitNanos`. The
    lock-free `available()` path stays `volatile`, the external semaphore signal API stays. Check
    Error Prone's `@GuardedBy` support for `Lock` fields; A3–A7 are the safety net; the A7 JMH
    comparison is mandatory.
  - **A9 — Functional proof of the sequential instance core (long-term, months).** The parked
    "Deeper ESC" item below; OpenJML first, KeY only for goals where Z3 answers "unknown".
  - **A10 — Class invariants under RAC via qualified delegation (hours).** The downstream
    workaround named in the RAC invariants item below: qualify the delegating calls of
    `SBInputStream`/`SBOutputStream` as `StreamBuffer.this.writeSingleByte(b)` etc., then enable
    the four candidate invariants from the `.jml` header under OpenJML 21.0.29. Done when:
    `-Pjml-rac` with invariants passes 285/285, or the negative result is reported on
    OpenJML/OpenJML#1012.
  - **A11 — API compatibility gate (hours).** japicmp or revapi against the last release on Maven
    Central, failing on a binary-incompatible change without a matching version step. Missing
    today.
  - **A12 — Waiting with a timeout (1–2 days).** `waitForAtLeast(long bytes, long timeout,
    TimeUnit unit)` via `Semaphore.tryAcquire` (Java 8; `awaitNanos` after A8): cancellation by
    deadline instead of only by interrupt. New API: JML spec, tests, README.
  - **A13 — Unbounded safety of the A5 model (weeks).** TLC checks fixed constants only: check
    the inductive invariant with Apalache, or prove it with TLAPS.
  - **Considered 2026-11 and not planned:** `StructuredTaskScope` inside the library (Java 8
    target, a caller-side API; preview in JDK 27 as JEP 533, final planned for JDK 28 with JEP 543 —
    at most an example once JDK 28 is released); fuzzing with Jazzer (jqwik properties plus PIT at
    100 % already cover the sequential side); checking the class against the full JMM including
    racy behaviour (no tool handles a class using `java.util.concurrent`; research tools such as
    jMT, jmc or MemSAT work on litmus-size programs — A4 is the sound route); VerCors (rejected
    2026-09, see below).

- **Formal verification — follow-ups.** The two-layer setup (OpenJML ESC proof of the static
  sequential core + OpenJML RAC under the full test suite) landed 2026-09 — see CLAUDE.md
  "Formal Verification" and `.github/workflows/formal-verification.yml`. Still open, in priority
  order:
  - **Checker Framework Lock Checker (deferred, not rejected).** Would soundly gate the
    `@GuardedBy("bufferLock")` discipline (Error Prone gates it heuristically today, in the
    default build). Blocked on a real cascade, not effort aversion: CF's JDK stubs for
    `Closeable`, `InputStream` and `OutputStream` declare mutually inconsistent `close()`
    receiver types (`@GuardSatisfied` vs `@GuardedBy`), so any receiver annotation that
    satisfies one stub violates another — plus `toString()`'s `synchronized` block trips
    `synchronized.block.in.lockingfree.method`. Revisit if CF ships consistent stubs, or gate it
    with a curated `-AskipDefs`/stub override.
  - **JPF interleaving harness — follow-ups.** The harness (`src/test/jpf/`, the scheduled
    `jpf-interleavings` job in `formal-verification.yml`) runs. Still open: report the AtomicLong
    model completion upstream as a jpf-core deficiency (its native peer already implements the
    methods the stub model never declared). Further harnesses (two readers, the array-read /
    `waitForAtLeast` blocking paths, trim re-entrancy) are package A3 of the roadmap above.
  - **RAC evaluates a `signals (E e)` clause for an exception of another type — confirmed OpenJML
    bug, reported in [OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050)** (2026-10-19; reproduced on 21.0.28 and on `dev-21` `529ac454da`,
    `BUGHUNT-MEASUREMENTS.md`, „OpenJML-Verdachtsfälle (RAC)“, in commit `0620aa7`, removed since). The spec
    of `waitForAtLeast` allows `InterruptedException` (`signals_only IllegalArgumentException,
    InterruptedException`) and constrains only the other one (`signals (IllegalArgumentException e)
    bytes <= 0`). When a read is interrupted, RAC prints `JML undefined exceptional postcondition -
    exception thrown` with `ClassCastException: InterruptedException cannot be cast to
    IllegalArgumentException` (stack at `waitForAnyData`, which calls `waitForAtLeast`). By JML's
    semantics the clause only applies when the exception is an instance of `E`, so nothing should be
    reported. Confirmed: the call-site check casts without an `instanceof` guard when the predicate
    folds to `false` for the actual argument (`waitForAtLeast(1L)`), `JmlAssertionAdder.applyHelper`.
    Harmless here (reported, not thrown, under `rac=exception`; the test stays green). To do: re-run
    once a release carries the fix.
  - **RAC prints a full stack trace per call for an uncompiled model method — confirmed OpenJML
    usability defect, reported in [OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050)** (2026-10-19, same issue; 1000 `arraycopy` = 1000 traces, also
    on `dev-21`; compiling with `-quiet` silences it). Every `System.arraycopy` and `clone` under RAC logs
    `Skipping a specification clause because it contains an uncompiled model method: 'boolean
    java.util.Arrays.equalArrays` plus a `NoSuchMethodError` stack trace (about 10 KB), once per
    call rather than once per clause. That is what made the concurrent-trim test take 7,344 s and
    21 GB of log; worked around by scaling the stress loops under `-Pjml-rac`
    (`StreamBufferTest.iterations`) and running jqwik with 100 tries there. Once fixed upstream, the
    scaling can go.
  - **Invariants + non-static inner classes break RAC — confirmed OpenJML bug, reported in
    [OpenJML/OpenJML#1012](https://github.com/OpenJML/OpenJML/issues/1012).** RAC checks the outer class's invariant inside the inner class's constructor and
    reads the field on the inner class → `NoSuchFieldError` at runtime (21.0.27 and 21.0.28).
    **21.0.29: the minimal reproducer below runs clean, the defect on this class does not go away** --
    with the four candidate invariants RAC throws `NoSuchMethodError` on
    `StreamBuffer$SBOutputStream.JML$INV$$<n>()` (the outer invariant check called on the inner
    class), 106 errors (measured 2026-10-20).
    **Narrowed down 2026-10-21 (21.0.29):** the trigger is an inner-class method calling an outer
    instance method *without a qualifier* -- exactly the delegation `SBOutputStream.write(int)` →
    `writeSingleByte(b)` (and `writeFromArray`, `closeAll`, `readSingleByte`, `availableClamped`).
    RAC checks the callee's receiver invariant on `this` (the inner object) instead of
    `StreamBuffer.this`:
    ```java
    public class InvA {
        private long x = 1;
        //@ private invariant 0 <= x;
        void inc() { x++; }
        class Inner { void go() { inc(); } }
        public static void main(String... a) { new InvA().new Inner().go(); }
    }
    ```
    → `NoSuchMethodError: 'boolean InvA$Inner.JML$INV$$107()'`. Same with a `private` outer method.
    Clean: `InvA.this.inc()`, `other.inc()` on another reference, outer → inner calls,
    `synchronized (InvA.this) { x++; }` inside the inner class. To report on
    [OpenJML/OpenJML#1012](https://github.com/OpenJML/OpenJML/issues/1012). Possible downstream
    workaround to try: qualify the delegating calls as `StreamBuffer.this.writeSingleByte(b)`
    (package A10 of the roadmap above).
    The 21.0.27/21.0.28 reproducer (fixed in 21.0.29):
    ```java
    public class Outer {
        private long x = 1;
        //@ private invariant 0 <= x;
        class Inner { Inner() {} }
        public static void main(String... a) { new Outer().new Inner(); }
    }
    ```
    `openjml --rac` compiles; running it throws `NoSuchFieldError: Class Outer$Inner does not
    have member field 'long x'`. With the four candidate invariants StreamBuffer fails 258/285
    tests. An earlier 21.0.27 compile crash ("no enclosing instance") was not reproduced.
  - **Deeper ESC — instance-method / trim() functional correctness (parked, revisit; package A9
    of the roadmap above).** Today
    ESC proves the 14 static helpers; the instance methods and trim() are RAC-only. A full
    functional proof (e.g. a ghost model sequence for the deque with the invariant
    `availableBytes == sum of buffered byte[] lengths`, preserved across read/write/trim) is the
    "TimSort-level" target. Currently blocked two ways: OpenJML ESC returns solver "unknown" on
    instance methods of this class (the non-static inner stream classes poison the receiver
    context), and modelling the deque as a ghost `\seq` is large (the LinkedList/KeY study was
    ~7 person-months for 328 LoC). Not gold-plating in principle — just expensive today; worth a
    re-scoping spike to see whether a *partial* invariant (e.g. non-negativity + position bounds
    proven on a static extraction of the read/write inner loops) is reachable more cheaply.
  - **On every OpenJML upgrade:** re-try the four class invariants documented in the `.jml`
    header (no bundled spec is deleted at install any more since fixups v3, so there is nothing
    to re-try in `.github/actions/setup-openjml/action.yml`), and, once #1050 is fixed, drop the
    RAC scaling (`streambuffer.test.rac` and `jqwik.tries.default` in the `jml-rac` profile,
    `StreamBufferTest.iterations`).
  - **Evaluated and rejected 2026-09** (do not re-open without new facts) — deductive/model-checking
    alternatives beyond OpenJML: **KeY 3.0.0** — could
    re-prove the same static scope with archived `.proof` files, but proof replay is
    version-brittle and adds maintenance without widening the scope (generics unsupported, no
    concurrency, no `Deque`/`java.util.concurrent` stubs); **VerCors 2.4.0** — only candidate
    with concurrent-Java separation logic, but models locks as single-entrant, has no
    volatile/JMM semantics and near-empty JDK stubs: verifying StreamBuffer means re-modeling it,
    a research project; **JBMC (cbmc 6.11)** — its JDK-8 model library has no
    `ArrayDeque`/`java.util.concurrent`, thread support officially limited; would only duplicate
    the ESC scope, bounded; **Infer/RacerD v1.3.0** — explicitly "avoids reasoning about weak
    memory and Java's volatile keyword", i.e. blind to exactly this class's design.

- **jqwik pin policy** — see [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md). `jqwik.version ≤ 1.9.3` is mandatory. A standing constraint, not a task: it has to be re-checked whenever the dependency is bumped.

- **`@VisibleForTesting` audit.** `StreamBuffer` has **15** package-private methods that exist so tests can reach them (`decideTrimExecution`, `shouldTrim`, `clampToMaxInt`, `decrementAvailableBytesBudget`, `calculateResultingChunks`, the five `shouldSkipTrim*`/`should*` predicates, `isAvailableBytesPositive`, `isMaxAllocSizeLessThanAvailable`, `shouldCheckEdgeCase`, `recordReadStatistics`, `shouldUpdateMaxObservedBytes`, `updateMaxObservedBytesIfNeeded`). None is annotated, and Guava is not a dependency here — so closing this means deciding between (a) adding a project-local marker annotation, which puts a new public type into the API surface of a deliberately one-class library, and (b) recording that the convention does not apply to this repo. Decide and act; do not leave it as a permanently open audit.

- **Null-safety refinement.** JSpecify + NullAway are enforced at compile time in **strict JSpecify mode** with the extra options `CheckOptionalEmptiness`, `AcknowledgeRestrictiveAnnotations`, `AcknowledgeAndroidRecent`, `AssertsEnabled` (see `pom.xml`); the package carries an explicit `@NullMarked` via `package-info.java`. The production code has no `@Nullable` markers because every value is non-null by construction (constructors reject `null`, no `return null` sites). Open follow-up: as new public API surfaces are added, evaluate whether `@Nullable` or `Optional<T>` would be more precise than the implicit non-null default.

- **Cross-repo code-quality TODOs** — see [`../workspace/policies/code-quality-todos.md`](../workspace/policies/code-quality-todos.md) for the canonical `@VisibleForTesting` design-fit review, package hierarchy review, and class/method naming review. This module is single-package, so the package review is trivially satisfied; the naming review is still open.
