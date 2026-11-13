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
  F278). State: A6, A13 and A14 are done (open points left under each); A8 is measured and parked
  (no throughput reason, see there); A9 is long-term. The infrastructure (jcstress on several
  architectures, formal tools pinned in CI, checking real executions against a formal model) is
  reusable by a later memory-model project — so pinned tool setups belong in a composite action of
  bernardladenthin/actions rather than in this workflow (not done yet: TLC, Apalache and TLAPS are
  still set up inline in `formal-verification.yml`).

  - **A6 — Trace validation. Done (2026-11-13, PR #227).** Real runs of the code, recorded on the
    test side (an ASM class loader rewrites `StreamBuffer`'s bytecode; source and jar untouched),
    are checked with TLC against `StreamBuffer.tla` unchanged (`TraceStreamBuffer.tla`,
    `trace.sh`): 990 traces (11 scenarios x 30 seeds x 3 yield rates), all accepted; every
    negative control rejects (the wait before F278, no re-check, `read(b, off, len)` before #212, a
    writer that never signals, corrupted traces). No mismatch between model and code. Details,
    numbers and limits in `src/test/tla/README.md`, "Trace validation".

    Still open:
    - [ ] The CI step (job `tla-model`, scheduled only) has not run on GitHub yet; check the first
      scheduled run (Monday 04:17 UTC) for green and its time (local estimate about 5 min for
      the 33 traces and the controls).
    - [ ] Not covered by the scenarios: several writers and several closers (the detailed model has
      one of each; the A13 abstractions have several, but no trace check against them), trim (not
      modeled; the scenarios set `maxBufferElements` above the number of writes), and
      `waitForAtLeast` with a timeout (`awaitNanos` is not rewritten, not in the model).
    - [ ] A spurious wake-up of `await()` is not in the model and would reject a trace (none
      occurred in 990 runs). If one shows up in CI: model it (a parked waiter may wake without a
      signal), not a retry.
    - [ ] The trace lines name a method and its n-th access (`waitForAtLeast.getAvail#0`): a
      change of the wait or read paths needs the mapping in `TraceStreamBuffer.tla` changed with
      it (`TraceRecorderTest` fails first).
    - [ ] Reuse for the memory-model project: the recorder serializes all traced accesses under
      one global lock, so it records sequentially consistent runs only; a weak-memory trace check
      would need another recording.
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
      reproduction), fixed by
      [apalache#3505](https://github.com/apalache-mc/apalache/pull/3505) (merged 2026-11-12,
      `QuantRule.skolemExistsInRange`, the bounds as a conjunct of the result, with a regression
      test). Latest release is still v0.63.0 (without the fix).
      - [ ] On the first Apalache release after 2026-11-12: bump `APALACHE_VERSION` and its
        SHA-256 in `formal-verification.yml`, run `inductive.sh` once with a range that can be
        empty to see the fix, then decide whether the never-empty workaround and the guard in
        `inductive.sh` go (they stay correct either way; keep them if older versions must still
        work).
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

    **Liveness with threads that call forever. Done (2026-11-13, branch
    `feat/a13-liveness-forever`).** With a finite stream and a closer every call of every thread
    returns although threads call forever, with fair scheduling only (weak fairness per thread,
    writer and closer), no lock fairness: TLC on `StreamBufferWaitForever.tla` (the abstraction
    with a ghost `Refill` of the call budget) and `StreamBufferForever.tla` (the detailed model, a
    thread calls again when done), and TLAPS for the abstraction and any number of threads, writers
    and closers (`StreamBufferWaitForeverLiveProof.tla`, 1,322 + 633 obligations) under the
    fairness by role. With an endless writer and no close a reader starves even with every thread
    step strongly fair (the bytes go to whoever commits first). The detailed model's readers have
    weak fairness now (was strong). Details, numbers, controls and limits in
    `src/test/tla/README.md`, "Liveness with threads that call forever".

    Still open:
    - [ ] The new models (`check.sh`, `tla-model`) and proofs (`proof.sh`, `tlaps-proofs`) have
      not run on GitHub yet; check the first scheduled run (Monday 04:17 UTC) for green and its
      times against the local ones (594 s and 2,866 s on 4 cores; the timeouts are 75 and 120 min).
    - [ ] `FairRole` is the proof's assumption; that it follows from the fairness per thread is
      argued and checked by TLC in bounded models only (tlapm cannot derive it for a symbolic set
      of threads: no rule from `\A q : P(q) ~> Q` to `(\E q : P(q)) ~> Q`).
    - [ ] The detailed model's forever liveness rests on TLC's bounded models; the refinement
      proof does not carry liveness.
    - [ ] tlapm 1.6.0-pre (`ff40755`) quirks, both worked around and reproduced in minimal modules
      (README, "tlapm 1.6.0-pre quirks"): a lemma cannot be instantiated at a term inside ENABLED
      (probably tlapm#75, "ENABLED is not coalesced"); expanding ENABLED crashes
      (`e_substitutive.ml`, line 143) when the module also has, unused,
      `G(q) == CASE y = q -> 1 [] OTHER -> 0`, `GF == [q \in S |-> G(q)]` and `GK == GF' = GF`
      (no issue found). Report both on tlaplus/tlapm (the owner's to decide: an issue from the
      owner's account), then note the links here.

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

- **CI: `claude-review` fails on every PR, at least since #214 (owner action).** The job
  (`claude-code-review.yml`, `anthropic_api_key: secrets.ANTHROPIC_API_KEY`) ends after 0.4 s
  with `is_error: true`, one turn, cost 0, empty `modelUsage` (checked on #214-#227; run
  43326281438). So the API is never reached with a usable key: check the secret (expired,
  revoked or out of credit) in the repository settings. Not related to the branches.

- **jqwik pin policy** — see [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md). `jqwik.version ≤ 1.9.3` is mandatory. A standing constraint, not a task: it has to be re-checked whenever the dependency is bumped.

- **`@VisibleForTesting` audit.** `StreamBuffer` has **15** package-private methods that exist so tests can reach them (`decideTrimExecution`, `shouldTrim`, `clampToMaxInt`, `decrementAvailableBytesBudget`, `calculateResultingChunks`, the five `shouldSkipTrim*`/`should*` predicates, `isAvailableBytesPositive`, `isMaxAllocSizeLessThanAvailable`, `shouldCheckEdgeCase`, `recordReadStatistics`, `shouldUpdateMaxObservedBytes`, `updateMaxObservedBytesIfNeeded`). None is annotated, and Guava is not a dependency here — so closing this means deciding between (a) adding a project-local marker annotation, which puts a new public type into the API surface of a deliberately one-class library, and (b) recording that the convention does not apply to this repo. Decide and act; do not leave it as a permanently open audit.

- **Null-safety refinement.** JSpecify + NullAway are enforced at compile time in **strict JSpecify mode** with the extra options `CheckOptionalEmptiness`, `AcknowledgeRestrictiveAnnotations`, `AcknowledgeAndroidRecent`, `AssertsEnabled` (see `pom.xml`); the package carries an explicit `@NullMarked` via `package-info.java`. The production code has no `@Nullable` markers because every value is non-null by construction (constructors reject `null`, no `return null` sites). Open follow-up: as new public API surfaces are added, evaluate whether `@Nullable` or `Optional<T>` would be more precise than the implicit non-null default.

- **Cross-repo code-quality TODOs** — see [`../workspace/policies/code-quality-todos.md`](../workspace/policies/code-quality-todos.md) for the canonical `@VisibleForTesting` design-fit review, package hierarchy review, and class/method naming review. This module is single-package, so the package review is trivially satisfied; the naming review is still open.

## Run prompts

Prompts for long `/loop` runs. The loop is started with a one-line reference to its section here,
so the prompt can be changed in this file without restarting the loop; the next iteration reads
the current text.

No run open.
