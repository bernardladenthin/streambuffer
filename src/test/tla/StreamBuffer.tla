\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE StreamBuffer ----------------------------
(***************************************************************************)
(* The wait/wake-up/close protocol of net.ladenthin.streambuffer.StreamBuffer *)
(* (TODO roadmap A5), checked with TLC.                                     *)
(*                                                                         *)
(* Threads: one writer of Bytes single-byte writes, one closer, and the     *)
(* readers in Readers, each calling read() until it returns -1. The FIFO is *)
(* abstracted to its bytes (buf); availableBytes is Len(buf). Every step    *)
(* is one atomic action: an action "under bufferLock" stands for the whole  *)
(* synchronized block, the lock-free volatile reads and writes are steps of *)
(* their own, and waitLock is a variable, so a writer's signal cannot slip  *)
(* in between a waiter's increment of waitingReaders and its check.         *)
(*                                                                         *)
(* Protocol = "condition", ReCheck = TRUE is the code since bug-hunt      *)
(* finding F278: a                                                         *)
(* Condition on waitLock with signalAll, the waitingReaders count that lets *)
(* a write skip the lock while nobody waits, and the re-check under         *)
(* bufferLock before taking a byte. Protocol = "semaphore" is the code      *)
(* before F278 (b3c309e): a Semaphore released only while it has no permit, *)
(* the check outside the lock and no re-check. trim() keeps availableBytes  *)
(* and the order of the bytes, so it is a no-op at this level of detail.    *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS
    Readers,    \* the reader threads (model values)
    Bytes,      \* how many single-byte writes the writer attempts
    Protocol,   \* "condition" (since F278) or "semaphore" (before F278)
    ReCheck     \* whether a reader checks availableBytes again under bufferLock

ASSUME Protocol \in {"condition", "semaphore"} /\ ReCheck \in BOOLEAN
       /\ Bytes \in Nat /\ Readers # {}

None == "none"
Writer == "writer"
Closer == "closer"

VARIABLES
    buf,        \* the buffered bytes in FIFO order; availableBytes = Len(buf)
    written,    \* every byte whose write returned normally, in order
    taken,      \* every byte a reader took, in the order they were taken
    closed,     \* streamClosed
    nextByte,   \* the value of the writer's next byte (1, 2, ...)
    wpc,        \* the writer's program counter
    cpc,        \* the closer's program counter
    rpc,        \* rpc[r]: reader r's program counter
    got,        \* got[r]: the bytes reader r received, in order
    eofAt,      \* Len(written) when a reader first returned -1, else -1
    permits,    \* "semaphore": permits of the internal semaphore (0 or 1)
    waiters,    \* "condition": waitingReaders
    parked,     \* "condition": the readers parked in Condition.await()
    wl          \* "condition": the holder of waitLock, or None

vars == <<buf, written, taken, closed, nextByte, wpc, cpc, rpc, got, eofAt,
          permits, waiters, parked, wl>>

ReaderStates == {"start", "reread", "acquire", "lockwait", "inc", "test",
                 "parked", "woken", "take", "eof", "done", "nsee"}

TypeOK ==
    /\ buf \in Seq(1..Bytes) /\ written \in Seq(1..Bytes) /\ taken \in Seq(1..Bytes)
    /\ closed \in BOOLEAN /\ nextByte \in 1..(Bytes + 1)
    /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
    /\ cpc \in {"close", "sigread", "siglock", "done"}
    /\ rpc \in [Readers -> ReaderStates]
    /\ got \in [Readers -> Seq(1..Bytes)]
    /\ eofAt \in -1..Bytes
    /\ permits \in 0..1 /\ waiters \in 0..Cardinality(Readers)
    /\ parked \subseteq Readers /\ wl \in Readers \cup {None, Writer, Closer}

Init ==
    /\ buf = <<>> /\ written = <<>> /\ taken = <<>>
    /\ closed = FALSE /\ nextByte = 1
    /\ wpc = "write" /\ cpc = "close"
    /\ rpc = [r \in Readers |-> "start"]
    /\ got = [r \in Readers |-> <<>>]
    /\ eofAt = -1 /\ permits = 0 /\ waiters = 0 /\ parked = {} /\ wl = None

(***************************************************************************)
(* The signal after a write or the close (signalModification()).          *)
(* "semaphore": release only while the semaphore has no permit (max 1).    *)
(* "condition": read waitingReaders lock-free; if it is not 0, take        *)
(* waitLock and signalAll -- every parked reader becomes "woken".          *)
(***************************************************************************)
SignalAll ==
    /\ wl = None
    /\ rpc' = [r \in Readers |-> IF r \in parked THEN "woken" ELSE rpc[r]]
    /\ parked' = {}
    /\ UNCHANGED <<waiters, wl, permits>>

(***************************************************************************)
(* The writer: write(int) under bufferLock -- fails once closed (F149: the *)
(* closed check is under the lock), else appends -- then the signal.       *)
(***************************************************************************)
WriterWrite ==
    /\ wpc = "write"
    /\ IF closed
          THEN /\ wpc' = "failed"
               /\ UNCHANGED <<buf, written, nextByte>>
          ELSE /\ buf' = Append(buf, nextByte)
               /\ written' = Append(written, nextByte)
               /\ nextByte' = nextByte + 1
               /\ wpc' = "sigread"
    /\ UNCHANGED <<taken, closed, cpc, rpc, got, eofAt, permits, waiters, parked, wl>>

WriterDone == IF nextByte > Bytes THEN "done" ELSE "write"

WriterSigRead ==
    /\ wpc = "sigread"
    /\ \/ /\ Protocol = "semaphore"
          /\ permits' = 1
          /\ wpc' = WriterDone
       \/ /\ Protocol = "condition"
          /\ wpc' = IF waiters # 0 THEN "siglock" ELSE WriterDone
          /\ UNCHANGED permits
    /\ UNCHANGED <<buf, written, taken, closed, nextByte, cpc, rpc, got, eofAt, waiters, parked, wl>>

WriterSigLock ==
    /\ wpc = "siglock"
    /\ SignalAll
    /\ wpc' = WriterDone
    /\ UNCHANGED <<buf, written, taken, closed, nextByte, cpc, got, eofAt>>

WriterStep == WriterWrite \/ WriterSigRead \/ WriterSigLock

(***************************************************************************)
(* The closer: close() sets streamClosed under bufferLock, then signals.  *)
(***************************************************************************)
CloserClose ==
    /\ cpc = "close"
    /\ closed' = TRUE
    /\ cpc' = "sigread"
    /\ UNCHANGED <<buf, written, taken, nextByte, wpc, rpc, got, eofAt, permits, waiters, parked, wl>>

CloserSigRead ==
    /\ cpc = "sigread"
    /\ \/ /\ Protocol = "semaphore"
          /\ permits' = 1
          /\ cpc' = "done"
       \/ /\ Protocol = "condition"
          /\ cpc' = IF waiters # 0 THEN "siglock" ELSE "done"
          /\ UNCHANGED permits
    /\ UNCHANGED <<buf, written, taken, closed, nextByte, wpc, rpc, got, eofAt, waiters, parked, wl>>

CloserSigLock ==
    /\ cpc = "siglock"
    /\ SignalAll
    /\ cpc' = "done"
    /\ UNCHANGED <<buf, written, taken, closed, nextByte, wpc, got, eofAt>>

CloserStep == CloserClose \/ CloserSigRead \/ CloserSigLock

(***************************************************************************)
(* A reader: read() = waitForAtLeast(1), then take a byte under bufferLock.*)
(***************************************************************************)
Goto(r, s) == rpc' = [rpc EXCEPT ![r] = s]

ReaderUnchanged == <<buf, written, taken, closed, nextByte, wpc, cpc>>

(* The lock-free fast path of the wait: enough bytes, or closed, or wait. *)
ReaderStart(r) ==
    /\ rpc[r] = "start"
    /\ IF Len(buf) >= 1 THEN Goto(r, "take")
       ELSE IF closed THEN Goto(r, "reread")
       ELSE Goto(r, IF Protocol = "condition" THEN "lockwait" ELSE "acquire")
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, permits, waiters, parked, wl>>

(* Closed seen: the wait returns availableBytes, read again (both code    *)
(* versions do), so a write buffered before the close is still read.       *)
ReaderReread(r) ==
    /\ rpc[r] = "reread"
    /\ Goto(r, IF Len(buf) >= 1 THEN "take" ELSE "eof")
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, permits, waiters, parked, wl>>

(* "semaphore": block on the semaphore, then check again (the loop). *)
ReaderAcquire(r) ==
    /\ rpc[r] = "acquire"
    /\ permits > 0
    /\ permits' = permits - 1
    /\ Goto(r, "start")
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, waiters, parked, wl>>

(* "condition": awaitAtLeast takes waitLock (also again after a wake-up). *)
ReaderLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"}
    /\ wl = None
    /\ wl' = r
    /\ Goto(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, permits, waiters, parked>>

(* "condition": waitingReaders.incrementAndGet() under waitLock. *)
ReaderInc(r) ==
    /\ rpc[r] = "inc"
    /\ waiters' = waiters + 1
    /\ Goto(r, "test")
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, permits, parked, wl>>

(* "condition": the loop condition under waitLock; await() parks and       *)
(* releases the lock in one step, leaving returns availableBytes.          *)
ReaderTest(r) ==
    /\ rpc[r] = "test"
    /\ wl = r
    /\ IF Len(buf) >= 1 \/ closed
          THEN /\ waiters' = waiters - 1
               /\ Goto(r, IF Len(buf) >= 1 THEN "take" ELSE "eof")
               /\ UNCHANGED parked
          ELSE /\ parked' = parked \cup {r}
               /\ Goto(r, "parked")
               /\ UNCHANGED waiters
    /\ wl' = None
    /\ UNCHANGED <<ReaderUnchanged, got, eofAt, permits>>

(* Take the head under bufferLock. With ReCheck (the code since F278) the  *)
(* reader checks again and waits again if another reader took the byte;    *)
(* without it (before F278) it calls getFirst() on the deque without       *)
(* checking: on an empty one, NoSuchElementException. F278 had two causes, *)
(* the semaphore and the missing re-check; ReCheck separates them.         *)
ReaderTake(r) ==
    /\ rpc[r] = "take"
    /\ IF Len(buf) > 0
          THEN /\ taken' = Append(taken, Head(buf))
               /\ got' = [got EXCEPT ![r] = Append(@, Head(buf))]
               /\ buf' = Tail(buf)
               /\ Goto(r, "start")
          ELSE /\ Goto(r, IF ReCheck THEN "start" ELSE "nsee")
               /\ UNCHANGED <<taken, got, buf>>
    /\ UNCHANGED <<written, closed, nextByte, wpc, cpc, eofAt, permits, waiters, parked, wl>>

(* read() returns -1. *)
ReaderEof(r) ==
    /\ rpc[r] = "eof"
    /\ eofAt' = IF eofAt = -1 THEN Len(written) ELSE eofAt
    /\ Goto(r, "done")
    /\ UNCHANGED <<ReaderUnchanged, got, permits, waiters, parked, wl>>

ReaderStep(r) ==
    \/ ReaderStart(r) \/ ReaderReread(r) \/ ReaderAcquire(r) \/ ReaderLock(r)
    \/ ReaderInc(r) \/ ReaderTest(r) \/ ReaderTake(r) \/ ReaderEof(r)

Terminated ==
    /\ wpc \in {"done", "failed"} /\ cpc = "done"
    /\ \A r \in Readers : rpc[r] = "done"

Next ==
    \/ WriterStep \/ CloserStep \/ \E r \in Readers : ReaderStep(r)
    \/ (Terminated /\ UNCHANGED vars)

(* Weak fairness for the writer and the closer. Strong fairness for the   *)
(* readers: a reader that waits for waitLock or for a permit may see it    *)
(* taken by another thread infinitely often; the JDK locks are not fair,   *)
(* so this assumes that a lock that is free again and again is eventually  *)
(* acquired.                                                               *)
Fairness ==
    /\ WF_vars(WriterStep) /\ WF_vars(CloserStep)
    /\ \A r \in Readers : SF_vars(ReaderStep(r))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Safety *)

(* No NoSuchElementException out of read() (F278). *)
NoEmptyTake == \A r \in Readers : rpc[r] # "nsee"

(* Every byte written is taken or still buffered, in FIFO order: nothing  *)
(* lost, nothing twice; availableBytes = written - read.                   *)
Fifo == written = taken \o buf

(* Each reader gets the bytes in the order they were written. *)
ReaderOrder ==
    \A r \in Readers : \A i, j \in 1..Len(got[r]) : i < j => got[r][i] < got[r][j]

(* No write returns normally after a reader reported the end (F149). *)
NoWriteAfterEof == eofAt # -1 => Len(written) = eofAt

(* Only a closed buffer reports the end, and it stays empty from then on. *)
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ buf = <<>>

(* Liveness: every reader returns, from every wait (no lost wake-up, F278). *)
AllReadersFinish == <>(\A r \in Readers : rpc[r] = "done")
=============================================================================
