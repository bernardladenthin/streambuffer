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
- **Fairness:** weak for the writer and the closer, strong for the readers (a free lock or permit
  that a reader keeps finding taken is eventually its; the JDK locks are not fair, so this is an
  assumption).

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

## Models and results

`check.sh` runs every model and compares it with its **expected** outcome. Last run 2026-11-11, TLC
v1.7.4, 16 models, about 90 s in total. Writes are single bytes unless the row says otherwise:

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
- **TLC refinement checks** tie each abstraction to the detailed model.

**What this does and does not show.** The unbounded results hold for the abstractions. That
`StreamBuffer.tla` behaves like them is checked by TLC refinement for its bounded configurations
only (2 and 3 readers, up to 4 bytes). Each mapped step concerns one thread, so the link very likely
generalises, but nothing machine-checks that.

The abstractions build in the current code where the slice does not vary it: the count lowered once
per read (F279), and the re-check everywhere but in the `read()` abstraction. `AvailLinearizable` is
therefore true by construction there, and the F279 defect is only shown by the bounded model
`RecordsCountPerEntry2`.

| Abstraction | Slice | Apalache (fixed N) | TLAPS (any N) | Refinement (TLC) | Older code reaches a violation |
|---|---|---|---|---|---|
| `StreamBufferCounters.tla` | `read()`, single-byte writes | N = 2, 3, 4, 8, 12; any bytes (`IndInv`) | `SafeInv`, 216 obligations | `Condition2`, `Condition3` | the empty take without the re-check (F278), 10 steps |
| `StreamBufferRecords.tla` | `read(b, 0, K)`, several writers and closers, any chunking | 2, 3, 4 readers with 2 writers and 2 closers, 2 readers with 3 and 3; any K and bytes (`SafeModInv`) | `SafeInv`, any readers, writers and closers, 488 obligations | `Records2`, `Chunks2` | a torn record with the two-phase read (#212), 6 steps |
| `StreamBufferWait.tla` | every thread any number of calls, each `read(b, 0, K[r])` (`K[r] = 1` is `read()`) or `waitForAtLeast(M[r])`; several writers and closers, any chunking | 2, 3, 4 threads with 2 writers and 2 closers, 2 threads with 3 and 3; any read sizes, requests, bytes and calls (`SafeModInv`) | `SafeInv`, any threads, writers and closers, 577 obligations | all seven configurations of the current code (`Condition2`, `Condition3`, `Records2`, `Chunks2`, `Mixed2`, `WaitAndRead2`, `WaitChecked2`) | `waitForAtLeast(M[r]) < M[r]` on an open buffer before `CheckedReturn`, 11 steps |
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
checked by Apalache (`SafeModInv`, N up to 4) and by the refinement (`off <- Len(taken) % ReadLen`),
not by TLAPS. In `StreamBufferWait.tla` the ghost counts modulo `RecLen`, and `RecordsAligned`
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

**Found on the way** (2026-11-12, not committed): Apalache's counterexamples to induction named the
missing conjuncts. These were `Buffered >= 0`, that a reader in `reread` saw the stream closed, and
for records the bound `hold + left <= K`. The record proof needed an explicit `PICK` of the copy's
byte count. The negative control of `waitForAtLeast` next to record readers stayed clean in
Apalache at every length while TLC found the violation; narrowing it down led to the range pitfall
above. With the ranges made non-empty, the torn record is found in 6 steps instead of 8.

**Limits of A13:**
- **Refinement for any number of readers:** that `StreamBuffer.tla` behaves like the abstractions
  is checked by TLC for its bounded configurations only (above).
- **Liveness needs finite programs.** Every call returns when every thread makes finitely many
  calls. With a thread that calls forever, the others still progress only if the locks are fair to
  them, which the JDK does not promise; that is not shown.
- **Inherited from `StreamBuffer.tla`:**
  - A reader's lock-free read of `availableBytes` and of `streamClosed` is one step, where Java
    reads them one after the other. This is harmless for safety: `RereadClosed` needs only
    `closed`, and nothing raises the count after the close.
  - Spurious wake-ups of `await` are not modelled. A woken thread checks again either way.
- **The `sigread -> siglock` mapping** of the refinements relies on `waitingReaders >= |parked|` in
  the detailed model, so a skipped signal has nobody to wake. That holds, but is checked only in the
  bounded configurations.
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
  modules proved; `inductive.sh` about 20 min, which is why `tla-model` has 60 min now. tlapm can
  leave backend provers running after it ends, which slowed the next module into timeouts, so
  `proof.sh` runs each tlapm in a process group of its own and kills it afterwards; the ENABLED
  steps run with `--stretch 12`. The 1.6.0-pre asset of that commit had SHA-256
  `99db29f119cb6f43ffed653b212ba2d005e5bf8e242c53468876cb0d08da6bcc`.

## Limits

- **Not in the model:** several writers (each write is atomic under the lock, so they interleave
  as whole entries), read sizes other than 1 and `ReadLen`, `waitForAtLeast` with a timeout,
  interrupts, the external `addSignal` semaphores, and trim's merging of the entries (it keeps the
  bytes, their order and `availableBytes`; it only changes how many copy steps a read takes, which
  matters to the count per entry before F279 alone). JPF, vmlens, jcstress and Lincheck cover them.
- **Sequential consistency.** TLC explores interleavings of atomic steps. That this matches the Java
  memory model rests on the data-race-freedom argument in the README ("Data-Race Freedom").
- **Model vs. code.** The model is written by hand from the code; nothing checks that they agree.
  Trace validation (roadmap A6) closes that gap. The inductive invariants above (roadmap A13)
  remove the bounds on readers, bytes and record size for three slices of the protocol, for
  abstractions that TLC ties to this model in its bounded configurations.

## Run it

```bash
curl -fLo tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
sha256sum tla2tools.jar   # 936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
bash src/test/tla/check.sh "$PWD/tla2tools.jar"

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
