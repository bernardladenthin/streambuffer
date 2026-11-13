<!--
SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# TLA+ model of the wait/wake-up/close protocol

`StreamBuffer.tla` models how `StreamBuffer` threads write, close, wait for data and read it, and
TLC checks it over every interleaving of a small configuration (TODO roadmap A5). Where the JPF
harnesses run the real bytecode for one fixed scenario, the model states the protocol on its own and
checks safety **and liveness** (every reader eventually returns) for each configuration. It is not
part of the Maven build and never touches the shipped jar.

## What is modeled

- **Threads:** a writer of `Bytes` bytes in writes of `ChunkLen` bytes (the last one shorter), a
  closer, and the threads in `Readers`. A reader reads until a call returns -1: `read()` if it is in
  `ByteReaders`, `read(b, 0, ReadLen)` otherwise. A thread in `WaitCallers` calls
  `waitForAtLeast(ReadLen)` once instead and keeps what it returns.
- **State:** the FIFO as a sequence of entries, one per write (`buf`), with the read position in the
  head entry (`pos`, `positionAtCurrentBufferEntry`); `availableBytes` as its own variable (`avail`,
  the count every lock-free reader sees), the bytes written and committed, `streamClosed`, and the
  waiting machinery.
- **Atomicity:** one step is one atomic action; each lock-free volatile read or write is a step of
  its own, and both locks are variables (`bl` for `bufferLock`, `wl` for `waitLock`). A copy under
  `bufferLock` takes one step per FIFO entry (at most the rest of the head entry, one turn of the
  copy loop of `readIntoArray`), so a lock-free reader of `avail` can watch it; a
  writer's signal cannot come between a reader's increment of `waitingReaders` and its check under
  `waitLock`.
- **Code versions**, chosen by constants; the current code is `Protocol = "condition"`,
  `ReCheck`, `AtomicRead`, `CountOnce`, `CheckedReturn`:
  - `Protocol` — `"condition"`: the wait since bug-hunt finding F278 (a `Condition` on `waitLock`
    with `signalAll`, the `waitingReaders` count that lets a write skip the lock while nobody waits);
    `"semaphore"`: the wait before it (a `Semaphore` released only while it has no permit).
  - `ReCheck` — the re-check of `availableBytes` under `bufferLock` before taking bytes (since F278;
    F278 had both causes at once, `ReCheck` separates them).
  - `AtomicRead` — `read(b, off, len)` waits for all `len` bytes and takes them in one lock hold
    (since #212); without it the read took the first byte, released the lock and waited for the rest.
  - `CountOnce` — `availableBytes` lowered once per read after the copy (since F279), not per entry.
  - `CheckedReturn` — `waitForAtLeast`'s waiting branch returns the count it checked (since
    2026-11-12); without it, it read `availableBytes` again for the result.
- **Fairness:** weak for every thread: a thread that can go on all the time eventually does (the
  scheduler runs a runnable thread). No lock fairness: a thread that keeps finding a lock taken may
  never get it, as the JDK's monitor and `ReentrantLock(false)` allow. Until 2026-11-13 the readers
  had strong fairness (fair locks); every model of the current code checks with weak fairness too
  (see "Liveness with threads that call forever").

## Properties

