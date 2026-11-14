# TODO — streambuffer

Open work items for this repo. Cross-cutting tracking lives in
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md);
items here are streambuffer-specific or are this repo's slice of a
cross-cutting initiative.

**Completed work is not recorded here.** It lives in git history and in
`crossrepostatus.md`; a finished item is deleted from this file rather than
annotated, so everything below is genuinely still open.

## Open

- **Open items — effort, odds and timeline (estimated 2026-11-13, updated 2026-11-14).** Estimates,
  not measurements; "success" means the result is there as described, machine-checked. Details
  under the items named. In this order; A15 comes last (see its row).

  | # | Item | Work | Odds of success | Timeline | Why / risk |
  |---|---|---|---|---|---|
  | 1 | **First scheduled formal run after #233** (Monday 04:17 UTC): the eight manifest steps run, rows V1-V18 get a run with a SHA, `check.sh`'s 4-core time is measured | ~½ h to check | ~85 % | Monday | the steps never ran in CI (the TLA+, TLAPS and JPF jobs run on the schedule only); a failure there is a CI error of mine (cancel, fix, push) |
  | 2 | **A18** Every interleaving of the code is a run of the model. **In progress, branch `feat/a18-jpf-traces`**: the exact graph check works (JPF's state graph -> minimal automaton -> TLC product -> subset check, with three controls); open: the controls for every scenario, docs, a `V19` row, CI with the smallest scenario, PR | 2–4 days left | ~80 % for the small scenarios; larger ones bounded by JPF and TLC's dump | 1 week | two `read()` readers did not finish JPF in 4 h; automata above ~2,500 states did not finish TLC's dump in 4 h (one thread writes it). Speeding up the product (fewer controls per scenario, a dump written in parallel, or the subset check without a dump) decides how far it reaches |
  | 3 | `@VisibleForTesting` decision (15 package-private methods; below) | ½ day | ~95 % | a few days | only the decision (an own marker annotation, or the convention does not apply here), then act |
  | 4 | Naming review (below, `code-quality-todos.md`) | ~1 day | ~90 % | ~1 week | mechanical; renaming private methods is cheap, a public API rename is a breaking change for the CHANGELOG |
  | 5 | A14 follow-up: a trim threshold that grows with the backlog | 1–2 days | ~70 % | ~1 week | with a backlog of 179 MiB the default threshold costs 10-20x against no trim (A14, below); it changes how many entries the buffer keeps |
  | 6 | A6: several writers and closers in the detailed model (planned, below; after A18) | 1–2 weeks | ~70 % | 2–3 weeks | `StreamBuffer.tla` has one of each; `RefineWaitProof.tla` (2,729 obligations) must follow; the trace scenarios are easy afterwards |
  | 7 | A6: trim in the model | 1–2 weeks | ~60 % | 2–4 weeks | the merge of the entries touches the FIFO invariant and the refinement; the geometric merge is hard to state compactly |
  | 8 | **A19** Liveness of the detailed model for any number of readers | 2–4 weeks | medium, ~50 % | 3–6 weeks | the pattern of `StreamBufferWaitForeverLiveProof.tla` carries over, but the detailed model is much larger (the FIFO as a sequence, more stages, the copy per entry), and the assumption of the row below stays |
  | 9 | Prove that fairness per thread gives the fairness by role (`FairRole`, A13 follow-up; today argued and checked by TLC in bounded models) | 1–2 weeks | low, ~30 % | 2–3 weeks | tlapm cannot swap a quantifier over threads with a temporal operator (`\A q : P(q) ~> Q` to `(\E q : P(q)) ~> Q`), which is where it failed; another prover (e.g. Isabelle with a TLA embedding) would be the way out |
  | 10 | A8: `ReentrantLock` instead of `synchronized` (parked) | 3–5 days, if taken up | technically ~90 %; the gain unclear | 1–2 weeks | the measurements show a trade-off (faster for platform threads, slower for virtual threads); only worth it with a workload that decides which kind matters, e.g. more virtual threads than carriers on JDK 21-23 |
  | 11 | A9: functional proof of the instance methods (long-term) | months | low, ~20–30 % (a partial goal ~35 %) | 3–6 months | OpenJML ESC returns "unknown" on instance methods, and the deque as a ghost sequence is large; extract a sequential core first |
  | 12 | Checker Framework Lock Checker (deferred) | 1–2 days for a spike | ~40 % | ~1 week | blocked by inconsistent JDK stubs of `close()`; A17 checks the lock discipline on the bytecode already, so it is a candidate to drop |
  | 13 | **A15** Proofs as a release gate (`workflow_call`, publish waits for the formal jobs on `v*` tags) | 1–2 days | high, ~90 % | ~1 week | **only after every other item of this table is done** (owner, 2026-11-13): each package adds checks to the formal jobs, so the gate's run time is known only at the end, and until then the formal jobs stay scheduled and keep the CI of each release short. It changes the release process (about 2 h more per release): the owner confirms before it is merged |

  Best value for the risk: 1 and 2; 3 and 4 on the side. 8, 9 and 11 are research with an open
  outcome.

  **For the owner (decisions and actions on your accounts):**
  - the `ANTHROPIC_API_KEY` secret: `claude-review` fails in every pull request without it;
  - the two tlapm quirks as an issue at tlaplus/tlapm (your account);
  - OpenJML: a new issue for the inner-class invariant case left from #1012 (draft in the
    owner's private notes; the report-back on the closed #1012 is
    unanswered since 2026-10-21);
  - a composite action in bernardladenthin/actions for the pinned tool setups (OpenJML,
    jpf-core, tla2tools, Apalache, tlapm): shared by several repositories, so your decision.

  **Waiting on others:**
  - an Apalache release with apalache#3505 (merged 2026-11-12): then bump `APALACHE_VERSION` (A13,
    below);
  - an OpenJML release with #1050 (fixed on `dev-21`): then drop the RAC scaling of the tests;
  - jpf-core#664 (the `AtomicLong` model) and #665 (lambda type name vs. anonymous classes), opened
    2026-11-11: their CI waits for the maintainers' approval; once merged and pinned, the
    `AtomicLong` patch of the `jpf-interleavings` job can go.

  **Standing rules:** jqwik stays at 1.9.3 (below); the null-safety refinement (below) as new API
  surfaces appear.

