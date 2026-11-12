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

## Unbounded safety: an inductive invariant (roadmap A13)

TLC checks fixed constants: up to 3 readers and a few bytes. For the `read()` protocol, an
inductive invariant removes both bounds: Apalache v0.63.0 checks it for fixed reader counts and any
number of bytes (`inductive.sh`), and a TLAPS proof shows it for **any number of readers and bytes**
(`proof.sh`):

- **`StreamBufferCounters.tla`** is a counter abstraction of the `read()` configuration: the
  writer writes the bytes 1, 2, ... in order and the FIFO hands them out in order, so the byte
  sequences reduce to counts (`w` written, `t` committed, `hold[r]` the byte a reader copies).
  Readers are `1..N`; `Bytes` stays **symbolic**, so every result holds for any number of bytes.
- **`SafeInv`**: the safety properties (`NoEmptyTake`, `AvailLinearizable`, `NoWriteAfterEof`,
  `EofOnlyWhenClosedAndEmpty`) plus what makes them inductive, each a named conjunct: `bufferLock`
  is held exactly by the reader deciding, copying or finishing (`BufLock`); the bytes in flight are
  buffered (`BufNonNeg`); a reader copying has a byte to copy (`CopyHasByte`); `waitLock` and
  `parked` match the reader states; a reader at the end of the stream saw it closed and empty; no
  write follows a close. **`IndInv`** adds the `waitingReaders` count, which steers only whether a
  write signals (liveness), so `SafeInv` is inductive without it.
- **Apalache proves** `Init => IndInv` and `IndInv /\ Next => IndInv'` for N = 2, 3, 4, 8 and 12
  readers (N = 12 in about 40 s; 2026-11-12). Without the re-check of F278 the inductive step
  fails exactly there: a reader in `decide` with an empty FIFO takes from it (`nsee`).
- **TLAPS proves** (`StreamBufferCountersProof.tla`, tlapm 1.6.0-pre `ff40755`, 2026-11-12) that
  `SafeInv` holds initially and is preserved by every action, for any `N >= 1` and `Bytes >= 1`, and
  so `Spec => []Safety`: all 216 obligations, about 100 s on 16 vCPUs, one case per action and the
  five reader actions with many updates split by conjunct. With `ReCheck = FALSE` assumed instead,
  3 obligations fail, all in `ReaderDecide` (`Safety'` and `BufLock'`): the proof needs the re-check.
- **TLC checks the abstraction against the detailed model:** `RefineCounters.tla` maps
  `StreamBuffer.tla` onto the counters (`w = Len(written)`, `hold[r] = Len(hold[r])`, the reader
  states one to one, `eof` onto `ret0`), and in the configurations of `Condition2` and `Condition3`
  every step of the detailed model is a step of the abstraction or a stuttering step
  (`RefineCondition2`, `RefineCondition3`). A wrong mapping (`avail + 1`, or `eof` left unmapped)
  makes the check fail.

Found on the way (2026-11-12, not committed): the first candidate invariant missed `Buffered >= 0`
and that a reader in `reread` saw the stream closed; Apalache's counterexamples to induction named
both. **Limits:** the abstraction covers `read()` with single-byte writes, not records, chunked
writes or `waitForAtLeast` (TLC covers those in the bounded models above), and only safety, not
liveness; the refinement to the detailed model is checked by TLC for 2 and 3 readers, so it is
bounded. `proof.sh` is not in CI yet: tlapm has no tagged 1.6 release, and the rolling 1.6.0-pre
asset changes, so a pinned checksum would break the scheduled job.

## Limits

- **Not in the model:** several writers (each write is atomic under the lock, so they interleave
  as whole entries), read sizes other than 1 and `ReadLen`, `waitForAtLeast` with a timeout,
  interrupts, the external `addSignal` semaphores, and trim's merging of the entries (it keeps the
  bytes, their order and `availableBytes`; it only changes how many copy steps a read takes, which
  matters to the count per entry before F279 alone). JPF, vmlens, jcstress and Lincheck cover them.
- **Sequential consistency.** TLC explores interleavings of atomic steps. That this matches the Java
  memory model rests on the data-race-freedom argument in the README ("Data-Race Freedom").
- **Model vs. code.** The model is written by hand from the code; nothing checks that they agree.
  Trace validation (roadmap A6) closes that gap. The inductive invariant above (roadmap A13)
  removes the bound on the bytes for the `read()` protocol, for a fixed number of readers.

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
