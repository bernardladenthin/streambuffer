<!--
SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# TLA+ model of the wait/wake-up/close protocol

`StreamBuffer.tla` models how `StreamBuffer` threads write, close, wait for data and take it, and
TLC checks it over every interleaving of a small configuration (TODO roadmap A5). Where the JPF
harnesses run the real bytecode for one fixed scenario, the model states the protocol on its own and
checks safety **and liveness** (every reader eventually returns) for each configuration. It is not
part of the Maven build and never touches the shipped jar.

## What is modeled

- **Threads:** a writer of `Bytes` single-byte writes, a closer, and the readers in `Readers`, each
  calling `read()` until it returns -1.
- **State:** the buffered bytes in FIFO order (`buf`; `availableBytes` is `Len(buf)`), the bytes
  written and taken, `streamClosed`, and the waiting machinery.
- **Atomicity:** one step is one atomic action. A `synchronized (bufferLock)` block is one step,
  each lock-free volatile read or write is a step of its own, and `waitLock` is a variable: a
  writer's signal can come between a reader's lock-free reads, but not between the reader's
  increment of `waitingReaders` and its check under `waitLock`.
- **Two code versions**, chosen by constants:
  - `Protocol = "condition"`, `ReCheck = TRUE` — the code since bug-hunt finding F278: a `Condition`
    on `waitLock` with `signalAll`, the `waitingReaders` count that lets a write skip the lock while
    nobody waits, and the re-check of `availableBytes` under `bufferLock` before taking a byte.
  - `Protocol = "semaphore"`, `ReCheck = FALSE` — the code before F278 (`b3c309e`): a `Semaphore`
    released only while it has no permit, the check outside the lock, no re-check.
  F278 had both causes at once; `ReCheck` separates them.
- **Fairness:** weak for the writer and the closer, strong for the readers (a free lock or permit
  that a reader keeps finding taken is eventually its; the JDK locks are not fair, so this is an
  assumption).

## Properties

| Property | Kind | Meaning |
|---|---|---|
| `TypeOK` | invariant | every variable in its domain |
| `NoEmptyTake` | invariant | no reader takes from an empty FIFO (`NoSuchElementException`, F278) |
| `Fifo` | invariant | `written = taken \o buf`: nothing lost, nothing twice, `available = written − read` |
| `ReaderOrder` | invariant | each reader gets the bytes in the order they were written |
| `NoWriteAfterEof` | invariant | no write returns normally after a reader reported the end (F149) |
| `EofOnlyWhenClosedAndEmpty` | invariant | only a closed buffer reports the end, and it stays empty |
| `AllReadersFinish` | liveness | every reader returns, from every wait (no lost wake-up, F278) |

## Models and results

`check.sh` runs every model and compares it with its **expected** outcome. Last run 2026-11-11, TLC
v1.7.4, about 30 s in total:

| Model | Code | Readers | Expected and found |
|---|---|---|---|
| `Condition1` | since F278 | 1 | no error, 426 states |
| `Condition2` | since F278 | 2 | no error, 6,871 states |
| `Condition3` | since F278 | 3 | no error, 97,441 states |
| `Semaphore1` | before F278 | 1 | no error (one reader was always fine) |
| `Semaphore2` | before F278 | 2 | `NoEmptyTake` violated: both readers saw the byte, the second found the FIFO empty under the lock |
| `SemaphoreReCheck2` | semaphore, but with the re-check | 2 | deadlock: both readers wait for a permit, the close releases one, the other reader waits forever |
| `ConditionNoReCheck2` | condition, without the re-check | 2 | `NoEmptyTake` violated: the re-check is needed with the condition too |

A mutation check on 2026-11-11 (not committed): with `waitingReaders` never counted, every signal is
skipped and TLC reports a deadlock in `Condition2`, so the model does check the skip of the wait
lock that the count allows.

## Limits

- **Single bytes.** `read(b, off, len)` taking its bytes in one step, trim's consolidation (it keeps
  `availableBytes` and the byte order, so it is a no-op here) and the per-entry counters of F279 are
  not in the model; JPF (`RecordReaders.jpf`), vmlens, jcstress and Lincheck cover them.
- **Sequential consistency.** TLC explores interleavings of atomic steps. That this matches the Java
  memory model rests on the data-race-freedom argument in the README ("Data-Race Freedom").
- **Model vs. code.** The model is written by hand from the code; nothing checks that they agree.
  Trace validation (roadmap A6) closes that gap, an inductive invariant checked with Apalache
  (roadmap A13) removes the bound on the configuration.

## Run it

```bash
curl -fLo tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
sha256sum tla2tools.jar   # 936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
bash src/test/tla/check.sh "$PWD/tla2tools.jar"
```

One model by hand, with its error trace: `java -cp tla2tools.jar tlc2.TLC -config Semaphore2.cfg
StreamBuffer.tla` from this directory. CI: the `tla-model` job of `formal-verification.yml`
(scheduled or dispatched).
