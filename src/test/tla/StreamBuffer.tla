\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE StreamBuffer ----------------------------
(***************************************************************************)
(* The wait/wake-up/close protocol and the reads of                        *)
(* net.ladenthin.streambuffer.StreamBuffer (TODO roadmap A5), checked with  *)
(* TLC.                                                                    *)
(*                                                                         *)
(* Threads: one writer of Bytes single-byte writes, one closer, and the     *)
(* readers in Readers, each reading ReadLen bytes per call (read() for 1,   *)
(* read(b, 0, ReadLen) otherwise) until a call returns -1. The FIFO is      *)
(* abstracted to its bytes (buf); avail is availableBytes. Every step is    *)
(* one atomic action: a lock-free volatile read or write is a step of its   *)
(* own, and both locks are variables (bl for bufferLock, wl for waitLock),  *)
(* so a copy under bufferLock may take several steps that a lock-free       *)
(* reader of avail can watch, and a signal cannot slip in between a         *)
(* waiter's increment of waitingReaders and its check under waitLock.       *)
(*                                                                         *)
(* The constants select a code version; the code since F279 is            *)
(*   Protocol = "condition", ReCheck, AtomicRead, CountOnce:                *)
(* - Protocol: "condition" is the wait since bug-hunt finding F278 (a      *)
(*   Condition on waitLock with signalAll, waitingReaders lets a write skip *)
(*   the lock while nobody waits); "semaphore" is the wait before it (a     *)
(*   Semaphore released only while it has no permit).                       *)
(* - ReCheck: a reader checks availableBytes again under bufferLock before *)
(*   it takes bytes (since F278; before it, getFirst() on an empty deque).  *)
(*   F278 had both causes; ReCheck separates them.                          *)
(* - AtomicRead: read(b, off, len) waits until len bytes are buffered and  *)
(*   takes them in one hold of bufferLock (since #212); without it, it took *)
(*   the first byte, released the lock and waited for the rest.             *)
(* - CountOnce: availableBytes is lowered once per read, after the copy    *)
(*   (since F279); without it, per FIFO entry during the copy.              *)
(* trim() keeps availableBytes and the byte order, so it is a no-op here.   *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS
    Readers,    \* the reader threads (model values)
    Bytes,      \* how many single-byte writes the writer attempts
    ReadLen,    \* the bytes one read call asks for
    Protocol,   \* "condition" (since F278) or "semaphore" (before F278)
    ReCheck,    \* the re-check of availableBytes under bufferLock (since F278)
    AtomicRead, \* read(b, off, len) takes its bytes in one lock hold (since #212)
    CountOnce   \* availableBytes lowered once per read, not per entry (since F279)

ASSUME /\ Protocol \in {"condition", "semaphore"}
       /\ ReCheck \in BOOLEAN /\ AtomicRead \in BOOLEAN /\ CountOnce \in BOOLEAN
       /\ Bytes \in Nat /\ ReadLen \in Nat \ {0} /\ Readers # {}
       \* the code without the re-check is modeled for read() only
       /\ ReCheck \/ ReadLen = 1

None == "none"

VARIABLES
    buf,        \* the buffered bytes in FIFO order
    avail,      \* availableBytes, the count every lock-free reader sees
    written,    \* every byte whose write returned normally, in order
    taken,      \* every byte a read committed (counted), in that order
    closed,     \* streamClosed
    nextByte,   \* the value of the writer's next byte (1, 2, ...)
    wpc,        \* the writer's program counter
    cpc,        \* the closer's program counter
    rpc,        \* rpc[r]: reader r's program counter
    want,       \* want[r]: the bytes reader r's current wait waits for
    cur,        \* cur[r]: the bytes of r's current read call committed so far
    hold,       \* hold[r]: the bytes r copied in its current hold of bufferLock
    left,       \* left[r]: the bytes r still copies in this hold
    reads,      \* reads[r]: the results of r's completed read calls
    eofAt,      \* Len(written) when a reader first returned -1, else -1
    permits,    \* "semaphore": permits of the internal semaphore (0 or 1)
    waiters,    \* "condition": waitingReaders
    parked,     \* "condition": the readers parked in Condition.await()
    wl,         \* the holder of waitLock, or None
    bl          \* the holder of bufferLock, or None

vars == <<buf, avail, written, taken, closed, nextByte, wpc, cpc, rpc, want, cur,
          hold, left, reads, eofAt, permits, waiters, parked, wl, bl>>

Min(a, b) == IF a < b THEN a ELSE b

RECURSIVE Flat(_)
Flat(s) == IF s = <<>> THEN <<>> ELSE Head(s) \o Flat(Tail(s))

(* The bytes reader r received, over all its completed reads. *)
Got(r) == Flat(reads[r])

ReaderStates == {"start", "reread", "acquire", "lockwait", "inc", "test", "parked",
                 "woken", "lock", "decide", "copy", "finish", "ret0", "eof", "done",
                 "nsee"}

TypeOK ==
    /\ buf \in Seq(1..Bytes) /\ written \in Seq(1..Bytes) /\ taken \in Seq(1..Bytes)
    /\ avail \in 0..Bytes /\ closed \in BOOLEAN /\ nextByte \in 1..(Bytes + 1)
    /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
    /\ cpc \in {"close", "sigread", "siglock", "done"}
    /\ rpc \in [Readers -> ReaderStates]
    /\ want \in [Readers -> 0..ReadLen] /\ left \in [Readers -> 0..ReadLen]
    /\ cur \in [Readers -> Seq(1..Bytes)] /\ hold \in [Readers -> Seq(1..Bytes)]
    /\ reads \in [Readers -> Seq(Seq(1..Bytes))]
    /\ eofAt \in -1..Bytes
    /\ permits \in 0..1 /\ waiters \in 0..Cardinality(Readers)
    /\ parked \subseteq Readers
    /\ wl \in Readers \cup {None} /\ bl \in Readers \cup {None}

Init ==
    /\ buf = <<>> /\ avail = 0 /\ written = <<>> /\ taken = <<>>
    /\ closed = FALSE /\ nextByte = 1
    /\ wpc = "write" /\ cpc = "close"
    /\ rpc = [r \in Readers |-> "start"]
    /\ want = [r \in Readers |-> 0] /\ left = [r \in Readers |-> 0]
    /\ cur = [r \in Readers |-> <<>>] /\ hold = [r \in Readers |-> <<>>]
    /\ reads = [r \in Readers |-> <<>>]
    /\ eofAt = -1 /\ permits = 0 /\ waiters = 0 /\ parked = {} /\ wl = None /\ bl = None

ReaderVars == <<rpc, want, cur, hold, left, reads>>

(***************************************************************************)
(* The signal after a write or the close (signalModification()):          *)
(* "semaphore" releases a permit only while there is none (max 1);        *)
(* "condition" reads waitingReaders lock-free and, if it is not 0, takes  *)
(* waitLock and signals all: every parked reader becomes "woken". Taking  *)
(* waitLock, signalling and releasing it is one step here.                 *)
(***************************************************************************)
WakeAll ==
    /\ wl = None
    /\ rpc' = [r \in Readers |-> IF r \in parked THEN "woken" ELSE rpc[r]]
    /\ parked' = {}

(***************************************************************************)
(* The writer: write(int) under bufferLock, failing once closed (F149),   *)
(* then the signal.                                                        *)
(***************************************************************************)
WriterDone == IF nextByte > Bytes THEN "done" ELSE "write"

WriterWrite ==
    /\ wpc = "write" /\ bl = None
    /\ IF closed
          THEN /\ wpc' = "failed"
               /\ UNCHANGED <<buf, avail, written, nextByte>>
          ELSE /\ buf' = Append(buf, nextByte)
               /\ written' = Append(written, nextByte)
               /\ avail' = avail + 1
               /\ nextByte' = nextByte + 1
               /\ wpc' = "sigread"
    /\ UNCHANGED <<taken, closed, cpc, ReaderVars, eofAt, permits, waiters, parked, wl, bl>>

WriterSigRead ==
    /\ wpc = "sigread"
    /\ IF Protocol = "semaphore"
          THEN /\ permits' = 1
               /\ wpc' = WriterDone
          ELSE /\ wpc' = IF waiters # 0 THEN "siglock" ELSE WriterDone
               /\ UNCHANGED permits
    /\ UNCHANGED <<buf, avail, written, taken, closed, nextByte, cpc, ReaderVars, eofAt,
                   waiters, parked, wl, bl>>

WriterSigLock ==
    /\ wpc = "siglock"
    /\ WakeAll
    /\ wpc' = WriterDone
    /\ UNCHANGED <<buf, avail, written, taken, closed, nextByte, cpc, want, cur, hold, left,
                   reads, eofAt, permits, waiters, wl, bl>>

WriterStep == WriterWrite \/ WriterSigRead \/ WriterSigLock

(***************************************************************************)
(* The closer: close() sets streamClosed under bufferLock, then signals.  *)
(***************************************************************************)
CloserClose ==
    /\ cpc = "close" /\ bl = None
    /\ closed' = TRUE
    /\ cpc' = "sigread"
    /\ UNCHANGED <<buf, avail, written, taken, nextByte, wpc, ReaderVars, eofAt, permits,
                   waiters, parked, wl, bl>>

CloserSigRead ==
    /\ cpc = "sigread"
    /\ IF Protocol = "semaphore"
          THEN /\ permits' = 1
               /\ cpc' = "done"
          ELSE /\ cpc' = IF waiters # 0 THEN "siglock" ELSE "done"
               /\ UNCHANGED permits
    /\ UNCHANGED <<buf, avail, written, taken, closed, nextByte, wpc, ReaderVars, eofAt,
                   waiters, parked, wl, bl>>

CloserSigLock ==
    /\ cpc = "siglock"
    /\ WakeAll
    /\ cpc' = "done"
    /\ UNCHANGED <<buf, avail, written, taken, closed, nextByte, wpc, want, cur, hold, left,
                   reads, eofAt, permits, waiters, wl, bl>>

CloserStep == CloserClose \/ CloserSigRead \/ CloserSigLock

(***************************************************************************)
(* A reader. A read call waits (waitForAtLeast) for want bytes, takes      *)
(* bufferLock, decides how many to copy, copies them entry by entry,       *)
(* commits them, and either returns or (two-phase read) waits again.       *)
(***************************************************************************)
Goto(r, s) == rpc' = [rpc EXCEPT ![r] = s]

Shared == <<buf, avail, written, taken, closed, nextByte, wpc, cpc>>

(* What the current wait waits for: the whole read (AtomicRead), else the  *)
(* first byte (readSingleByte) and then the rest (waitForAtLeast(missing)). *)
WantNow(r) == IF AtomicRead THEN ReadLen
              ELSE IF cur[r] = <<>> THEN 1 ELSE ReadLen - Len(cur[r])

(* The lock-free fast path of the wait. *)
ReaderStart(r) ==
    /\ rpc[r] = "start"
    /\ want' = [want EXCEPT ![r] = WantNow(r)]
    /\ IF avail >= WantNow(r) THEN Goto(r, "lock")
       ELSE IF closed THEN Goto(r, "reread")
       ELSE Goto(r, IF Protocol = "condition" THEN "lockwait" ELSE "acquire")
    /\ UNCHANGED <<Shared, cur, hold, left, reads, eofAt, permits, waiters, parked, wl, bl>>

(* Closed seen: the wait returns availableBytes, read again. *)
ReaderReread(r) ==
    /\ rpc[r] = "reread"
    /\ Goto(r, IF avail >= 1 THEN "lock" ELSE "ret0")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, waiters, parked, wl, bl>>

(* "semaphore": block on the semaphore, then check again (the loop). *)
ReaderAcquire(r) ==
    /\ rpc[r] = "acquire" /\ permits > 0
    /\ permits' = permits - 1
    /\ Goto(r, "start")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, waiters, parked, wl, bl>>

(* "condition": awaitAtLeast takes waitLock (again after a wake-up). *)
ReaderWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None
    /\ wl' = r
    /\ Goto(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, waiters, parked, bl>>

(* "condition": waitingReaders.incrementAndGet() under waitLock. *)
ReaderInc(r) ==
    /\ rpc[r] = "inc"
    /\ waiters' = waiters + 1
    /\ Goto(r, "test")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, parked, wl, bl>>

(* "condition": the loop condition under waitLock; await() parks and       *)
(* releases the lock in one step; leaving returns availableBytes.          *)
ReaderTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= want[r] \/ closed
          THEN /\ waiters' = waiters - 1
               /\ Goto(r, IF avail >= 1 THEN "lock" ELSE "ret0")
               /\ UNCHANGED parked
          ELSE /\ parked' = parked \cup {r}
               /\ Goto(r, "parked")
               /\ UNCHANGED waiters
    /\ wl' = None
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, bl>>

(* Take bufferLock. *)
ReaderLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None
    /\ bl' = r
    /\ Goto(r, "decide")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, waiters, parked, wl>>

(* Under bufferLock: how many bytes to copy, or release and wait again.   *)
ReaderDecide(r) ==
    /\ rpc[r] = "decide" /\ bl = r
    /\ IF ~ReCheck
          \* before F278: getFirst() without a check
          THEN IF buf = <<>>
                  THEN /\ Goto(r, "nsee")
                       /\ UNCHANGED <<left, bl>>
                  ELSE /\ left' = [left EXCEPT ![r] = 1]
                       /\ Goto(r, "copy")
                       /\ UNCHANGED bl
       ELSE IF AtomicRead
          \* since #212: all ReadLen bytes, or what is left of a closed stream
          THEN IF avail >= ReadLen \/ (closed /\ avail > 0)
                  THEN /\ left' = [left EXCEPT ![r] = Min(avail, ReadLen)]
                       /\ Goto(r, "copy")
                       /\ UNCHANGED bl
                  ELSE /\ bl' = None
                       /\ Goto(r, "start")
                       /\ UNCHANGED left
          \* before #212: copy what is there of what this phase wants
          ELSE LET n == Min(avail, WantNow(r)) IN
               IF n > 0
                  THEN /\ left' = [left EXCEPT ![r] = n]
                       /\ Goto(r, "copy")
                       /\ UNCHANGED bl
                  ELSE /\ bl' = None
                       /\ Goto(r, "start")
                       /\ UNCHANGED left
    /\ UNCHANGED <<Shared, want, cur, hold, reads, eofAt, permits, waiters, parked, wl>>

(* Under bufferLock: copy one FIFO entry (one byte); before F279 the count  *)
(* went down per entry.                                                    *)
ReaderCopy(r) ==
    /\ rpc[r] = "copy" /\ bl = r /\ left[r] > 0
    /\ hold' = [hold EXCEPT ![r] = Append(@, Head(buf))]
    /\ buf' = Tail(buf)
    /\ avail' = IF CountOnce THEN avail ELSE avail - 1
    /\ left' = [left EXCEPT ![r] = @ - 1]
    /\ Goto(r, IF left[r] = 1 THEN "finish" ELSE "copy")
    /\ UNCHANGED <<written, taken, closed, nextByte, wpc, cpc, want, cur, reads, eofAt,
                   permits, waiters, parked, wl, bl>>

(* Under bufferLock: commit the copied bytes (since F279 also the count),  *)
(* release the lock; the read returns, or the two-phase read goes on.      *)
ReaderFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ taken' = taken \o hold[r]
    /\ avail' = IF CountOnce THEN avail - Len(hold[r]) ELSE avail
    /\ LET c == cur[r] \o hold[r] IN
          IF AtomicRead \/ Len(c) = ReadLen
             THEN /\ reads' = [reads EXCEPT ![r] = Append(@, c)]
                  /\ cur' = [cur EXCEPT ![r] = <<>>]
             ELSE /\ cur' = [cur EXCEPT ![r] = c]
                  /\ UNCHANGED reads
    /\ hold' = [hold EXCEPT ![r] = <<>>]
    /\ bl' = None
    /\ Goto(r, "start")
    /\ UNCHANGED <<buf, written, closed, nextByte, wpc, cpc, want, left, eofAt, permits,
                   waiters, parked, wl>>

(* The wait returned 0 (closed and empty): -1, or the short read so far.   *)
ReaderRet0(r) ==
    /\ rpc[r] = "ret0"
    /\ IF cur[r] = <<>>
          THEN /\ Goto(r, "eof")
               /\ UNCHANGED <<cur, reads>>
          ELSE /\ reads' = [reads EXCEPT ![r] = Append(@, cur[r])]
               /\ cur' = [cur EXCEPT ![r] = <<>>]
               /\ Goto(r, "start")
    /\ UNCHANGED <<Shared, want, hold, left, eofAt, permits, waiters, parked, wl, bl>>

(* The read returns -1. *)
ReaderEof(r) ==
    /\ rpc[r] = "eof"
    /\ eofAt' = IF eofAt = -1 THEN Len(written) ELSE eofAt
    /\ Goto(r, "done")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, permits, waiters, parked, wl, bl>>

ReaderStep(r) ==
    \/ ReaderStart(r) \/ ReaderReread(r) \/ ReaderAcquire(r) \/ ReaderWaitLock(r)
    \/ ReaderInc(r) \/ ReaderTest(r) \/ ReaderLock(r) \/ ReaderDecide(r)
    \/ ReaderCopy(r) \/ ReaderFinish(r) \/ ReaderRet0(r) \/ ReaderEof(r)

Terminated ==
    /\ wpc \in {"done", "failed"} /\ cpc = "done"
    /\ \A r \in Readers : rpc[r] = "done"

Next ==
    \/ WriterStep \/ CloserStep \/ \E r \in Readers : ReaderStep(r)
    \/ (Terminated /\ UNCHANGED vars)

(* Weak fairness for the writer and the closer, strong for the readers: a  *)
(* reader that keeps finding a lock or permit taken eventually gets it (the *)
(* JDK locks are not fair, so this is an assumption).                      *)
Fairness ==
    /\ WF_vars(WriterStep) /\ WF_vars(CloserStep)
    /\ \A r \in Readers : SF_vars(ReaderStep(r))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Safety *)

(* No NoSuchElementException out of read() (F278). *)
NoEmptyTake == \A r \in Readers : rpc[r] # "nsee"

(* Every byte written is committed, being copied, or still buffered, in    *)
(* FIFO order: nothing lost, nothing twice.                                *)
InFlight == IF bl \in Readers THEN hold[bl] ELSE <<>>
Fifo == written = taken \o InFlight \o buf

(* The count a lock-free reader sees (available(), getAvailableBytesExact(),*)
(* the fast path of the wait) is always that of a state between two         *)
(* operations, never one in the middle of a read (F279).                     *)
AvailLinearizable == avail = Len(written) - Len(taken)

(* Each reader gets the bytes in the order they were written. *)
ReaderOrder ==
    \A r \in Readers : \A i, j \in 1..Len(Got(r)) : i < j => Got(r)[i] < Got(r)[j]

(* Each read returns consecutive bytes, a whole aligned record of ReadLen   *)
(* bytes, or fewer only from a closed buffer (#212).                        *)
RecordsWhole ==
    \A r \in Readers : \A k \in 1..Len(reads[r]) :
        LET c == reads[r][k] IN
            /\ c # <<>>
            /\ \A i \in 1..(Len(c) - 1) : c[i + 1] = c[i] + 1
            /\ Len(c) = ReadLen => (c[1] - 1) % ReadLen = 0
            /\ Len(c) < ReadLen => closed

(* No write returns normally after a reader reported the end (F149). *)
NoWriteAfterEof == eofAt # -1 => Len(written) = eofAt

(* Only a closed buffer reports the end, and it stays empty from then on. *)
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ buf = <<>> /\ avail = 0

(* Liveness: every reader returns, from every wait (no lost wake-up, F278). *)
AllReadersFinish == <>(\A r \in Readers : rpc[r] = "done")
=============================================================================