| Property | Kind | Meaning |
|---|---|---|
| `TypeOK` | invariant | every variable in its domain |
| `NoEmptyTake` | invariant | no reader takes from an empty FIFO (`NoSuchElementException`, F278) |
| `Fifo` | invariant | `written = taken \o InFlight \o buf`: nothing lost, nothing twice |
| `AvailLinearizable` | invariant | `availableBytes` is `written − committed`, or that minus the whole read in flight: a lock-free reader sees the count before or after a read, never from the middle of it (F279) |
| `ReaderOrder` | invariant | each reader gets the bytes in the order they were written |
| `RecordsWhole` | invariant | each read returns consecutive bytes, as many as it asked for, fewer only from a closed buffer; with readers of one size, a whole aligned record (#212) |
| `WaitEnoughOrClosed` | invariant | `waitForAtLeast(n)` returns fewer than `n` only for a closed buffer (its JML postcondition) |
| `NoWriteAfterEof` | invariant | no write returns normally after a reader reported the end (F149) |
| `EofOnlyWhenClosedAndEmpty` | invariant | only a closed buffer reports the end, and it stays empty |
| `AllReadersFinish` | liveness | every read and every `waitForAtLeast` call returns, from every wait (no lost wake-up, F278) |
| `EveryCallReturns` | liveness | `StreamBufferForever.tla`: with every thread calling again forever, every call returns |

## Models and results

`check.sh` runs every model and compares it with its **expected** outcome: the 16 models below
(last run 2026-11-13, TLC v1.7.4, about 90 s) and the 16 of "Liveness with threads that call
forever", 32 in all, 594 s on 4 cores. Writes are single bytes unless the row says otherwise:

| Model | Code | Reads | Threads | Expected and found |
|---|---|---|---|---|
| `Condition1` | since F278 | `read()` | 1 | no error, 570 states |
| `Condition2` | since F278 | `read()` | 2 | no error, 11,239 states |
| `Condition3` | since F278 | `read()` | 3 | no error, 199,810 states |
| `Records2` | since F279 | `read(b, 0, 2)`, 4 bytes | 2 | no error, 21,657 states |
| `Semaphore1` | before F278 | `read()` | 1 | no error (one reader was always fine) |
| `Semaphore2` | before F278 | `read()` | 2 | `NoEmptyTake` violated: both readers saw the byte, the second found the FIFO empty under the lock |
| `SemaphoreReCheck2` | semaphore, but with the re-check | `read()` | 2 | deadlock: both readers wait for a permit, the close releases one, the other reader waits forever |
| `ConditionNoReCheck2` | condition, without the re-check | `read()` | 2 | `NoEmptyTake` violated: the re-check is needed with the condition too |
| `RecordsTwoPhase2` | two-phase read, before #212 | `read(b, 0, 2)` | 2 | `RecordsWhole` violated: a reader got `<<1, 3>>`, the same torn record vmlens found |
| `RecordsCountPerEntry2` | count per entry, before F279 | `read(b, 0, 2)` | 2 | `AvailLinearizable` violated: the count dropped by one in the middle of a read |
| `Chunks2` | since F279 | `read(b, 0, 2)`; writes of 3 and 1 bytes | 2 | no error, 14,263 states: records span two entries and end inside one |
| `Mixed2` | since F279 | `read()` and `read(b, 0, 2)`; writes of 2 and 1 bytes | 2 | no error, 12,749 states |
| `WaitAndRead2` | since F279 | `waitForAtLeast(2)` and `read()`; 1 byte | 2 | no error, 1,796 states (the JPF `WaitAndRead` scenario, liveness included) |
| `SemaphoreWaitAndRead2` | before F278 | `waitForAtLeast(2)` and `read()`; 1 byte | 2 | deadlock: the wait took the only permit, the reader waits forever (F278) |
| `WaitSnapshot2` | before `CheckedReturn` | `waitForAtLeast(2)` and `read()`; one 2-byte write | 2 | `WaitEnoughOrClosed` violated: the wait saw 2 bytes under `waitLock`, the reader took one, the wait returned 1 on an open buffer |
| `WaitChecked2` | current | the same | 2 | no error, 2,432 states |

`WaitSnapshot2` found a real defect (2026-11-11): the waiting branch of `waitForAtLeast` read
`availableBytes` a second time for its result, after the loop condition had seen enough bytes, so
`waitForAtLeast(2)` could return 1 on an open buffer, against its own JML postcondition. The JPF
harness `WaitSnapshot.jpf` confirmed it on the bytecode (`src/test/jpf/README.md`); since the fix
(`CheckedReturn`) the call returns the checked count, as its fast path did.

A mutation check on 2026-11-11 (not committed): with `waitingReaders` never counted, every signal is
skipped and TLC reports a deadlock in `Condition2`, `Records2`, `Chunks2`, `Mixed2` and
`WaitAndRead2`, so the model does check the skip of the wait lock that the count allows. Probe
invariants that must fail (not committed) confirm the new models reach their cases: a partly read
head entry, a copy across two entries, completed reads of both sizes, `waitForAtLeast` parked and
returning through the waiting branch. Moving the FIFO from bytes to entries left the state counts of
the clean single-byte models unchanged.

## Unbounded safety: inductive invariants (roadmap A13)

TLC checks fixed constants, up to 3 readers and a few bytes. Counter abstractions with inductive
invariants remove those bounds. The most general one, `StreamBufferWait.tla`, has every thread make
any number of calls, each a `read(b, 0, K[r])` or a `waitForAtLeast(M[r])`, next to any numbers of
writers and closers; its liveness is proved too.

- **Apalache v0.63.0** (`inductive.sh`): fixed thread counts, with bytes, read sizes, requests and
  the budget of calls symbolic.
- **TLAPS** (`proof.sh`): any number of threads, writers and closers.
- **TLC refinement checks** tie each abstraction to the detailed model; for `StreamBufferWait.tla`
  a TLAPS proof does so for any number of readers (`RefineWaitProof.tla`, in `proof.sh`).

**What this does and does not show.** The unbounded results hold for the abstractions, and the
safety results carry over to `StreamBuffer.tla` with the current code: `RefineWaitProof.tla` proves
with TLAPS that it refines `StreamBufferWait.tla` for **any** set of readers (see "The refinement"
below). The liveness does not carry over: the refinement is of the specifications without
fairness, and weak fairness of the abstraction's `Next` does not follow from the detailed model's
fairness by this proof, so the detailed model's liveness rests on TLC's bounded checks. For
`StreamBufferCounters.tla` and `StreamBufferRecords.tla` the link is TLC's refinement check of the
bounded configurations (2 and 3 readers, up to 4 bytes); `StreamBufferWait.tla` covers what they
check about the current code, except the alignment of records, which it states only while every
read size is the record size.

The abstractions build in the current code where the slice does not vary it: the count lowered once
per read (F279), and the re-check everywhere but in the `read()` abstraction. `AvailLinearizable` is
therefore true by construction there, and the F279 defect is only shown by the bounded model
`RecordsCountPerEntry2`.

| Abstraction | Slice | Apalache (fixed N) | TLAPS (any N) | Refinement (TLC) | Older code reaches a violation |
|---|---|---|---|---|---|
| `StreamBufferCounters.tla` | `read()`, single-byte writes | N = 2, 3, 4, 8, 12; any bytes (`IndInv`) | `SafeInv`, 216 obligations | `Condition2`, `Condition3` | the empty take without the re-check (F278), 10 steps |
| `StreamBufferRecords.tla` | `read(b, 0, K)`, several writers and closers, any chunking | 2, 3, 4 readers with 2 writers and 2 closers, 2 readers with 3 and 3; any K and bytes (`SafeModInv`) | `SafeInv`, any readers, writers and closers, 488 obligations | `Records2`, `Chunks2` | a torn record with the two-phase read (#212), 6 steps |
| `StreamBufferWait.tla` | every thread any number of calls, each `read(b, 0, K[r])` (`K[r] = 1` is `read()`) or `waitForAtLeast(M[r])`; several writers and closers, any chunking | 2, 3, 4 threads with 2 writers and 2 closers, 2 threads with 3 and 3; any read sizes, requests, bytes and calls (`SafeModInv`) | `SafeInv`, any threads, writers and closers, 577 obligations | TLAPS for any number of readers (`RefineWaitProof.tla`, 2,656 obligations); TLC in all seven configurations of the current code (`Condition2`, `Condition3`, `Records2`, `Chunks2`, `Mixed2`, `WaitAndRead2`, `WaitChecked2`) | `waitForAtLeast(M[r]) < M[r]` on an open buffer before `CheckedReturn`, 11 steps |
| `StreamBufferWaitForeverLive.tla` | liveness with threads that call forever: with a closer, every call returns | TLC (`WaitForever*`, below) | `SpecRole => EveryCallReturns`, any threads, writers and closers: 633 + 1,322 obligations | as `StreamBufferWait.tla` | with an endless writer and no close a reader starves, also with fair locks |
| `StreamBufferWaitLive.tla` | liveness of `StreamBufferWait.tla`: with a closer, every call returns and all finish | 2 threads with 2 writers and 1 closer, 3 with 2 and 2: `LiveInv` inductive, `Pot` goes down with every step, a step until all are done | `FairSpec => <>AllDone`, any threads, writers and closers: 363 + 628 + 919 obligations | as `StreamBufferWait.tla` | without `ClosedNoPark` a state of `SafeInv` has no step |

**The abstractions.** The writer writes the bytes 1, 2, ... in order, and the FIFO hands them out
in order, so the byte sequences reduce to counts:
- `w` written, `t` committed, `hold[r]` copied in the current hold of `bufferLock`;
- for records (and the record readers next to the waiters), also `left[r]` (bytes still to copy)
  and the ghost `off`.

The records and wait abstractions have NW writers sharing the budget of `Bytes` bytes; a writer
that finds it used up is done. They have NC closers: `close()` sets `streamClosed` under
`bufferLock` and signals, and a second close does the same again. With `K = 1` the records
abstraction is the `read()` protocol, so `read()` with several writers and closers is covered
there; `StreamBufferCounters.tla` keeps one writer and one closer.

In `StreamBufferWait.tla` the threads are a constant set `Threads`, each with a read size `K[r]`
and a request `M[r]` of its own. A thread chooses, for every call anew, a read or a wait
(`op[r]`); when a call returns it makes the next one or stops. The threads share a budget of
`Calls0` further calls, which goes down by at least one per call (by any amount at a stop), so
every finite program fits: a reader that reads until -1 needs at most one call per byte and one
more. The refinement maps the budget to the bytes not yet taken plus one per thread not done.

Two simplifications, both weaker than the detailed model, so they over-approximate it:
- **Chunks:** a write puts 1 to the remaining bytes into one entry, and a copy step takes 1 to the
  bytes still to copy. This covers every chunking, and trim, which only merges entries.
- **Signals:** without a parked reader a signal does nothing and needs no lock, since the code
  skips it then. The records and wait abstractions have no `waitingReaders` count at all.

The bounded TLC models above show that each older code version fails.

**The invariants.** `SafeInv` is the safety properties plus what makes them inductive, each part
a named conjunct:
- **Safety properties:** `NoEmptyTake`, `AvailLinearizable`, `NoWriteAfterEof`,
  `EofOnlyWhenClosedAndEmpty`; `RecordsAligned` for records, `WaitEnoughOrClosed` for
  `waitForAtLeast` (what a thread's last wait returned), and in `StreamBufferWait.tla` also
  `WholeRead` (a read takes `K[r]` bytes, fewer only from a closed buffer).
- **Calls:** a wait never takes `bufferLock`, a read never returns through the waiting branch
  (`OpStates`).
- **Closers:** the buffer is closed once some closer has passed its close (`CloserInv`).
- **`bufferLock`:** held exactly by the thread deciding, copying or finishing.
- **Bytes in flight:** they are buffered (`BufNonNeg`), and a copy has the bytes it still copies.
- **Waiting:** `waitLock` and `parked` match the thread states.
- **End of stream:** a reader that sees it saw the buffer closed and empty, and no write follows a
  close.
- **Records:** `WholeRead` (each read takes a whole record, fewer only from a closed buffer) and
  `hold + left <= K`.

`IndInv` (in `read()`) adds the `waitingReaders` count. That count only decides whether a signal is
skipped, which is liveness, so `SafeInv` is inductive without it. That is the form the TLAPS proofs
use.

For records, `RecordsAligned` says that up to the close every commit is a whole record. It is stated
on the ghost `off` (the committed count modulo K), which advances linearly: `off + hold`, less K once
a record is full. The provers do not handle `%` with a symbolic divisor. That `off = t % K` is
checked by Apalache (`SafeModInv`, N up to 4) and by the refinement: the detailed model keeps the
same ghost (`toff`, advanced the same way, `off <- toff`), and its `TypeOK` says
`toff = Len(taken) % ReadLen`, which TLC checks in every model; not by TLAPS. In `StreamBufferWait.tla` the ghost counts modulo `RecLen`, and `RecordsAligned`
speaks only when every read size is `RecLen` (`Uniform`); `off = t % RecLen` holds while every read
size is at most `RecLen`, as in the detailed model (`RecLen <- ReadLen`).

**An Apalache pitfall: ranges that can be empty.** Apalache 0.63.0 rewrites a skolemizable
`\E c \in a..b : P` to a fresh constant `c` and asserts `a <= c` and `c <= b` as **global** facts
(`QuantRule.skolemExistsInRange`), not as part of the formula. When the range depends on the state
and is empty in some state, every execution through that state becomes unsatisfiable, even one that
takes another action there. The search then misses violations, and an inductive step skips
pre-states. With `\E c \in 1..(Bytes - w)` the step never saw `w = Bytes`. With
`\E k \in 1..left[r]` it never saw a state where no reader copies, since some thread then had to
have `left[r] >= 1`. The abstractions therefore use ranges that are never empty and filter inside:
`\E c \in 1..Bytes : c <= Bytes - w /\ ...` and `\E k \in 0..left[r] : k >= 1 /\ ...` (equivalent,
since `w` and `left[r]` are naturals), and `\E n \in 0..calls` for the budget. `inductive.sh` fails
on any other existential over a range. A range behind an operator is not safe either: with `NC = 0`
(`Closers == 1..NC` empty) the deadlock check `NoDeadlock` reported no error, although states with
every thread parked satisfy its init (a check of `FALSE` finds them). Negating
`\A c \in Closers : ...` in `AllDone` gives an existential over that empty range, the likely cause.
`inductive.sh` therefore also fails on a constant init without a writer or a closer. The
known-issues page of Apalache lists non-constant ranges as an encoding that fails with an error;
this path fails silently. Reported with a 15-line reproduction as
[apalache#3503](https://github.com/apalache-mc/apalache/issues/3503) (TODO.md, A13).

**Negative controls.** Each older code version reaches a violation of the **safety property
itself** in a bounded Apalache search from `Init`, with the symbolic constants left free. The steps
are in the table above. In the TLAPS proofs, assuming the older code makes obligations fail: without
the re-check, `Safety'` and `BufLock'` in `ReaderDecide`; with the two-phase read, `WholeRead'` and
`CurZero'`; without `CheckedReturn`, `OpStates'` in `ThreadTest` (the last two checked again
2026-11-12, with several closers and the calls abstraction). Those failures are in helper
conjuncts that encode the fix, which is why the bounded searches are the evidence. A wrong mapping
makes a refinement check fail (`avail + 1`, or `eof` left unmapped).

**Liveness** (`StreamBufferWaitLive.tla`, proof `StreamBufferWaitLiveProof.tla`). The theorem
`Liveness == FairSpec => <>AllDone`: with at least one closer and finitely many threads, every
behaviour of `StreamBufferWait.tla` with weak fairness of `Next` ends with every call returned and
every thread, writer and closer done. Weak fairness of `Next` as a whole only says that the system
does not halt while a step is possible; it assumes no fairness per thread or lock. The argument:
- **`Pot` goes down with every step.** `Pot` is a natural number: the bytes to write and to commit,
  the bytes buffered, the calls left, and a rank per thread (at most 10), writer and closer. Each
  loop of the protocol is paid for: a wake-up by the signal that caused it, a failed re-check under
  `bufferLock` by the commit that took the bytes, the next call by the budget. The thread part is
  the sum of 10 layers, layer k the number of threads of rank at least k, so the proof needs no sum
  over the threads, only cardinalities (`StreamBufferCountLemmas.tla`).
- **A step is possible until all are done** (`StreamBufferWaitEnabled.tla`). A lock holder can always
  go on, and no thread is parked once a closer is done (`ClosedNoPark`): that closer woke every
  parked thread after the close, and a thread that checks after the close does not park. For each
  kind of step a deterministic witness action shows `ENABLED <<Next>>_vars` (`ENABLEDaxioms`).
- **An induction over `Pot`** (WF1 and `NatInduction`, as in tlapm's `SimpleEventuallyInt`).

Apalache checks the same parts for fixed thread counts (`inductive.sh`). Its negative controls: a
potential that pays a call with too little, or leaves out the buffered bytes, does not go down
(checked once, 2026-11-12); without `ClosedNoPark`, a state of `SafeInv` with a closer done and
the threads parked has no step (in `inductive.sh`).

**The refinement** (`RefineWaitProof.tla`). Every step of `StreamBuffer.tla` keeps a detailed
invariant `DInv` and is a step of `StreamBufferWait.tla` under the mapping of `RefineWait.tla`, or
a stuttering step; with `Init` mapped to `Init`, `Spec => W!CSpec` for any finite set of readers.
The abstraction's own invariant holds in the mapped state (the instantiated `StepSafe`) and gives
what the detailed one lacks, such as a copying reader having its bytes buffered. `DInv` needs no
sum over the FIFO: the writer writes the bytes 1, 2, ... in order, so it describes each entry by
its first byte and its length: the next entry starts where one ends, the last ends at `nextByte`,
and the head starts, past `pos`, with the byte after those committed and in flight.
`waitingReaders` is the number of threads between the increment and the return of the wait, so a
skipped signal (`waitingReaders = 0`) has nobody to wake; that is what maps `sigread` to `siglock`.
Two changes to `StreamBuffer.tla` make the proof possible, both without new states: `Flat` is a
recursive function instead of a RECURSIVE operator, which tlapm cannot parse, and the ghost `toff`
replaces `Len(taken) % ReadLen` in the mapping, since tlapm proves nothing about `%` with a symbolic
divisor (not even `(a + R) % R = a % R`). Negative control (2026-11-12): with `LEMMA Bad == FALSE`
added, exactly that obligation fails, so the assumptions are consistent; a wrong mapping (`avail + 1`)
makes TLC's refinement check fail.

**Found on the way** (2026-11-12, not committed): Apalache's counterexamples to induction named the
missing conjuncts. These were `Buffered >= 0`, that a reader in `reread` saw the stream closed, and
for records the bound `hold + left <= K`. The record proof needed an explicit `PICK` of the copy's
byte count. The negative control of `waitForAtLeast` next to record readers stayed clean in
Apalache at every length while TLC found the violation; narrowing it down led to the range pitfall
above. With the ranges made non-empty, the torn record is found in 6 steps instead of 8.

**Limits of A13:**
- **Liveness of the detailed model** for any number of readers is not shown; the proof is about
  the abstraction (above), TLC checks the detailed model's liveness in its bounded configurations.
- **Liveness with threads that call forever** is in its own section below: with a finite stream
  and a closer every call returns without lock fairness; with an endless writer a reader can
  starve.
- **Inherited from `StreamBuffer.tla`:**
  - A reader's lock-free read of `availableBytes` and of `streamClosed` is one step, where Java
    reads them one after the other. This is harmless for safety: `RereadClosed` needs only
    `closed`, and nothing raises the count after the close.
  - Spurious wake-ups of `await` are not modelled. A woken thread checks again either way.
- **The refinement proof is for the current code** (`Protocol = "condition"` and the four fixes on),
  the configuration the abstractions model; the older code is shown failing by the bounded models.
- **The proofs** run every step as `OBVIOUS` under one large `USE DEF`, with `--stretch 3`. On a
  slower machine an obligation may time out. The obligation counts drift with prover versions.
- **tlapm 1.6.0-pre quirks** the liveness proof works around: its SMT backend proves linear
  arithmetic over cardinalities only when each term has a type fact of its own, and fails when
  unrelated facts are added (`BY ONLY` with the type facts, or a split into halves of 5 layers);
  it finds no witness for `ENABLED` of an action with an `IF` on the formula level (one witness
  action per branch); and expanding `ENABLED` in a context that extends `StreamBufferWaitLive.tla`
  crashes it (an assertion in `e_substitutive.ml`), so `StreamBufferWaitEnabled.tla` extends only
  the safety proof.
- **CI:** tlapm has no tagged 1.6 release, and the rolling 1.6.0-pre asset is replaced with every
  tlapm commit, so a checksum pin would break. The scheduled job `tlaps-proofs` therefore builds tlapm
  from the pinned commit `ff40755` (opam, dune, `make release`, which also runs tlapm's own release
  checks) and caches the tarball. Measured on 4 cores (2026-11-12, the job's steps replayed as a
  user without the cache): build about 10 min including the Isabelle download, `proof.sh` 622-1042 s
  in five runs for the three safety proofs, all obligations proved. With the liveness proof
  (2026-11-12, 4 cores, the other cores busy with `inductive.sh`): `proof.sh` 1098 s, all six
  modules proved; `inductive.sh` about 20 min, which is why `tla-model` has 60 min now. With the
  refinement proof: `proof.sh` 2114 s, all seven modules proved. With the forever liveness proof
  (2026-11-13, 4 cores of a local machine): 2866 s, all nine modules, so `tlaps-proofs` has
  120 min. tlapm can
  leave backend provers running after it ends, which slowed the next module into timeouts, so
  `proof.sh` runs each tlapm in a process group of its own and kills it afterwards; the ENABLED
  steps run with `--stretch 12`. The 1.6.0-pre asset of that commit had SHA-256
  `99db29f119cb6f43ffed653b212ba2d005e5bf8e242c53468876cb0d08da6bcc`.

## Liveness with threads that call forever (A13 follow-up)

The liveness of A13 needs finite programs: every thread makes finitely many calls. The open
question was a thread that calls forever. The guess was that the others then progress only with
fair locks, which the JDK does not promise. That guess was wrong in both directions:

- **A finite stream with a closer.** Every call of every thread returns, although threads call
  forever. That needs fair scheduling only: weak fairness per thread, writer and closer. It needs no
  lock fairness. TLC checks it in bounded models of the abstraction and of the detailed model, and
  TLAPS proves it for the abstraction, for any number of threads, writers and closers, under the
  fairness by role, which follows from that (see "Limits" below).
- **An endless writer and no close.** A reader can starve even when every thread step is strongly
  fair. The starving reader gets `bufferLock` every round and finds the bytes gone: the other
  reader committed them first. The bytes go to whoever commits first, so a fair lock would not
  help. Nothing in the contract promises otherwise; it supports several readers without fairness
  (F278).
- **The detailed model** needs weak fairness for its readers only. Its `Fairness` has been weak
  since 2026-11-13 (it was strong before); every model of the current code checks with it.

**Calls forever, without changing the models.** `StreamBufferWaitForever.tla` extends
`StreamBufferWait.tla` with a ghost step `Refill`, which tops up the budget of calls whenever it is
used up. Every run in which threads call forever is a run of it, with a `Refill` whenever the budget is
used up.
It also has runs in which threads stop, which only adds behaviours: what holds for all its fair
runs holds for the forever runs. So the safety, refinement and liveness proofs of
`StreamBufferWait.tla` stay as they are. `StreamBufferForever.tla` does the same for the detailed
model: a thread that is done calls again (`Restart`), so a reader reads again after -1 and a
`waitForAtLeast` caller waits again. The property `EveryCallReturns`: each thread returns again and
again, or it stopped. A failed re-check under `bufferLock` goes back to `start` too, but is no
return.

**The endless writer.** A ghost step `Shift` lowers `w` and `t` together. The code sees only
their difference (`availableBytes` and the buffered bytes), so with `Shift` the writer writes
forever in a finite state space, with its backlog bounded by `Bytes` (a subset of its runs, enough
for a counterexample).

**Models** (`check.sh`, 2026-11-13, TLC v1.7.4, the sizes CI runs):

| Model | Module | Threads | Expected and found |
|---|---|---|---|
| `WaitForever2` | `StreamBufferWaitForever` | `read()`, `read(b, 0, 2)` and `waitForAtLeast(2)` calls, 3 bytes, 1 writer, 1 closer | every call returns, 364,866 states |
| `WaitForever3` | same | 3 threads, 1 byte | every call returns, 838,813 states |
| `WaitForever2W2` | same | 2 threads, 2 bytes, 2 writers, 1 closer | every call returns, 588,720 states |
| `WaitForeverNextOnly2` | same | as `WaitForever2`, fairness for `Next` only | violated: thread 2 is never scheduled again while thread 1 calls forever |
| `WaitForeverNoClose2` | same | as `WaitForever2`, no closer | violated: the record reader waits forever for its second byte |
| `WaitForeverRuns2` | same | as `WaitForever2`, probe `AllStop` | violated: fair runs in which the threads call forever exist |
| `WaitForeverStarve2` | same | 2 threads, each call a `read()` or a `waitForAtLeast(2)`, an endless writer, no close, every thread step strongly fair | violated: the starvation lasso above (the starving thread's call is a `read()`) |
| `WaitForeverMeasure2` | `StreamBufferWaitForeverLive` | as `WaitForever2` | the step property of the proof's measure, and fairness per thread implies fairness by role |
| `WaitForeverRole2` | same | as `WaitForever2`, fairness by role | every call returns |
| `ForeverWaitAndRead2`, `ForeverWaitChecked2`, `ForeverMixed2`, `ForeverRecords2`, `ForeverChunks2`, `ForeverCondition3` | `StreamBufferForever` | the models of the current code, every thread calling again forever | every call returns; 3,038 to 294,862 states |
| `ForeverNextOnlyWaitAndRead2` | same | fairness for `Next` only | violated |

Locally, larger models check as well: 3 threads with 2 bytes (5,377,658 states, 13 min) and 2
writers with 2 closers and 3 bytes (6,138,012 states, 11 min).

**The proof for any number of threads** (`StreamBufferWaitForeverLiveProof.tla`, in `proof.sh`).
The theorem `ForeverLiveness == SpecRole => EveryCallReturns`, with at least one closer and
finitely many threads, writers and closers.

- **Fairness by role** (`FairRole`, `StreamBufferWaitForeverLive.tla`). Weak fairness for the
  thread r itself, for the holder of `bufferLock`, for the holder of `waitLock`, for a signaling
  writer or closer, and for a closing closer. Each follows from the weak fairness per thread of
  `FairProc`: a holder stays the holder while its step is possible (only its own step releases
  the lock), and a closer at `close` or a signaler at `siglock` stays enabled while the lock it
  needs is free. TLC checks `FairProc => FairRole` in `WaitForeverMeasure2`; the proof assumes
  `FairRole`, because tlapm cannot derive it for a symbolic set of threads.
- **A measure per thread r**, a natural number. Every step but a return of r keeps it or lowers it,
  and a step that keeps it moves neither r nor a lock holder nor a writer or closer. Its parts, each
  weighted to pay for the largest rise of the parts below it:
  1. what writers, closers and commits still have to do;
  2. the bytes a copy can still take;
  3. the threads at `bufferLock` whose re-check fails (stale since a commit);
  4. a stage per thread, the same on the cycles of returns that take no lock (a fast-path return,
     -1, the closed branch), lower with every lock taken; a wait that will not park ranks above one
     that will;
  5. r's position in its call.
- **In every state in which r has not stopped, some fair step lowers the measure:** r's own step;
  the holder of the lock r waits for; for a parked r, a signaler while `waitLock` is free, else the
  holder of `waitLock`, else a closer at `close` or the holder of `bufferLock`. A closer is at
  `close` there, since a parked thread means no closer is done (`ClosedNoPark`).
- **The measure is bounded by a constant**, so one induction over it (WF1 for each case,
  `NatInduction`) gives the property from every state.

Obligations: `StreamBufferWaitForeverEnabled.tla` 633 (the role actions are enabled where the
proof needs them), `StreamBufferWaitForeverLiveProof.tla` 1,322. Negative controls (2026-11-13,
not committed); each makes exactly the obligation fail that it should:

- a lemma `FALSE` added: only that one fails, so no backend derives `FALSE` from the
  assumptions;
- the weight of the first part too small (20 · threads + 1 instead of 30 · threads + 10, changed
  everywhere the proof names it): the arithmetic that pays for the rise of the lower parts fails;
- the stage of `decide` raised to that of `lock`, in the definition and the lemmas that restate
  it: the step that takes `bufferLock` no longer lowers the measure;
- the fairness of the closing closer removed: the fairness the proof unpacks is missing.

Before the proof, TLC checked the measure on the bounded models (`MeasureSteps`), and three
mutations of it fail there: a stage that does not drop when `bufferLock` is taken, the measure
without the buffered bytes, and without the stale lock holders.

**tlapm 1.6.0-pre quirks** the proof works around:
- a lemma cannot be instantiated at a term inside ENABLED (`ENABLED <<ThreadStep(x)>>_vars` at
  `r`, every backend fails): the operator `EnR(x)` is expanded only where it is used;
- expanding ENABLED in a context with the temporal definitions of the liveness modules crashes
  tlapm (an assertion in `e_substitutive.ml`): the role actions are in a module of their own,
  `StreamBufferWaitForeverRoles.tla`.

**Limits.**
- The proof is about the abstraction. As for A13, liveness does not carry over by the refinement;
  the detailed model's forever liveness rests on TLC's bounded models.
- `FairRole` is the proof's assumption; that it follows from fairness per thread is argued above
  and checked by TLC in bounded models.
- A finite stream with a closer. With an endless writer, per-call liveness fails (above).
- Spurious wake-ups of `await` are not modeled (see "Limits of A13").

## Trace validation: recorded runs of the code (roadmap A6)

The model is written by hand from the code. Trace validation checks the other direction on real
runs: every recorded run of the code must be a behaviour of `StreamBuffer.tla` (the approach of
Cirstea, Kuppe, Merz et al., "Validating Traces of Distributed Programs Against TLA+
Specifications", 2024). It checks only the runs it sees, so it is not a proof; it shows that the
model does what the code does in those runs, including the waits, wake-ups and lock holds.

**Recording, without touching the code.** `net.ladenthin.streambuffer.trace` (test code) loads
`StreamBuffer` through `TracingClassLoader`, which rewrites its bytecode with ASM (the class file in
`target/classes` and the shipped jar stay as they are). Every access to the state the model has
calls `TraceRecorder`:

- the reads and writes of `availableBytes` and `streamClosed`;
- `waitingReaders.get`, `incrementAndGet` and `decrementAndGet`;
- the monitor enter and exit of `bufferLock`;
- `waitLock.lock` and `unlock`, `modified.await` (before and after) and `signalAll`.

A non-blocking access runs and is logged under one global lock, so the log order is the order of
the accesses. A blocking one is logged right after it returns, a release right before it, which
keeps the order of everything that depends on the lock. `TraceScenario` runs the model's
scenarios on real threads:

- one writer of the bytes 1, 2, ... in writes of `ChunkLen` bytes, and one closer that closes at a
  random point of the run;
- readers of `read()` or `read(b, 0, ReadLen)` until -1, and `waitForAtLeast(ReadLen)` callers;
- `maxBufferElements` above the number of writes, since trim is not modeled;
- seeded random yields before the accesses, to vary the interleavings.

It adds the results of the calls to the log (the bytes a read returned, -1, the count of the wait,
a failed write). `TraceGenerator` writes each run as a TLA+ module, `Trace_<scenario>_<seed>.tla`,
with its configuration. A module rather than ndjson, because `ndJsonDeserialize` needs the
CommunityModules jar as a second pinned dependency.

**Matching** (`TraceStreamBuffer.tla`, which extends the model unchanged). The model is coarser
than the code in three places, so a thread's model steps are not tied to single lines:

- the fast path of the wait reads `availableBytes` and `streamClosed` in one step, the code in two
  reads;
- `ReaderTest` lowers `waitingReaders` in the step that reads the count, the code a few accesses
  later;
- a waiter's closed branch reads the count again for its result.

Before a line of thread `t`, `t` may take up to `K` = 6 model steps; then the line must agree with
the model's state:

- **Values:** every value read or written. Only `waitingReaders` may be lower in the model,
  because of the later decrement; the writer then skips a signal that wakes nobody.
- **Locks:** who holds `bufferLock` and `waitLock`.
- **The thread's position:** after the fast path, after the closed check, parked, past the
  decrement.
- **Results:** what its calls returned.

Other threads move only at their own lines. A trace is accepted if some placement consumes every
line. TLC 1.7.4 has no `POSTCONDITION`, so the verdict is the inverted invariant `TraceNotDone`,
which TLC violates exactly then. Deadlock checking is off, as the paper says. A rejected trace
prints the first line no placement could consume.

**Results** (2026-11-13, local, TLC 1.7.4, `trace.sh`, assertions on in the traced class):

| | |
|---|---|
| traces | 990, all accepted: 11 scenarios x 30 seeds x 3 yield rates (0, 32, 128 per 256 accesses) |
| scenarios | the seven of `check.sh` (2 and 3 `read()` readers, records of 2 bytes from writes of 1 and 3, `read()` next to a record reader, `waitForAtLeast` next to a reader, also next to a 2-byte write), plus 3 `read()` readers of 8 bytes, 3 record readers of writes of 3 bytes, two waiters next to a reader, a waiter next to a reader of 3-byte records |
| size | 81,998 lines, 82 per trace on average, up to 284; TLC up to 50,683 distinct states per trace (2,254 on average) |
| time | about 2.3 s per trace with one TLC worker; the 990 in 10 min, 9 in parallel on 16 cores |

**Negative controls** (`trace-controls.sh`, also in CI; in CI the two scripts take about 5 min). A validation that accepts everything shows
nothing, so these must reject:

| control | rejected (one CI-sized run: 33 traces, 3 seeds, 2026-11-12; the counts vary with the interleavings) |
|---|---|
| older code with fewer behaviours: `AtomicRead = FALSE` (before #212, the `Records*` traces) | 3 of 6 |
| the semaphore wait (before F278) | 17 of 33 |
| no re-check under `bufferLock` (`ReCheck = FALSE`, before F278, the `Bytes*` traces) | 7 of 9 |
| a mutated model whose writer never signals | 10 of 33 |
| every trace with a completed read, its first returned byte changed by one | 33 of 33 |

The traces a wrong model accepts are those that never reach the difference, e.g. no thread
waited, so the semaphore and the missing signal never mattered. Two older versions accept every
trace, and rightly so. Before F279 (`CountOnce = FALSE`) and without `CheckedReturn`, the model
allows *more* behaviours than the current code: a count from the middle of a read, a second read of
the count. Trace validation checks that the code's runs are runs of the model; that the model's
runs have the properties is what model checking (`check.sh`) and the proofs show.

**Limits.**

- Only the runs it sees, of the scenarios above. The global trace lock serializes the traced
  accesses, which changes the timing; the yields vary it again.
- Not traced: the FIFO itself and `positionAtCurrentBufferEntry`, which only the holder of
  `bufferLock` touches. The bytes every read returns are checked against the model's FIFO
  instead.
- A spurious wake-up of `await()` is not in the model and would reject a trace; none occurred.
- The lines name a method and its n-th access of a kind (`waitForAtLeast.getAvail#0`). A change of
  those methods needs the mapping in `TraceStreamBuffer.tla` changed with it (`TraceRecorderTest`
  fails first, with the fixed list of a single-threaded run).

## Limits

- **Not in the model:** several writers (each write is atomic under the lock, so they interleave
  as whole entries), read sizes other than 1 and `ReadLen`, `waitForAtLeast` with a timeout,
  interrupts, the external `addSignal` semaphores, and trim's merging of the entries (it keeps the
  bytes, their order and `availableBytes`; it only changes how many copy steps a read takes, which
  matters to the count per entry before F279 alone). JPF, vmlens, jcstress and Lincheck cover them.
- **Sequential consistency.** TLC explores interleavings of atomic steps. That this matches the Java
  memory model rests on the data-race-freedom argument in the README ("Data-Race Freedom").
- **Model vs. code.** The model is written by hand from the code. Trace validation (above, roadmap
  A6) checks recorded runs against it, which is evidence, not a proof that they agree. The inductive invariants above (roadmap A13)
  remove the bounds on readers, bytes and record size for three slices of the protocol, for
  abstractions that TLC ties to this model in its bounded configurations.

## Run it

```bash
curl -fLo tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
sha256sum tla2tools.jar   # 936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
bash src/test/tla/check.sh "$PWD/tla2tools.jar"

# A6: record traces of the instrumented code (3 runs per scenario, yields 32/256), check them
mvn test-compile dependency:build-classpath -Dmdep.includeScope=test -Dmdep.outputFile=target/test-classpath.txt
java -cp "target/test-classes:target/classes:$(cat target/test-classpath.txt)" \
  net.ladenthin.streambuffer.trace.TraceGenerator target/traces 3 32   # ';' instead of ':' on Windows
bash src/test/tla/trace.sh "$PWD/tla2tools.jar" target/traces
bash src/test/tla/trace-controls.sh "$PWD/tla2tools.jar" target/traces

# A13: Apalache (needs JDK 17+)
curl -fLo apalache.tgz https://github.com/apalache-mc/apalache/releases/download/v0.63.0/apalache-0.63.0.tgz
sha256sum apalache.tgz   # a756e96af249bf33cd7629667a49472cb26ac8227c48583da139b414834d59df
mkdir apalache && tar xzf apalache.tgz -C apalache --strip-components=1
bash src/test/tla/inductive.sh "$PWD/tla2tools.jar" "$PWD/apalache/bin/apalache-mc"

# A13, any number of readers: TLAPS (Linux). The rolling asset follows tlapm main; CI builds the
# pinned commit instead (the tlaps-proofs job of formal-verification.yml)
curl -fLo tlapm.tgz https://github.com/tlaplus/tlapm/releases/download/1.6.0-pre/tlapm-1.6.0-pre-x86_64-linux-gnu.tar.gz
mkdir tlapm && tar xzf tlapm.tgz -C tlapm --strip-components=1
bash src/test/tla/proof.sh "$PWD/tlapm/bin/tlapm"
```

One model by hand, with its error trace: `java -cp tla2tools.jar tlc2.TLC -config Semaphore2.cfg
StreamBuffer.tla` from this directory. CI: the `tla-model` job (`check.sh`, `inductive.sh`) and the
`tlaps-proofs` job (`proof.sh`) of `formal-verification.yml`, both scheduled or dispatched.
