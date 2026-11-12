# TODO — streambuffer

Open work items for this repo. Cross-cutting tracking lives in
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md);
items here are streambuffer-specific or are this repo's slice of a
cross-cutting initiative.

**Completed work is not recorded here.** It lives in git history and in
`crossrepostatus.md`; a finished item is deleted from this file rather than
annotated, so everything below is genuinely still open.

## Open

- **Verification roadmap 2026-11 — packages A6–A14.** Each package is closed on its own, ends in a
  machine-checked result and is listed with its acceptance criterion. The contract every package
  checks: several readers and writers are supported, without fairness (decided with bug-hunt finding
  F278). Order: A13 (Apalache) and A6 on the A5 spec; A8 is measured and parked (no throughput
  reason, see there); A9 is long-term. A6 also builds infrastructure that a later memory-model project can reuse (jcstress on
  several architectures, formal tools pinned in CI, checking real executions against a formal model)
  — so pinned tool setups belong in a composite action of bernardladenthin/actions rather than in
  this workflow.

  - **A6 — Trace validation (1–2 weeks).** Record the events of real runs (JPF listener, or
    test-side wrappers / an agent — no change to production code) and check the traces against the
    A5 spec (`src/test/tla/StreamBuffer.tla`) with TLC (the approach of Cirstea, Kuppe, Merz et al.,
    2024). Closes the gap between model and code. Done when: a deliberately wrong spec rejects
    recorded traces.
  - **A8 — `ReentrantLock` instead of `synchronized (bufferLock)` — measured 2026-11-12: no
    throughput reason, parked.** The waiting part landed with F278 (`waitLock`, a `Condition`,
    `signalAll`, the re-check under `bufferLock`). Still on `synchronized`: every FIFO access, so a
    virtual thread blocked at the monitor holds its carrier on JDK 21–23, which
    `jdk.VirtualThreadPinned` does not show (it covers parking while pinned).

    **What the time goes to now** (Vultr `voc-c-16c-32gb`, AMD EPYC Milan, 8 cores with SMT,
    JDK 25.0.5, main with A14, `StreamBufferContendedBenchmark`, platform threads, async-profiler
    wall clock of the writer and reader threads): blocked on `bufferLock` 43 / 66 / 51 / 78 % of
    thread time at trim 100 (writers/readers 1/1, 4/1, 1/4, 4/4), 33 % (1/1) and 58 % (4/4) with trim
    off; lock profile (total wait time): 18-47 % at trim 100, 0.5-26 % with trim off. The first
    measurement (A14, below) found trim at 82-89 % of the CPU; now the threads queue at the lock.

    **A/B with a prototype** (all six `synchronized (bufferLock)` blocks as `lock()`/`unlock()`,
    otherwise unchanged; two interleaved rounds each, round-to-round spread a few percent;
    ReentrantLock / synchronized, below 1 = faster):

    | JDK | threads | trim 100: 1/1, 4/1, 1/4, 4/4 | trim off: 1/1, 4/1, 1/4, 4/4 | trim 1000: 1/1, 4/1, 1/4, 4/4 |
    |---|---|---|---|---|
    | 25 | platform | 1.00, 1.03, 0.76, 0.91 | 0.69, 1.02, 0.64, 0.80 | 1.00, 1.05, 0.93, 0.90 |
    | 25 | virtual | 1.03, 1.25, 1.40, 1.52 | 0.67, 1.13, 1.39, 1.26 | 1.11, 1.07, 1.31, 1.77 |
    | 21 | virtual | 1.08, 1.04, 1.11, 1.14 | 0.75, 0.99, 0.93, 0.76 | 0.88, 1.03, 0.94, 1.21 |

    Mixed: up to 1.5x faster for platform threads, up to 1.8x slower for virtual threads on JDK 25,
    on JDK 21 between 0.75 and 1.21. The lock kind does not shorten the critical section the threads
    queue for. Three tests of the suite wait for `Thread.State.BLOCKED` (a monitor); a thread parked on
    a `ReentrantLock` is `WAITING`, so a real A8 would rewrite them
    (`StreamBufferConcurrentReadersTest`, `close_fromAnotherThreadDuringAWrite`). Error Prone's
    `NonAtomicVolatileUpdate` knows `synchronized` blocks but not `Lock` regions, so the read and
    write methods would need a suppression. Not covered: more virtual threads than carriers on JDK
    21–23 (the benchmark has at most 8 threads on 16 carriers), the case where a monitor holding a
    carrier matters; reconsider A8 only for that, with a benchmark of its own. A shorter critical
    section (copying outside the lock) would be the throughput lever, at the cost of the atomic
    `read(b, off, len)` of #212 -- not planned.

    Earlier baselines, before A14 (trim-dominated, kept for the record): local x86 2026-11-11,
    platform 1/1 65.4 ± 5.9, 4/1 66.2 ± 5.2, 1/4 49.6 ± 10.5, 4/4 65.2 ± 7.8; virtual 1/1 66.9 ± 7.0,
    4/1 61.6 ± 5.4, 1/4 57.1 ± 8.3, 4/4 52.5 ± 9.6 ms; on Vultr trim 100 32.7-46.7 ms, trim off
    0.84-2.04 ms, trim 1000 3.9-6.8 ms; arm64 (cfarm424, shared) too noisy to compare.
  - ~~**A14 — Trim policy: stop recopying the backlog.**~~ **Done 2026-11-11.** A trim used to merge
    every buffered byte into one array and, 100 writes later, copy that array again with the new
    entries: a backlog cost quadratic copying (measurement under A8). Now it merges geometrically:
    walking from the tail it takes every entry the caller may still hold (`ownedPrefix` counts the
    leading chunks a trim allocated) and an older own chunk only while it is not longer than what is
    collected, so each byte is copied O(log n) times and the FIFO keeps a few chunks of growing size;
    if that would leave more than half of `maxBufferElements` entries, it merges everything. The
    owner's condition holds: after any trim no buffered array is reachable from outside, so a caller
    writing without `safeWrite` may overwrite its arrays once a trim has run, and no `trimAll()` is
    needed (`StreamBufferTrimOwnershipTest`: green on the old and the new trim, red if a trim keeps a
    caller array). Checked: ESC 17 proofs (the helpers `joinsTrimMerge` and `shouldTrimMergeAll`,
    Z3 and cvc5; deliberately wrong specs fail), the full suite 353 tests on Vultr, vmlens no data
    race, JPF `TrimReentrancy` (24,972 states, was 24,880), `StreamBuffer`, `WaitAndRead`,
    `WriteClose` no errors, PIT 257/257 (100 %, Vast EPYC 7742, 48 threads, 24 min). Same Vultr
    machine, threshold 100, ms per 11 MiB transfer, before → after: platform 1/1 43.9 → 3.7, 4/1
    46.6 → 4.4, 1/4 39.7 → 4.9, 4/4 45.6 → 4.8; virtual 1/1 43.4 → 3.2, 4/1 41.2 → 3.4, 1/4 36.8 →
    3.5, 4/4 32.3 → 3.7 (8-13x); threshold 1000: 3.5-7.5 → 1.6-3.9. Trim off stays 2-4x faster
    still (0.8-2.0 ms), the price of the entry bound. The TLA+ model does not model trim.
  - **A9 — Functional proof of the sequential instance core (long-term, months).** The parked
    "Deeper ESC" item below; OpenJML first, KeY only for goals where Z3 answers "unknown".
  - **A13 — Unbounded safety of the A5 model (weeks).** TLC checks fixed constants only (up to 3
    readers, 2 bytes): check an inductive invariant of `src/test/tla/StreamBuffer.tla` with Apalache
    (unbounded byte counts and runs, fixed readers), or prove it with TLAPS for any number of readers.
    The model covers `read()`, fixed-size `read(b, off, len)` (#212, F279), writes of several bytes,
    readers of two sizes and `waitForAtLeast` (the A5 rest, 2026-11-11).
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
    methods the stub model never declared). Also worth reporting: jpf-core's `Thread.start` peer
    throws a `NullPointerException` (no `run()` found) for a harness with an anonymous
    `Semaphore` subclass next to lambdas; `JpfTrimReentrancyHarness` uses named classes instead.
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
  - **Report the unqualified-call trigger on [OpenJML/OpenJML#1012](https://github.com/OpenJML/OpenJML/issues/1012)
    (owner action: a comment on an external repository).** RAC (21.0.29) checks the receiver
    invariant of an outer instance method called *without a qualifier* from an inner class on the
    inner object; this class works around it with qualified calls (`StreamBuffer.this.x()`, CLAUDE.md
    "Formal Verification"), and the four class invariants run. Minimal reproducer:
    ```java
    public class InvA {
        private long x = 1;
        //@ private invariant 0 <= x;
        void inc() { x++; }
        class Inner { void go() { inc(); } }
        public static void main(String... a) { new InvA().new Inner().go(); }
    }
    ```
    → `NoSuchMethodError: 'boolean InvA$Inner.JML$INV$$107()'`. Same with a `private` outer method;
    clean with `InvA.this.inc()`.
  - **Deeper ESC — instance-method / trim() functional correctness (parked, revisit; package A9
    of the roadmap above).** Today
    ESC proves the static helpers (17 methods with the validators); the instance methods and trim() are RAC-only. A full
    functional proof (e.g. a ghost model sequence for the deque with the invariant
    `availableBytes == sum of buffered byte[] lengths`, preserved across read/write/trim) is the
    "TimSort-level" target. Currently blocked two ways: OpenJML ESC returns solver "unknown" on
    instance methods of this class (the non-static inner stream classes poison the receiver
    context), and modelling the deque as a ghost `\seq` is large (the LinkedList/KeY study was
    ~7 person-months for 328 LoC). Not gold-plating in principle — just expensive today; worth a
    re-scoping spike to see whether a *partial* invariant (e.g. non-negativity + position bounds
    proven on a static extraction of the read/write inner loops) is reachable more cheaply.
  - **On every OpenJML upgrade:** once #1050 is fixed, drop the RAC scaling
    (`streambuffer.test.rac` and `jqwik.tries.default` in the `jml-rac` profile,
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
