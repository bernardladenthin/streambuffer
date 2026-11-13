<!--
SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# Verification: what is shown, by what, under which assumptions

Roadmap A16. Every verification result of this repository has one row in the table below. A row
says what property is shown, by which tool, how far the result reaches (bounded or unbounded; a
model, an abstraction, or the code itself), what it assumes, and which job checks it. The READMEs
name the row of each of their claims as `[V<n>]`. `VerificationAssumptionsTest` (in `mvn test`)
fails when a README names a row that does not exist or a row is named nowhere.

The sections after the table list what every row takes for granted (the trusted base), what a
caller must do for the results to apply (the caller contracts), and what no row covers.

## The results

| Id | Property | Tool | Scope | Assumes | CI job (workflow) |
|---|---|---|---|---|---|
| V1 | The 17 static methods of the sequential core (2 validators, 15 pure helpers) meet their full functional contracts | OpenJML 21.0.29 ESC, proved with Z3 and again with cvc5 | the code, every input (unbounded) | the JML semantics of OpenJML; `code_java_math` where the code relies on wrap-around (2 methods); one assumed contract (`newInvalidOffsetOrLengthToWriteException`); the bundled JDK specs | `openjml-esc` (formal-verification) |
| V2 | Every JML contract (class invariants, the read/write guarantees, the statistics) holds at runtime during the whole test suite | OpenJML 21.0.29 RAC | the code, the executions of the test suite | contracts reference only monotone state, so they hold under concurrency; RAC's runtime classes | `openjml-rac` (formal-verification) |
| V3 | The lock discipline: every access to a `@GuardedBy` field and every call of a `@GuardedBy` method holds its lock on every path; no field is plain without `@GuardedBy`; the README's field table lists every field with its kind | ASM 9.9.1 data flow over the bytecode (`drf/LockDisciplineBytecodeTest`); Error Prone's `GuardedBy` check on the source at compile time | the code's class files, every execution | the class files tested are those shipped (same build); the monitor of a lock is the field the operand was loaded from | `test`, `build` (publish) |
| V4 | No data race in the scenarios run (happens-before of the JMM) | vmlens 1.2.28 | the code, the scenarios and their interleavings (one stops at vmlens' limit) | the JDK classes behave as specified | `vmlens` (publish) |
| V5 | Data-race freedom implies sequentially consistent executions, so the interleaving-based results (V6, V7, V8, V4) hold under the Java memory model | the theorem of JLS §17.4.5, machine-checked by Aspinall & Ševčík (TPHOLs 2007) and Lochbihler (TOPLAS 2014) | every execution of a correctly synchronized program | V3 for the lock-guarded fields, the total order of synchronization actions (JLS §17.4.4) for the volatile and atomic ones | none (an argument from V3 and V4) |
| V6 | No deadlock, no lost wake-up, no uncaught exception, and the bytes each reader gets, in the 7 harnesses (a writer and a reader, a racing close, two readers, two record readers, a wait next to a reader, a wait next to a 2-byte write, a trim signal writing back) | Java PathFinder (jpf-core `e61e396`, an `AtomicLong` model patch) | the code's bytecode under JPF, every interleaving of the harnesses (bounded) | JPF's models of the JDK classes; the `AtomicLong` patch | `jpf-interleavings` (formal-verification) |
| V7 | The non-blocking subset (`write`, `available`, `close`, `isClosed`) is linearizable; the trim keeps it so | Lincheck 3.7 | the code, the scenarios Lincheck generates | Lincheck's model of the JVM | `test` (publish) |
| V8 | The concurrent outcomes of the jcstress tests are among the allowed ones | jcstress 0.16 | the code on the JVM and hardware it runs on (x86, arm64) | the hardware and JIT of the runner | `test` (quick), `jcstress-default`, `arm64-jcstress-benchmark` (formal-verification) |
| V9 | No virtual thread is pinned inside `StreamBuffer` | JFR `jdk.VirtualThreadPinned` | the code, 64 virtual readers and 4 writers | JDK 24+ (on 21-23 a report only) | `test` (publish), `virtual-threads-jdk21` (formal-verification) |
| V10 | The protocol model (`StreamBuffer.tla`) is safe (`NoEmptyTake`, `Fifo`, `AvailLinearizable`, `RecordsWhole`, `WaitEnoughOrClosed`, `NoWriteAfterEof`, `EofOnlyWhenClosedAndEmpty`) and live (every call returns), also with spurious wake-ups and with threads that call forever; the older code fails with its defects | TLC 1.7.4 (`check.sh`) | the detailed model, up to 3 readers and a few bytes (bounded) | weak fairness per thread (no lock fairness); finitely many spurious wake-ups for liveness; one writer and one closer; no trim | `tla-model` (formal-verification) |
| V11 | The safety invariants of the three counter abstractions are inductive, and the detailed model refines them in its bounded configurations | Apalache 0.63.0 and TLC 1.7.4 (`inductive.sh`) | the abstractions, fixed thread counts with any bytes, sizes, requests, calls and budget of spurious wake-ups | the abstractions' slice of the protocol (README of `src/test/tla`) | `tla-model` (formal-verification) |
| V12 | The safety invariants of the three counter abstractions hold for any number of threads, writers and closers | TLAPS, tlapm `ff40755` (`proof.sh`) | the abstractions, unbounded | the abstractions build in the current code where their slice does not vary it | `tlaps-proofs` (formal-verification) |
| V13 | The detailed model refines `StreamBufferWait.tla` for any set of readers, so its safety carries over | TLAPS (`RefineWaitProof.tla`) | the detailed model, any number of readers | the current code's configuration; the refinement is of the specifications without fairness | `tlaps-proofs` (formal-verification) |
| V14 | With a closer, every call of `StreamBufferWait.tla` returns and all finish, for any number of threads | TLAPS (`StreamBufferWaitLiveProof.tla`) | the abstraction, unbounded | weak fairness of `Next`; finitely many spurious wake-ups | `tlaps-proofs` (formal-verification) |
| V15 | With a closer, every call returns although threads call forever, for any number of threads | TLAPS (`StreamBufferWaitForeverLiveProof.tla`) | the abstraction, unbounded | fairness by role (`FairRole`; that it follows from fairness per thread is argued and TLC-checked in bounded models, V10); a finite stream; finitely many spurious wake-ups | `tlaps-proofs` (formal-verification) |
| V16 | The "max 1 permit" release of the external signals (F280) keeps at most one permit and loses no signal | TLC 1.7.4 (bounded) and TLAPS (any number of signalers) | the model `StreamBufferSignal.tla` | the model of `releaseMaxOnePermit` matches the code (changed together) | `tla-model`, `tlaps-proofs` (formal-verification) |
| V17 | Recorded runs of the code are runs of the model; models of older code, a mutated model and corrupted runs are rejected | TLC 1.7.4 (`trace.sh`, `trace-controls.sh`) over the instrumented class (A6) | the code's runs that were recorded (990 locally, 33 in CI) | the instrumentation logs every access to shared state in order; the trace lock serializes the traced accesses | `tla-model` (formal-verification) |
| V18 | The functional behaviour of the API (reads, writes, trim, signals, statistics), with mutation testing at 100 % | JUnit 6, jqwik 1.9.3 properties, PIT | the code, the tests | -- | `test`, `report` (PIT) (publish) |

## The runs: which revision a result is for

Every job of `formal-verification.yml` writes a manifest when its checks pass
(`src/test/verification/manifest.sh`) and uploads it as the artifact `manifest-<job>`: the commit
(`GITHUB_SHA`) and run it checked, the rows it covers, the tools with their version and SHA-256,
and its counts (proofs of ESC with each solver, the tests under RAC, the states of each JPF
harness, the TLC models passed, including the two runs of the mutant, the traces accepted and the
controls passed, the Apalache checks, the TLAPS modules and obligations, the jcstress results).
The rows checked by jobs of `publish.yml` (V3, V4, V7, V9, V18) are tied to the Publish run of
the same commit. ESC and RAC (V1, V2) run on every push and pull request; the other formal jobs
weekly and on dispatch (`arm64-jcstress-benchmark` on dispatch only), so their latest result is the
manifest of the latest scheduled run, not necessarily of the latest commit. A15 (a release gate,
`TODO.md`) would tie each release to its own run.

## The trusted base

What every row takes for granted:

- **The JVM and its JIT, and javac.** The rows on the code (V1-V9, V17, V18) check the source or the
  bytecode javac produced; that the JVM runs that bytecode as the JLS says is assumed.
- **The JDK classes** the buffer builds on: `ReentrantLock`, `Condition` and the AQS behind them,
  `Semaphore`, `ArrayDeque`, `CopyOnWriteArrayList`, `AtomicInteger`, `AtomicLong`. The TLA+ models
  (V10-V16) assume their documented behaviour (a lock is exclusive, `await` releases it,
  `signalAll` wakes every waiter, a spurious wake-up may happen).
- **The tools themselves**, pinned by version, commit or SHA-256 in `formal-verification.yml`: OpenJML
  with Z3 and cvc5, TLC, Apalache, tlapm with its backends (Zenon, Isabelle, the SMT solvers), JPF.

## The caller contracts

What a caller must do for the results to apply:

- **A written array** is kept without a copy while `safeWrite` is off: changing it afterwards races
  with the readers (README, "Safe Write").
- **The external signals** (`addSignal`, the trim signals) are semaphores with at most one permit
  each; a caller's own `release()` breaks that bound, and an override of `release()` that throws is
  handled but not modelled beyond the throw (README, "Signal/Slot Notifications"; V16).
- **The trim signals** run inside the trim, under `bufferLock`; a signal that writes back to the
  buffer is allowed (JPF `TrimReentrancy`, V6), one that blocks on another thread holding the lock is
  not.

## What no row covers

- `waitForAtLeast` with a timeout (`awaitNanos`) and interrupts: in no model, not traced.
- Trim in the TLA+ models: it keeps the bytes, their order and `availableBytes`, which is why the
  models leave it out; JPF (V6), vmlens (V4) and the tests (V18) cover it.
- Several writers and closers in the detailed TLA+ model (the abstractions have them, V11-V15).
- Liveness of the detailed model for any number of readers (bounded only, V10), and the instance
  methods' functional contracts beyond runtime checking (V2).
- Infinitely many spurious wake-ups without progress: liveness assumes finitely many (V10, V14,
  V15).

The open work on these is in `TODO.md` ("Open verification items").
