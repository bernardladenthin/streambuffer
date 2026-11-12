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

TLC checks fixed constants, up to 3 readers and a few bytes. For three slices of the protocol,
counter abstractions with inductive invariants remove those bounds:

- **Apalache v0.63.0** (`inductive.sh`): fixed reader counts, with bytes, record size and the
  `waitForAtLeast` request symbolic.
- **TLAPS** (`proof.sh`): any number of readers.
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
| `StreamBufferCounters.tla` | `read()`, single-byte writes | N = 2, 3, 4, 8, 12; any bytes (`IndInv`) | `SafeInv`, 216 obligations | `Condition2`, `Condition3` | the empty take without the re-check (F278), 9 steps |
| `StreamBufferRecords.tla` | `read(b, 0, K)`, any chunking of the writes | N = 2, 3, 4; any K and bytes (`SafeModInv`) | `SafeInv`, 501 obligations | `Records2`, `Chunks2` | a torn record with the two-phase read (#212), 8 steps |
| `StreamBufferWait.tla` | `waitForAtLeast(M)` next to `read()` readers, any chunking | 1+1, 2+2, 3+1 readers+waiters; any M and bytes | `SafeInv`, 531 obligations | `WaitAndRead2`, `WaitChecked2` | `waitForAtLeast(M) < M` on an open buffer before `CheckedReturn`, 11 steps |

**The abstractions.** The writer writes the bytes 1, 2, ... in order, and the FIFO hands them out
in order, so the byte sequences reduce to counts:
- `w` written, `t` committed, `hold[r]` copied in the current hold of `bufferLock`;
- for records, also `left[r]` (bytes still to copy) and the ghost `off`.

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
  `waitForAtLeast`.
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
not by TLAPS.

**Negative controls.** Each older code version reaches a violation of the **safety property
itself** in a bounded Apalache search from `Init`, with the symbolic constants left free. The steps
are in the table above. In the TLAPS proofs, assuming the older code makes obligations fail: without
the re-check, `Safety'` and `BufLock'` in `ReaderDecide`; with the two-phase read, `WholeRead'` and
`CurZero'`; without `CheckedReturn`, `WaiterStates'` in `ThreadTest`. Those failures are in helper
conjuncts that encode the fix, which is why the bounded searches are the evidence. A wrong mapping
makes a refinement check fail (`avail + 1`, or `eof` left unmapped).

**Found on the way** (2026-11-12, not committed): Apalache's counterexamples to induction named the
missing conjuncts. These were `Buffered >= 0`, that a reader in `reread` saw the stream closed, and
for records the bound `hold + left <= K`. The record proof needed an explicit `PICK` of the copy's
byte count.

**Limits of A13:**
- **Not covered:** one writer and one closer only; `waitForAtLeast` next to record readers; waiters
  with different M; a waiter that calls more than once or also reads; record readers of different
  sizes next to each other (TLC covers that, bounded, in `Mixed2`); liveness.
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
- **Not in CI yet:** `proof.sh`, because tlapm has no tagged 1.6 release and the rolling 1.6.0-pre
  asset changes. The run of 2026-11-12 used the asset with SHA-256
  `99db29f119cb6f43ffed653b212ba2d005e5bf8e242c53468876cb0d08da6bcc` (tlapm `ff40755`).

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

# A13, any number of readers: TLAPS (Linux)
curl -fLo tlapm.tgz https://github.com/tlaplus/tlapm/releases/download/1.6.0-pre/tlapm-1.6.0-pre-x86_64-linux-gnu.tar.gz
mkdir tlapm && tar xzf tlapm.tgz -C tlapm --strip-components=1
bash src/test/tla/proof.sh "$PWD/tlapm/bin/tlapm"
```

One model by hand, with its error trace: `java -cp tla2tools.jar tlc2.TLC -config Semaphore2.cfg
StreamBuffer.tla` from this directory. CI: the `tla-model` job of `formal-verification.yml`
(scheduled or dispatched).