- **A6: several writers and closers in the detailed model (planned 2026-11-14, after A18).** The
  detailed model `StreamBuffer.tla` has one writer and one closer; the abstractions have several
  (`StreamBufferWait.tla`: `Writers == 1..NW`, `Closers == 1..NC`). Done when TLC checks the
  current code with two writers and with two closers (safety and liveness), the older code still
  fails with its defects, `RefineWaitProof.tla` proves the refinement for any numbers of readers,
  writers and closers, and A6 records and accepts runs with two writers and two closers. Its own
  branch from `main` once A18 is merged: both change `StreamBuffer.tla` and `TraceStreamBuffer.tla`.

  Plan, with the reasons:
  - [x] (1e2588d) `StreamBuffer.tla`: constants `NW`, `NC` with `Writers == 1..NW`, `Closers == 1..NC` (the
    abstraction's form, so the refinement maps writer i to writer i and `RefineWaitProof.tla` needs
    no bijection between two sets); `wpc`, `cpc` functions; `WriterStep(i)`, `CloserStep(c)`, weak
    fairness for each. The writers share `nextByte`: together they write the bytes `1..Bytes`, a
    chunk per write, in commit order (as the abstraction's shared `w`), so `Fifo` and the
    invariants keep their meaning. A writer is done once all bytes are written by anyone.
  - [x] (1e2588d, f960d35) Every existing configuration with `NW = 1`, `NC = 1`: the state counts must stay as they
    are (a check that the change is a pure generalization); new models: two writers, two closers,
    both, for `read()`, records and `waitForAtLeast`; the older code's models with two writers
    where that shows something new (e.g. F149, a write racing a close, with two writers).
    Result (2026-11-14): check.sh, all 45 earlier models with the same outcome, every clean one
    with the same state count (a model that finds a violation stops at a count that depends on
    TLC's worker order). New, clean with liveness: `Writers2Condition2`, `Closers2Condition2`,
    `Writers2Records2`, `Writers2Mixed2` (two writers, two closers), `Writers2WaitChecked2`,
    `Writers2WaitAndRead2`, `ForeverWriters2Mixed2`; probes `Writers2Reached2`,
    `Closers2Reached2` (two writers, two closers signal at once) violated. No older code gets a new
    defect with two writers that one writer does not show already: the defects of F149 and F278
    are in the one-writer models.
  - [ ] `StreamBufferForever.tla`, `TraceStreamBuffer.tla` (`StepOf` and the observations per
    writer and closer; the trace's thread names `w1`.., `c1`.. map to the model's ids) and A6:
    `TraceScenario` and `TraceGenerator` with several writers and closers; `trace.sh` and its
    controls on the new traces.
  - [ ] (TLC part 4f37431: `RefineWaitWriters2Mixed2`, `RefineWaitWriters2WaitChecked2`,
    `RefineRecordsWriters2Records2` hold) Refinements: `RefineWait.tla` and `RefineRecords.tla` map `wpc[i]` to the abstraction's
    writer i (no `1..1` any more); `RefineCounters.tla` stays for one writer (its abstraction has
    one; it assumes `NW = 1`). `RefineWaitProof.tla`: the writer and closer lemmas per i and c, the
    detailed invariant for several writers; tlapm on all modules (proof.sh) on a rented machine.
  - [ ] A18 with two writers or two closers in the smallest scenario, if it fits (rented machine).
  - [ ] README, CHANGELOG, CLAUDE.md, `VERIFICATION-ASSUMPTIONS.md` (the rows that say "one writer
    and one closer"), the table above.

- **Spurious wake-ups — open limits** (model and proofs since #231, `src/test/tla/README.md`,
  "Spurious wake-ups"): `FairRole` is TLC-checked only without spurious wake-ups
  (`WaitForeverMeasure2`); the probe `SpuriousReached2` covers one configuration; the 4-core CI
  time of `check.sh` is an estimate until the first scheduled run.

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

- **Verification roadmap 2026-11, second part — packages A15–A19 (planned 2026-11-13).** From an
  external review that compared the verification with seL4's (abstract spec, executable spec, code,
  binary, each step proved, and a published list of assumptions). Checked against this repo:
  - **Done already:** the semaphore race the review found (F280, PR #228); DRF ⇒ sequential
    consistency (A4, README "Data-Race Freedom", with the machine-checked theorem); a field table
    of the lock discipline (README); the `safeWrite` array contract; the model invariants it
    proposes (`Fifo`, `AvailLinearizable`, `RecordsWhole`, `NoWriteAfterEof`, proved for any number
    of threads in the abstractions and carried to the detailed model by `RefineWaitProof.tla`).
  - **Done in this part:** A16 and A17 (PR #233, 2026-11-14): `VERIFICATION-ASSUMPTIONS.md` with
    every result as a row and the run manifests of the formal jobs; the lock discipline checked on
    the bytecode for every execution (`drf/LockDisciplineBytecodeTest`).
  - **Not taken:** an Isabelle/JMM proof of the wake-up protocol. It uses only synchronization
    actions (volatile `availableBytes`/`streamClosed`, `AtomicInteger waitingReaders`, the locks,
    `await`/`signalAll`), which the JMM puts in one total order consistent with program order (JLS
    §17.4.4), exactly what the TLA+ model assumes. The plain accesses are checked by A17;
    what is left is the code-to-model link (A18); an Isabelle project would mostly re-prove that reduction.
    Source-to-bytecode correctness: javac and the JVM stay trusted (A16 lists them).
  - **The gaps left:** no formal job gates a release (they run scheduled only); code and model are
    linked by 990 recorded runs (A6), not by every interleaving; liveness of the detailed model and
    the instance methods for any number of threads.
  Order: A18 (branch `feat/a18-jpf-traces`); A19 and A9 only if wanted afterwards. A15 last, once
  every other item of the table above is done (owner, 2026-11-13). Run with `/loop` and the prompt
  in "Run prompts" below.

  - **A15 — Proofs as a release gate (1–2 days; last, see the table).** `formal-verification.yml` gets a `workflow_call`
    trigger; `publish.yml` calls it for a `v*` tag and its deploy job needs it (no new workflow
    file). Done when a release of a commit without green formal jobs is impossible. Cost: about 2 h
    more per release. Changes the release process: the owner confirms before it is merged.
  - **A16 and A17 — open remnants.** The manifests' first run: the formal jobs other than ESC and
    RAC run weekly, so the first scheduled run after #233 (Monday 04:17 UTC) writes them; until
    then "every row has a run with a SHA" is open. A17's known limits (reviews 2026-11-13, not
    reachable by the code today): a guarded reference used after the lock is released, calls
    through a supertype, a static `@GuardedBy` method (matched by the lock's name), a method
    reference to an accessor, a method named like a guarded field in a method reference.
  - **A18 — Every interleaving of the code is a run of the model, for small scenarios (1–2
    weeks).** JPF enumerates all interleavings of the real bytecode for the scenarios of
    `src/test/jpf/`; a JPF listener writes each path as a trace in the format of A6, and
    `trace.sh` checks all of them against `TraceStreamBuffer.tla`. Done when, for those scenarios,
    every bytecode execution is accepted and the A6 negative controls still reject. Risk: JPF's
    state counts (`TwoReaders.jpf` 2.3 million states) — start with the smallest scenarios,
    time-box, and keep the bounded result if the larger ones do not fit.

    Plan (branch `feat/a18-jpf-traces`, started 2026-11-14), with the reasons:
    - [x] Spike first (the gate of the package): JPF explores the instrumented class of A6 (the
      class files `TracingClassLoader` writes, dumped to a directory, with `TraceRecorder`
      compiled at `--release 8`) in a harness of the A6 format (threads `w`, `c`, `r1`...), and
      every path that ends prints its events. Measure the number of paths and traces for the
      smallest scenario (one 1-byte write, a close, one `read()` reader), time-boxed. Why a gate:
      with the trace in the program's state JPF can match no states, so it enumerates every order
      of the logged accesses; for three threads of about ten accesses each that can be up to
      ~10^10 orders, fewer through the locks. If that is too many, the per-trace check of
      `trace.sh` does not scale, and the package needs another design (below).
      **Result (2026-11-14, local, Docker, jpf-core `e61e396`):** the pipeline works
      (`TracedClassDump`, `JpfTraceHarness` in `src/test/jpf/trace/`, `JpfTraceImport`). For the
      smallest scenario (one 1-byte write, a closer of its own, one `read()` reader) JPF printed
      18,630 traces in the 20-minute time-box without finishing, 2,870 of them distinct; a sample of
      300 distinct ones: all accepted by `trace.sh` (1.7 s each). Without a recording (so JPF can
      match states) it did not finish in 30 minutes either: the tracer's global lock adds a
      scheduling point before every logged access (the same three threads on the plain class,
      `WriteClose.jpf`, take 196,000 states and 1.5 minutes). So "every interleaving" is out of
      reach in this design, even for the smallest A6 scenario; the owner decides how to go on
      (options in the next steps).
    - [x] The owner's choice: a tracer for JPF without a lock of its own (an atomic block per
      access, one `Thread.yield()` before it as the access's scheduling point,
      `src/test/jpf/trace/.../TraceRecorder.java`). Result (2026-11-14): the state graph is small
      now and JPF finishes it, no errors: with the close after the writes 104,712 states in 41 s,
      with the close at any point 617,544 states in 4:21 min. Enumerating the traces still does not
      finish: 61,220 printed in 15 minutes, 10,718 distinct (the paths of a small graph are still
      exponentially many). So per-trace checking stays bounded; a complete check has to work on
      the graph.
    - [x] The owner's choice: a check on the graph. A probe first (2026-11-14): the trace model
      runs into dead branches on accepted traces (TLC with a deadlock check and a stutter at the
      end: three of three accepted traces deadlock after 17 states). Before each line the thread
      may take up to K silent model steps, and a wrong choice dies only later, so the sufficient
      condition "every product state can consume every edge" would raise false alarms; an exact
      check against this nondeterministic model is a language inclusion (a subset construction
      over the model's states).
    - Owner (2026-11-14): close to 100 % proven software; heavy computation on a rented machine
      (the owner's private notes), only minimal examples in GitHub Actions; a redesign that
      saves time is welcome if the proof stays as strong. The design that gives that:
      **one marker per model step.** The instrumentation logs exactly one event at the code site of
      each action of `StreamBuffer.tla` (plus the observations it has today), so the model replays
      a trace deterministically, without silent steps. Then:
      1. JPF exports its state graph (a listener; the events at the edges), with state matching;
      2. a tool removes the edges without an event and minimizes the graph to a deterministic
         automaton over the events (only the language of the event sequences matters);
      3. TLC checks the product of that automaton and the replaying model completely; since the
         replay is deterministic, "every edge can be consumed in every reachable product state"
         is exactly "every interleaving of the code is a run of the model", with no false alarms.
      A6 gets faster on the way (no search over silent steps).
    - [x] Gate 2: the size of the minimized automaton for the smallest scenario (the graph export,
      the minimization); if it is small, the design carries. Result (2026-11-14; `GraphExport`, a
      JPF listener, and `graphmin.py` in `src/test/jpf/trace/`): close after the writes, 104,713
      JPF states -> 1,839 deterministic -> **375 minimal**, 52 distinct events; close at any point,
      617,545 -> 5,471 -> **1,402 minimal**, 57 events; seconds each.
    - Decision (2026-11-14), with the reason: the automaton is small enough for an exact check that
      keeps A6's trace model unchanged, so the markers (a table from every model action to its
      code site, a new replay model) are not needed. Instead: TLC builds the product of the
      automaton and `TraceStreamBuffer.tla`'s acceptance (`TraceGraph.tla` extends it and uses its
      observation predicates as they are; "the next line" becomes "an edge of the automaton"), and a
      subset construction over the dumped product follows, for every event sequence of the
      automaton, the set of model states consistent with it; an empty set is a counterexample
      (the sequence). Exact: no false alarms, no path left out; the acceptance relation is the one
      A6 validated.
    - [x] The JPF tracer gives each event its full A6 line (the ordinal of a harness event, which
      depends on the path, counted per thread); `graphmin.py` writes the minimal automaton as a TLA+
      module.
    - [x] `TraceGraph.tla` (the product), TLC with a state dump, and the subset check; a positive
      run on both small scenarios. Close after the writes (2026-11-14): automaton 373 states and
      653 edges, product 82,944 states (TLC 30 s), 2,140 subsets: **every word is a run of the
      model** (`graphcheck.py`). The tracer emits only from the start on (the constructor's
      accesses in `main` are no part of a trace, as in A6).
      Close at any point: automaton 1,451 states and 3,318 edges, product 542,666 states (TLC 34
      min, dump 409 MB), 10,581 subsets: **every word is a run of the model** as well.
    - [x] Negative controls: a mutated model (the writer never signals), a corrupted automaton (a
      returned byte changed), a mutated class: each must give a rejected sequence. Done for the
      first two (2026-11-14): the mutant rejected after 19 events (with `Spurious = 0`, which could
      stand in for the signal), the corrupted byte after 14; the current model with `Spurious = 0`
      accepted. A mutated class (`TracedClassDump ... no-decrement`: `readSingleByte` no longer
      lowers `availableBytes`): rejected after 22 events (JPF itself also reports the
      `NoSuchElementException` that follows).
    - [ ] Scenarios: the smallest in CI (minutes), the larger ones on a rented machine; README,
      CHANGELOG, CLAUDE.md, `VERIFICATION-ASSUMPTIONS.md` (a row for A18). CI: the step in the
      `jpf-interleavings` job runs S1A with its controls (about 2 minutes locally). The rented run
      (2026-11-14, a rented 32-core machine, `check-graph.sh` with controls, 4 h per scenario), so far:
      every word accepted for S1A (1 byte, a `read()` reader, close after the writes: 104,712 JPF
      states, automaton 373), S1N (close at any point: 617,544, 1,451), S4N (one 2-byte write, a
      record reader: 601,656, 1,451), S7N (`waitForAtLeast(2)` alone, two 1-byte writes:
      1,036,384, 1,555); the controls rejected where they hit. Out of the time-box: S2N, S5N (in
      the TLC product: automata of 3,790 and 2,674 states, TLC's dump is written by one thread),
      S3A, S3N (two `read()` readers: still in JPF after 4 h). S6A (a waiter next to a reader)
      reached 15,081,689 JPF states, automaton 5,102.
      The class control first missed S4N: it changed `readSingleByte` only, which a record reader
      does not run; now it changes both read paths, and it rejects on a record scenario (S4A, a
      2-byte write, close after: all three controls rejected, 147 s locally).
    - [ ] If the count fits: an importer writes each distinct trace as an A6 module
      (`TraceGenerator.write`), `trace.sh` checks all of them, `trace-controls.sh` still rejects;
      then the next larger scenarios, as far as the time-box allows.
    - [ ] If it does not fit: the alternative is to check JPF's state graph (with state matching,
      each edge labelled with its logged access) against the model as a whole, a simulation
      (every edge of the graph, some placement of the model's steps), not trace by trace; that
      needs a subset construction over the model's states and is a larger package. Then the owner
      decides whether it is worth it; the spike's numbers go into the table.
    - [ ] CI (if it fits): in the `jpf-interleavings` job (JDK 11, jpf-core already built), plus
      TLC; README, CHANGELOG, CLAUDE.md, `VERIFICATION-ASSUMPTIONS.md` (a row for A18).
  - **A19 — Liveness of the detailed model for any number of readers (optional, weeks).** TLAPS,
    on the pattern of `StreamBufferWaitForeverLiveProof.tla` (a measure per thread, fairness by
    role), for `StreamBuffer.tla` directly, or a refinement that carries fairness. Done when the
    liveness of the detailed model no longer rests on TLC's bounded models.
  - A9 (below) stays the long-term package for the instance methods; first extract a sequential
    core (trim, read, write as a pure function on the deque), then OpenJML or KeY.

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

### Verification roadmap A18

Start: `/loop Work on the verification roadmap A18 as described in TODO.md, section "Run prompts" / "Verification roadmap A18", re-read on every iteration.`

````text
Work on the verification roadmap A18 of streambuffer (TODO.md, "Verification roadmap 2026-11,
second part") fully automatically and as independently as possible (A16 and A17 are done, #233).
A15 is not part of this run: it comes after every other open item (TODO.md, the table). It
may take longer than one session; there is no deadline. Work locally (TLC, Apalache and
tlapm as in src/test/tla/README.md; JPF in Docker, eclipse-temurin:11-jdk + apt-get install git,
MSYS_NO_PATHCONV=1; OpenJML RAC in WSL as the formal-verification.yml job does it; Maven with
JAVA_HOME=/c/Users/berna/AppData/Local/Programs/jdk-25.0.4.1+1). A rented instance (see
../workspacePrivate/remote.md) is allowed for up to about 10-15 EUR in total: enter it in
remote.md while it runs, delete it and sweep when done. Web search and Chrome are allowed.

Procedure:
1. Every iteration: in the real clone, switch to the branch feat/a18-jpf-traces (create it from
   main if it does not exist), write the package's plan as checkbox steps under it in TODO.md with
   the reason for every decision, do the next open step, test it, tick it with its commit, add
   steps found on the way. One branch and PR.
2. A change of production code only if a package finds a defect (then a bug-hunt finding in
   BUGHUNT-FOUND.md, a test that is red before and green after, and the fix). Negative controls are
   mandatory for every check: a deliberately broken input must make it fail.
3. Before every push: mvn verify, PIT (100 % threshold) if test or main code changed, and the
   OpenJML RAC job locally if StreamBuffer.java changed. Results with numbers in the READMEs;
   CHANGELOG.md, CLAUDE.md, TODO.md updated. CI: only the existing workflow files.
4. At the end of each package: review of the branch by an agent. Only regressions against main,
   moderate or high bugs in the branch's own changes, and wrong statements in the docs block the
   push; the rest goes as one line under the package in TODO.md. At most one more round. Then one
   push, open the PR (do not merge, no dispatch runs), watch CI; on a CI error of my own: cancel the
   run, commit the fix, push. Check the CodeRabbit review and work off still-valid findings.
5. Rules: no questions (ask only for something that is the owner's to decide, such as more budget
   or a release-process change). No force-push, no pkill -f (kill by PID), delete only with
   Remove-Item, no private data to external services. Remove the done steps of a package from
   TODO.md when its PR is merged; only the result stays.
6. When a package's PR is open and CI is green: a short summary in German, then go on with the next
   package; after A18 (or when A18 is time-boxed out): a German summary of all packages, then end
   the loop.
````
