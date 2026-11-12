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
  F278). Order: A6 on the A5 spec (A13 is done for `read()`); A8 is measured and parked (no throughput
  reason, see there); A9 is long-term. A6 also builds infrastructure that a later memory-model project can reuse (jcstress on
  several architectures, formal tools pinned in CI, checking real executions against a formal model)
  — so pinned tool setups belong in a composite action of bernardladenthin/actions rather than in
  this workflow.

  - **A6 — Trace validation (1–2 weeks).** Record the events of real runs (JPF listener, or
    test-side wrappers / an agent — no change to production code) and check the traces against the
    A5 spec (`src/test/tla/StreamBuffer.tla`) with TLC (the approach of Cirstea, Kuppe, Merz et al.,
    2024). Closes the gap between model and code. Done when: a deliberately wrong spec rejects
    recorded traces. Run with `/loop` and the prompt in "Run prompts" below.
    Run plan (branch `feat/a6-trace-validation`; decisions with reasons, ticked with their commit):
    - Decisions (2026-11-12, after the paper, arXiv 2404.16075, and Merz's TLA+ 2024 slides):
      - **Recording:** a test-side class loader rewrites the bytecode of `StreamBuffer` with ASM
        (already on the test classpath through Lincheck, declared explicitly): every access to
        shared state (`availableBytes`, `streamClosed`, `waitingReaders`, `bufferLock` enter and
        exit, `waitLock`, `modified.await`/`signalAll`, the FIFO and `positionAtCurrentBufferEntry`)
        calls a tracer. Non-blocking accesses run and log under one global trace lock, so the log
        order is the real order of those accesses; a blocking one (monitor enter, `lock()`,
        `await()`) logs right after it returns, a release right before it. Why: real JVM threads
        instead of JPF's scheduler, no `-javaagent` in Surefire, the source and the shipped jar
        untouched. Seeded random yields in the tracer vary the interleavings.
      - **Trace format:** the test writes each trace as a TLA+ module (`Trace == << [...], ... >>`)
        instead of ndjson. Why: `ndJsonDeserialize` needs the CommunityModules jar, a second pinned
        dependency; a generated module needs only the pinned `tla2tools.jar` (MongoDB's conformance
        checking did the same).
      - **Trace spec:** `TraceStreamBuffer.tla` extends `StreamBuffer.tla` unchanged and adds the
        line counter `l`. Each event belongs to one code step of one thread (a group of accesses,
        e.g. the two volatile reads of the fast path of `waitForAtLeast`); within its group the
        thread may take its spec step(s) at any of the group's events, outside it the thread
        stutters, and at the group's end the thread's spec state must match what the code did (the
        values it read and returned, the bytes it got). Why: the model is coarser than the code in
        places (the fast path reads `availableBytes` and `streamClosed` in one step,
        `ReaderTest` decrements `waitingReaders` in the step that reads the count); where the code
        allows an outcome no placement explains, the trace is rejected, which is a finding about
        the model, not a reason to bend it. Accepted = every line consumed (`l > Len(Trace)`),
        checked as an invariant TLC must violate or as a postcondition if TLC 1.7.4 has one;
        deadlock checking off (the paper).
      - **Scenarios** = the model's: one writer of `Bytes` bytes (values 1, 2, ...) in writes of
        `ChunkLen`, one closer, readers of `read()` or `read(b, 0, ReadLen)`, `waitForAtLeast`
        callers; `maxBufferElements` above the number of writes (trim is not modeled).
    - [x] Tracer and instrumenting class loader, unit test (`ebac6b8`): a single-threaded write/read gives the
      expected event list.
    - [x] Trace spec for the writer and the closer, then the readers; first trace accepted (`ebac6b8`).
    - [x] Trace generator (`ebac6b8`, a main class run by the script, not a test): scenarios x seeds, traces written to `target/traces/`; a script
      `src/test/tla/trace.sh` runs TLC over them.
    - [x] Negative controls (`ebac6b8`, `trace-controls.sh`; CountOnce = FALSE and CheckedReturn =
      FALSE allow more behaviours and accept, see the script): at least two wrong specs (e.g. `ReCheck = FALSE`, `CheckedReturn =
      FALSE`, a mutated action) reject recorded traces; a corrupted trace is rejected by the
      correct spec.
    - [x] Numbers (traces, events, states, time) and the mismatches found in
      `src/test/tla/README.md`; CI step in `formal-verification.yml`; CHANGELOG, CLAUDE.md. No
      mismatch between model and code; the three places where the model is coarser are in the README.
    - [x] Wider runs: 990 traces (11 scenarios x 30 seeds x 3 yield rates), all accepted (again
      after the review, with assertions on). On the way:
      TLC runs in parallel truncated each other's standard modules in `java.io.tmpdir`, and a large
      here-string hung Git Bash; `trace.sh` gives each run its own temp directory and an output file.
    - [ ] Review, one push, PR, CI green.
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

    **Larger transfers (2026-11-12).** The benchmark starts new threads for every transfer of a few
    ms, so thread creation is part of the score above. With 131,072 records per transfer
    (179 MiB; a local change of `RECORDS`, not committed), JDK 25, two interleaved rounds, the ratios
    (ReentrantLock / synchronized) are:

    | threads | trim | 1/1 | 1/4 | 4/1 | 4/4 |
    |---|---|---|---|---|---|
    | platform | 100 | 0.84 | 0.35 | 0.91 | 0.78 |
    | platform | off | 0.59 | 0.74 | 0.52 | 0.54 |
    | virtual | 100 | 1.13 | 1.15 | 1.18 | 1.33 |
    | virtual | off | 0.62 | 1.76 | 1.35 | 1.41 |

    Platform threads are consistently faster with a `ReentrantLock`, up to 1.9x with trim off.
    Virtual threads are mostly slower: the monitor spins before it parks, the lock parks sooner,
    and an unmount and remount costs a virtual thread more. So A8 is a trade-off between the two
    kinds of thread, not a free gain. It stays parked until a workload decides which kind matters;
    if it is taken up, measure with large transfers (or persistent threads) and on JDK 21 as well.

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
    still (0.8-2.0 ms), the price of the entry bound. The TLA+ model does not model trim. With a
    backlog of 179 MiB (131,072 records per transfer, see A8), the default threshold costs 10-20x
    against trim off (platform 1/1: 277 against 23 ms). That is the O(log n) of the design: each byte
    is copied about log2(131,072 / 100), about 10, times. A threshold that grows with the backlog
    would cut that further; possible follow-up.
  - **A9 — Functional proof of the sequential instance core (long-term, months).** The parked
    "Deeper ESC" item below; OpenJML first, KeY only for goals where Z3 answers "unknown".
  - **A13 — Unbounded safety and liveness of the A5 model. Done (2026-11-12).** Counter abstractions with inductive invariants:
    `StreamBufferCounters.tla` (`read()`), `StreamBufferRecords.tla` (`read(b, 0, K)`, any chunking
    of the writes, several writers and closers) and `StreamBufferWait.tla`: every thread any number
    of calls, each a `read(b, 0, K[r])` or a `waitForAtLeast(M[r])` with a read size and request of
    its own, several writers and closers.
    - **Apalache v0.63.0** (`inductive.sh`): fixed thread counts, with the bytes, the read sizes,
      the requests and the budget of calls symbolic.
    - **TLAPS** (`proof.sh`): any number of threads, writers and closers; 216, 488 and 577
      obligations.
    - **Liveness** (`StreamBufferWaitLive.tla`): with at least one closer, every behaviour with weak
      fairness of `Next` ends with every call returned and all done, for any number of threads,
      writers and closers and any finite programs (`FairSpec => <>AllDone`; TLAPS 363 + 628 + 919
      obligations, Apalache for 2 and 3 threads). A natural number goes down with every step, and
      a step is possible until all are done (README, "Liveness").
    - **Apalache soundness bug, found 2026-11-12:** a skolemized `\E c \in a..b` asserts its bounds
      globally, so a range empty in some state cut every execution through it. Missed violations,
      and inductive steps that skipped pre-states (`w = Bytes`, no reader copying). The
      abstractions now use ranges that are never empty, and `inductive.sh` rejects any other
      (README "An Apalache pitfall"). Reported as
      [apalache#3503](https://github.com/apalache-mc/apalache/issues/3503) (2026-11-12, a 15-line
      reproduction); waiting for a maintainer to confirm it, since Apalache wants a confirmed issue
      before a fix PR. Then the prepared fix (`QuantRule.skolemExistsInRange`, the bounds as a
      conjunct of the result, with a regression test that fails on 0.63.0). The workaround and the
      guard stay until a release has the fix.
    - **Older code:** each older version reaches a violation of the safety property itself in a
      bounded search from `Init`: without the F278 re-check, with the two-phase read before #212,
      and with `waitForAtLeast` reading the count again before `CheckedReturn`.
    - **Link to the code:** TLAPS proves that `StreamBuffer.tla` with the current code refines
      `StreamBufferWait.tla` for any number of readers (`RefineWaitProof.tla`, 2,656 obligations),
      so its safety results hold for the detailed model (liveness does not carry over: the
      refinement is of the specifications without fairness). TLC also checks the
      refinement of all three abstractions (`RefineCounters.tla`, `RefineRecords.tla`,
      `RefineWait.tla`) in the bounded configurations.
    - Details and limits in `src/test/tla/README.md`.

    Still open: liveness with a thread that calls forever (it needs lock fairness, which the JDK
    does not promise).

    The detailed model covers `read()`, fixed-size `read(b, off, len)` (#212, F279), writes of
    several bytes, readers of two sizes and `waitForAtLeast` (the A5 rest, 2026-11-11).
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

## Run prompts

Prompts for long `/loop` runs. The loop is started with a one-line reference to its section here,
so the prompt can be changed in this file without restarting the loop; the next iteration reads
the current text.

### A6 trace validation

Start: `/loop Work on A6 as described in TODO.md, section "Run prompts" / "A6 trace validation", re-read on every iteration.`

````text
Implement A6 trace validation for streambuffer fully automatically and as independently as
possible. It may take longer than one session; there is no deadline. Work locally by default; for
heavy runs a rented instance (e.g. Vultr, see ../workspacePrivate/remote.md) is allowed for up to
about 10-15 EUR in total: enter it in remote.md while it runs, delete it and sweep when done.
Web search is allowed, and so is Chrome (Claude in Chrome) for pages a search does not show.

Goal (TODO.md, roadmap A6): record the events of real runs and check them with TLC against the A5
spec src/test/tla/StreamBuffer.tla (the approach of Cirstea, Kuppe, Merz et al. 2024, "Validating
Traces of Distributed Programs Against TLA+ Specifications"). Done when: recorded traces of the
current code are accepted, AND a deliberately wrong spec (e.g. without the F278 re-check, without
CheckedReturn, or a mutated action) rejects the same traces.

Procedure:
1. First iteration: switch to the branch feat/a6-trace-validation in the real clone (git switch;
   create it from main if it does not exist). Web-search the current state of TLA+ trace
   validation (trace spec with TraceNext, ndjson log, IOUtils/JSON deserialization, TLC
   configuration; examples from tlaplus/Examples and the paper). Then write a plan as checkbox
   steps under A6 in TODO.md and commit it. Every later iteration: do the next open step, test
   it, tick it with its commit, add steps found on the way.
2. No change to production code: record only on the test side (wrappers, listener, agent or JPF
   listener). The events must match the actions of StreamBuffer.tla, including lock boundaries and
   waitingReaders; where the model is finer than what can be observed, fill in
   nondeterministically (trace spec with stuttering/auxiliary steps), do not bend the model.
3. Local: download TLC in the version and with the SHA256 from
   .github/workflows/formal-verification.yml into the scratchpad and verify it. Maven build with
   JAVA_HOME=/c/Users/berna/AppData/Local/Programs/jdk-25.0.4.1+1. JPF only in Docker
   (eclipse-temurin:11-jdk + apt-get install git, MSYS_NO_PATHCONV=1). Several traces: different
   numbers of readers, read() / read(b, off, len) / waitForAtLeast, close, several writers.
4. Negative controls are mandatory: at least two wrong specs or mutations that must reject the
   real traces; and a deliberately corrupted trace that the correct spec must reject. Results
   with numbers (traces, events, states, time) in src/test/tla/README.md.
5. CI: hook into the existing formal-verification.yml (no new workflow file), keep the run time
   small. Update CHANGELOG.md, CLAUDE.md and TODO.md.
6. At the end: review of the branch by an agent. Only regressions against main, moderate or high
   bugs in the branch's own changes, and wrong statements in the docs block the push; the rest
   goes as one line under Known limits in TODO.md. At most one more round. Then exactly one push,
   open the PR (do not merge, no dispatch runs), watch CI; on a CI error of my own: cancel the
   run, commit the fix, push.
7. Rules: no questions (ask only for something that is the owner's to decide, such as more
   budget), decide by best practice and give the reason for each decision in the TODO step. No force-push, no pkill -f, delete only with Remove-Item, no private data to external
   services. At the end remove the done steps from TODO.md; only the result stays.
8. When the PR is open and CI is green: summary in German (what was decided and why, numbers,
   open points), then end the loop.
````
