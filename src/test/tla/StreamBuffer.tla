\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE StreamBuffer ----------------------------
(***************************************************************************)
(* The wait/wake-up/close protocol, the writes and the reads of            *)
(* net.ladenthin.streambuffer.StreamBuffer (TODO roadmap A5), checked with  *)
(* TLC.                                                                    *)
(*                                                                         *)
(* Threads: one writer of Bytes bytes in writes of ChunkLen bytes (the last *)
(* one shorter; each write is one FIFO entry), one closer, and the threads  *)
(* in Readers. A reader reads until a call returns -1: read() if it is in   *)
(* ByteReaders, else read(b, 0, ReadLen). A thread in WaitCallers calls     *)
(* waitForAtLeast(ReadLen) once instead. The FIFO is a sequence of entries  *)
(* (buf) with the read position in the head entry (pos); avail is          *)
(* availableBytes. Every step is one atomic action: a lock-free volatile    *)
(* read or write is a step of its own, and both locks are variables (bl for *)
(* bufferLock, wl for waitLock), so a copy under bufferLock takes one step  *)
(* per FIFO entry that a lock-free reader of avail can watch, and a signal  *)
(* cannot slip in between a waiter's increment of waitingReaders and its    *)
(* check under waitLock.                                                    *)
(*                                                                         *)
(* The constants select a code version; the code since F279 is            *)
(*   Protocol = "condition", ReCheck, AtomicRead, CountOnce, CheckedReturn: *)
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
(* - CheckedReturn: waitForAtLeast's waiting branch returns the count it   *)
(*   checked (since 2026-11-12); without it, availableBytes read again,     *)
(*   which another reader may have lowered below n on an open buffer.       *)
(* trim() merges entries; it keeps the bytes, their order and              *)
(* availableBytes, and is not modeled.                                      *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS
    Readers,     \* the reading and waiting threads (model values)
    ByteReaders, \* the readers calling read(); the others read(b, 0, ReadLen)
    WaitCallers, \* the threads calling waitForAtLeast(ReadLen) once, not reading
    Bytes,       \* how many bytes the writer attempts to write
    ChunkLen,    \* the bytes per write (one FIFO entry each)
    ReadLen,     \* the bytes one read(b, 0, len) asks for, and waitForAtLeast waits for
    Protocol,    \* "condition" (since F278) or "semaphore" (before F278)
    ReCheck,     \* the re-check of availableBytes under bufferLock (since F278)
    AtomicRead,  \* read(b, off, len) takes its bytes in one lock hold (since #212)
    CountOnce,   \* availableBytes lowered once per read, not per entry (since F279)
    CheckedReturn \* waitForAtLeast returns the count it checked (since 2026-11-12)

(* The bytes one read call of r asks for, or the bytes r's wait waits for. *)
LenOf(r) == IF r \in ByteReaders THEN 1 ELSE ReadLen

ASSUME SBAssump ==
       /\ Protocol \in {"condition", "semaphore"}
       /\ ReCheck \in BOOLEAN /\ AtomicRead \in BOOLEAN /\ CountOnce \in BOOLEAN
       /\ CheckedReturn \in BOOLEAN
       /\ Bytes \in Nat /\ ChunkLen \in Nat \ {0} /\ ReadLen \in Nat \ {0}
       /\ Readers # {} /\ ByteReaders \subseteq Readers /\ WaitCallers \subseteq Readers
       /\ ByteReaders \cap WaitCallers = {}
       \* the code without the re-check is modeled for read() only
       /\ ReCheck \/ \A r \in Readers \ WaitCallers : LenOf(r) = 1

None == "none"

VARIABLES
    buf,        \* the FIFO entries (each a nonempty sequence of bytes), in order
    pos,        \* positionAtCurrentBufferEntry: the bytes of Head(buf) already read
    avail,      \* availableBytes, the count every lock-free reader sees
    written,    \* every byte whose write returned normally, in order
    taken,      \* every byte a read committed (counted), in that order
    toff,       \* ghost: Len(taken) % ReadLen, kept linear (the A13 refinement proof)
    closed,     \* streamClosed
    nextByte,   \* the value of the writer's next byte (1, 2, ...)
    wpc,        \* the writer's program counter
    cpc,        \* the closer's program counter
    rpc,        \* rpc[r]: thread r's program counter
    want,       \* want[r]: the bytes r's current wait waits for
    cur,        \* cur[r]: the bytes of r's current read call committed so far
    hold,       \* hold[r]: the bytes r copied in its current hold of bufferLock
    left,       \* left[r]: the bytes r still copies in this hold
    reads,      \* reads[r]: the results of r's completed read calls
    wres,       \* wres[w]: what waitForAtLeast returned to w, -1 before
    wclosed,    \* wclosed[w]: streamClosed when it returned
    eofAt,      \* Len(written) when a reader first returned -1, else -1
    permits,    \* "semaphore": permits of the internal semaphore (0 or 1)
    waiters,    \* "condition": waitingReaders
    parked,     \* "condition": the threads parked in Condition.await()
    wl,         \* the holder of waitLock, or None
    bl          \* the holder of bufferLock, or None

vars == <<buf, pos, avail, written, taken, toff, closed, nextByte, wpc, cpc, rpc, want, cur,
          hold, left, reads, wres, wclosed, eofAt, permits, waiters, parked, wl, bl>>

Min(a, b) == IF a < b THEN a ELSE b

\* the concatenation of a sequence of sequences: a recursive function, not a RECURSIVE operator,
\* which tlapm cannot parse (the A13 refinement proof extends this module)
Flat(s) == LET F[i \in 0..Len(s)] == IF i = 0 THEN <<>> ELSE F[i - 1] \o s[i] IN F[Len(s)]

(* The bytes still buffered, in order. *)
BufBytes == IF buf = <<>> THEN <<>>
            ELSE SubSeq(Head(buf), pos + 1, Len(Head(buf))) \o Flat(Tail(buf))

(* The bytes reader r received, over all its completed reads. *)
Got(r) == Flat(reads[r])

ReaderStates == {"start", "reread", "acquire", "lockwait", "inc", "test", "parked",
                 "woken", "wret", "lock", "decide", "copy", "finish", "ret0", "eof",
                 "done", "nsee"}

TypeOK ==
    /\ buf \in Seq(Seq(1..Bytes)) /\ \A i \in 1..Len(buf) : buf[i] # <<>>
    /\ pos \in 0..Bytes /\ (buf # <<>> => pos < Len(Head(buf))) /\ (buf = <<>> => pos = 0)
    /\ written \in Seq(1..Bytes) /\ taken \in Seq(1..Bytes)
    /\ toff = Len(taken) % ReadLen
    /\ avail \in 0..Bytes /\ closed \in BOOLEAN /\ nextByte \in 1..(Bytes + 1)
    /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
    /\ cpc \in {"close", "sigread", "siglock", "done"}
    /\ rpc \in [Readers -> ReaderStates]
    /\ want \in [Readers -> 0..ReadLen] /\ left \in [Readers -> 0..ReadLen]
    /\ cur \in [Readers -> Seq(1..Bytes)] /\ hold \in [Readers -> Seq(1..Bytes)]
    /\ reads \in [Readers -> Seq(Seq(1..Bytes))]
    /\ wres \in [Readers -> -1..Bytes] /\ wclosed \in [Readers -> BOOLEAN]
    /\ eofAt \in -1..Bytes
    /\ permits \in 0..1 /\ waiters \in 0..Cardinality(Readers)
    /\ parked \subseteq Readers
    /\ wl \in Readers \cup {None} /\ bl \in Readers \cup {None}

Init ==
    /\ buf = <<>> /\ pos = 0 /\ avail = 0 /\ written = <<>> /\ taken = <<>> /\ toff = 0
    /\ closed = FALSE /\ nextByte = 1
    /\ wpc = "write" /\ cpc = "close"
    /\ rpc = [r \in Readers |-> "start"]
    /\ want = [r \in Readers |-> 0] /\ left = [r \in Readers |-> 0]
    /\ cur = [r \in Readers |-> <<>>] /\ hold = [r \in Readers |-> <<>>]
    /\ reads = [r \in Readers |-> <<>>]
    /\ wres = [r \in Readers |-> -1] /\ wclosed = [r \in Readers |-> FALSE]
    /\ eofAt = -1 /\ permits = 0 /\ waiters = 0 /\ parked = {} /\ wl = None /\ bl = None

ReaderVars == <<rpc, want, cur, hold, left, reads, wres, wclosed>>
Sync == <<permits, waiters, parked, wl, bl>>

(***************************************************************************)
(* The signal after a write or the close (signalModification()):          *)
(* "semaphore" releases a permit only while there is none (max 1);        *)
(* "condition" reads waitingReaders lock-free and, if it is not 0, takes  *)
(* waitLock and signals all: every parked thread becomes "woken". Taking  *)
(* waitLock, signalling and releasing it is one step here.                 *)
(***************************************************************************)
WakeAll ==
    /\ wl = None
    /\ rpc' = [r \in Readers |-> IF r \in parked THEN "woken" ELSE rpc[r]]
    /\ parked' = {}

(***************************************************************************)
(* The writer: write(b, 0, n) of the next ChunkLen bytes as one entry      *)
(* under bufferLock, failing once closed (F149), then the signal.          *)
(***************************************************************************)
WriterDone == IF nextByte > Bytes THEN "done" ELSE "write"

Chunk == [i \in 1..Min(ChunkLen, Bytes - nextByte + 1) |-> nextByte + i - 1]

WriterWrite ==
    /\ wpc = "write" /\ bl = None
    /\ IF closed
          THEN /\ wpc' = "failed"
               /\ UNCHANGED <<buf, avail, written, nextByte>>
          ELSE /\ buf' = Append(buf, Chunk)
               /\ written' = written \o Chunk
               /\ avail' = avail + Len(Chunk)
               /\ nextByte' = nextByte + Len(Chunk)
               /\ wpc' = "sigread"
    /\ UNCHANGED <<pos, taken, toff, closed, cpc, ReaderVars, eofAt, Sync>>

WriterSigRead ==
    /\ wpc = "sigread"
    /\ IF Protocol = "semaphore"
          THEN /\ permits' = 1
               /\ wpc' = WriterDone
          ELSE /\ wpc' = IF waiters # 0 THEN "siglock" ELSE WriterDone
               /\ UNCHANGED permits
    /\ UNCHANGED <<buf, pos, avail, written, taken, toff, closed, nextByte, cpc, ReaderVars, eofAt,
                   waiters, parked, wl, bl>>

WriterSigLock ==
    /\ wpc = "siglock"
    /\ WakeAll
    /\ wpc' = WriterDone
    /\ UNCHANGED <<buf, pos, avail, written, taken, toff, closed, nextByte, cpc, want, cur, hold,
                   left, reads, wres, wclosed, eofAt, permits, waiters, wl, bl>>

WriterStep == WriterWrite \/ WriterSigRead \/ WriterSigLock

(***************************************************************************)
(* The closer: close() sets streamClosed under bufferLock, then signals.  *)
(***************************************************************************)
CloserClose ==
    /\ cpc = "close" /\ bl = None
    /\ closed' = TRUE
    /\ cpc' = "sigread"
    /\ UNCHANGED <<buf, pos, avail, written, taken, toff, nextByte, wpc, ReaderVars, eofAt, Sync>>

CloserSigRead ==
    /\ cpc = "sigread"
    /\ IF Protocol = "semaphore"
          THEN /\ permits' = 1
               /\ cpc' = "done"
          ELSE /\ cpc' = IF waiters # 0 THEN "siglock" ELSE "done"
               /\ UNCHANGED permits
    /\ UNCHANGED <<buf, pos, avail, written, taken, toff, closed, nextByte, wpc, ReaderVars, eofAt,
                   waiters, parked, wl, bl>>

CloserSigLock ==
    /\ cpc = "siglock"
    /\ WakeAll
    /\ cpc' = "done"
    /\ UNCHANGED <<buf, pos, avail, written, taken, toff, closed, nextByte, wpc, want, cur, hold,
                   left, reads, wres, wclosed, eofAt, permits, waiters, wl, bl>>

CloserStep == CloserClose \/ CloserSigRead \/ CloserSigLock

(***************************************************************************)
(* A reader. A read call waits (waitForAtLeast) for want bytes, takes      *)
(* bufferLock, decides how many to copy, copies them entry by entry,       *)
(* commits them, and either returns or (two-phase read) waits again. A     *)
(* thread in WaitCallers runs the wait only and records what it returns.   *)
(***************************************************************************)
Goto(r, s) == rpc' = [rpc EXCEPT ![r] = s]

Shared == <<buf, pos, avail, written, taken, toff, closed, nextByte, wpc, cpc>>

(* waitForAtLeast returns avail to w; the snapshot also notes streamClosed. *)
Return(w) ==
    /\ wres' = [wres EXCEPT ![w] = avail]
    /\ wclosed' = [wclosed EXCEPT ![w] = closed]
    /\ Goto(w, "done")

(* What the current wait waits for: the whole read (AtomicRead), else the  *)
(* first byte (readSingleByte) and then the rest (waitForAtLeast(missing)). *)
WantNow(r) == IF AtomicRead \/ r \in WaitCallers THEN LenOf(r)
              ELSE IF cur[r] = <<>> THEN 1 ELSE LenOf(r) - Len(cur[r])

(* The lock-free fast path of the wait: enough bytes, then the returned    *)
(* count is the one just checked.                                          *)
ReaderStart(r) ==
    /\ rpc[r] = "start"
    /\ want' = [want EXCEPT ![r] = WantNow(r)]
    /\ IF avail >= WantNow(r) /\ r \in WaitCallers THEN Return(r)
       ELSE /\ IF avail >= WantNow(r) THEN Goto(r, "lock")
               ELSE IF closed THEN Goto(r, "reread")
               ELSE Goto(r, IF Protocol = "condition" THEN "lockwait" ELSE "acquire")
            /\ UNCHANGED <<wres, wclosed>>
    /\ UNCHANGED <<Shared, cur, hold, left, reads, eofAt, Sync>>

(* Closed seen: the wait returns availableBytes, read again. *)
ReaderReread(r) ==
    /\ rpc[r] = "reread"
    /\ IF r \in WaitCallers THEN Return(r)
       ELSE /\ Goto(r, IF avail >= 1 THEN "lock" ELSE "ret0")
            /\ UNCHANGED <<wres, wclosed>>
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, Sync>>

(* "semaphore": block on the semaphore, then check again (the loop). *)
ReaderAcquire(r) ==
    /\ rpc[r] = "acquire" /\ permits > 0
    /\ permits' = permits - 1
    /\ Goto(r, "start")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, eofAt, waiters, parked,
                   wl, bl>>

(* "condition": awaitAtLeast takes waitLock (again after a wake-up). *)
ReaderWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None
    /\ wl' = r
    /\ Goto(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, eofAt, permits,
                   waiters, parked, bl>>

(* "condition": waitingReaders.incrementAndGet() under waitLock. *)
ReaderInc(r) ==
    /\ rpc[r] = "inc"
    /\ waiters' = waiters + 1
    /\ Goto(r, "test")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, eofAt, permits, parked,
                   wl, bl>>

(* "condition": the loop condition under waitLock; await() parks and       *)
(* releases the lock in one step. Leaving, a reader goes on with the count  *)
(* it read; a WaitCallers thread reads availableBytes again to return it.   *)
ReaderTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= want[r] \/ closed
          THEN IF r \in WaitCallers
                  \* CheckedReturn: enough bytes, return the count just checked
                  THEN IF CheckedReturn /\ avail >= want[r]
                          THEN /\ Return(r)
                               /\ waiters' = waiters - 1
                               /\ wl' = None
                               /\ UNCHANGED parked
                          ELSE /\ Goto(r, "wret")
                               /\ UNCHANGED <<waiters, parked, wl, wres, wclosed>>
                  ELSE /\ waiters' = waiters - 1
                       /\ Goto(r, IF avail >= 1 THEN "lock" ELSE "ret0")
                       /\ wl' = None
                       /\ UNCHANGED <<parked, wres, wclosed>>
          ELSE /\ parked' = parked \cup {r}
               /\ Goto(r, "parked")
               /\ wl' = None
               /\ UNCHANGED <<waiters, wres, wclosed>>
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, bl>>

(* "condition": return availableBytes, still under waitLock, then the      *)
(* finally block (waitingReaders.decrementAndGet(), unlock).               *)
ReaderWaitReturn(r) ==
    /\ rpc[r] = "wret" /\ wl = r
    /\ Return(r)
    /\ waiters' = waiters - 1
    /\ wl' = None
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, eofAt, permits, parked, bl>>

(* Take bufferLock. *)
ReaderLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None
    /\ bl' = r
    /\ Goto(r, "decide")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, eofAt, permits,
                   waiters, parked, wl>>

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
          \* since #212: all bytes of the read, or what is left of a closed stream
          THEN IF avail >= LenOf(r) \/ (closed /\ avail > 0)
                  THEN /\ left' = [left EXCEPT ![r] = Min(avail, LenOf(r))]
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
    /\ UNCHANGED <<Shared, want, cur, hold, reads, wres, wclosed, eofAt, permits, waiters,
                   parked, wl>>

(* Under bufferLock: copy from the head entry, at most what is left of it   *)
(* (one turn of the copy loop); a fully read entry is removed. Before F279  *)
(* the count went down per entry.                                           *)
ReaderCopy(r) ==
    /\ rpc[r] = "copy" /\ bl = r /\ left[r] > 0
    /\ LET e == Head(buf)
           k == Min(left[r], Len(e) - pos)
       IN /\ hold' = [hold EXCEPT ![r] = @ \o SubSeq(e, pos + 1, pos + k)]
          /\ IF pos + k = Len(e)
                THEN /\ buf' = Tail(buf)
                     /\ pos' = 0
                ELSE /\ pos' = pos + k
                     /\ UNCHANGED buf
          /\ avail' = IF CountOnce THEN avail ELSE avail - k
          /\ left' = [left EXCEPT ![r] = @ - k]
          /\ Goto(r, IF left[r] = k THEN "finish" ELSE "copy")
    /\ UNCHANGED <<written, taken, toff, closed, nextByte, wpc, cpc, want, cur, reads, wres,
                   wclosed, eofAt, Sync>>

(* Under bufferLock: commit the copied bytes (since F279 also the count),  *)
(* release the lock; the read returns, or the two-phase read goes on.      *)
ReaderFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ taken' = taken \o hold[r]
    \* the ghost: a read of a ReadLen-byte record or less (the two-phase read: cur and hold)
    /\ toff' = IF toff + Len(hold[r]) >= ReadLen THEN toff + Len(hold[r]) - ReadLen
              ELSE toff + Len(hold[r])
    /\ avail' = IF CountOnce THEN avail - Len(hold[r]) ELSE avail
    /\ LET c == cur[r] \o hold[r] IN
          IF AtomicRead \/ Len(c) = LenOf(r)
             THEN /\ reads' = [reads EXCEPT ![r] = Append(@, c)]
                  /\ cur' = [cur EXCEPT ![r] = <<>>]
             ELSE /\ cur' = [cur EXCEPT ![r] = c]
                  /\ UNCHANGED reads
    /\ hold' = [hold EXCEPT ![r] = <<>>]
    /\ bl' = None
    /\ Goto(r, "start")
    /\ UNCHANGED <<buf, pos, written, closed, nextByte, wpc, cpc, want, left, wres, wclosed,
                   eofAt, permits, waiters, parked, wl>>

(* The wait returned 0 (closed and empty): -1, or the short read so far.   *)
ReaderRet0(r) ==
    /\ rpc[r] = "ret0"
    /\ IF cur[r] = <<>>
          THEN /\ Goto(r, "eof")
               /\ UNCHANGED <<cur, reads>>
          ELSE /\ reads' = [reads EXCEPT ![r] = Append(@, cur[r])]
               /\ cur' = [cur EXCEPT ![r] = <<>>]
               /\ Goto(r, "start")
    /\ UNCHANGED <<Shared, want, hold, left, wres, wclosed, eofAt, Sync>>

(* The read returns -1. *)
ReaderEof(r) ==
    /\ rpc[r] = "eof"
    /\ eofAt' = IF eofAt = -1 THEN Len(written) ELSE eofAt
    /\ Goto(r, "done")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, Sync>>

ReaderStep(r) ==
    \/ ReaderStart(r) \/ ReaderReread(r) \/ ReaderAcquire(r) \/ ReaderWaitLock(r)
    \/ ReaderInc(r) \/ ReaderTest(r) \/ ReaderWaitReturn(r) \/ ReaderLock(r)
    \/ ReaderDecide(r) \/ ReaderCopy(r) \/ ReaderFinish(r) \/ ReaderRet0(r) \/ ReaderEof(r)

Terminated ==
    /\ wpc \in {"done", "failed"} /\ cpc = "done"
    /\ \A r \in Readers : rpc[r] = "done"

Next ==
    \/ WriterStep \/ CloserStep \/ \E r \in Readers : ReaderStep(r)
    \/ (Terminated /\ UNCHANGED vars)

(* Weak fairness for every thread: a thread that can go on all the time    *)
(* eventually does (the scheduler runs a runnable thread). No lock         *)
(* fairness: a thread that keeps finding a lock taken may never get it, as  *)
(* the JDK's monitor and ReentrantLock(false) allow. Until 2026-11-13 the   *)
(* readers had strong fairness (fair locks); every model of the current    *)
(* code checks with weak fairness too.                                     *)
Fairness ==
    /\ WF_vars(WriterStep) /\ WF_vars(CloserStep)
    /\ \A r \in Readers : WF_vars(ReaderStep(r))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Safety *)

(* No NoSuchElementException out of read() (F278). *)
NoEmptyTake == \A r \in Readers : rpc[r] # "nsee"

(* Every byte written is committed, being copied, or still buffered, in    *)
(* FIFO order: nothing lost, nothing twice.                                *)
InFlight == IF bl \in Readers THEN hold[bl] ELSE <<>>
Fifo == written = taken \o InFlight \o BufBytes

(* The count a lock-free reader sees (available(), getAvailableBytesExact(),*)
(* the fast path of the wait) is always that of a state between two         *)
(* operations: before the read under bufferLock, or after all of it, never  *)
(* in the middle of it (F279). The read in flight takes Len(hold) + left    *)
(* bytes in all.                                                            *)
AvailLinearizable ==
    LET d == Len(written) - Len(taken) - avail IN
        \/ d = 0
        \/ bl \in Readers /\ d = Len(hold[bl]) + left[bl]

(* Each reader gets the bytes in the order they were written. *)
ReaderOrder ==
    \A r \in Readers : \A i, j \in 1..Len(Got(r)) : i < j => Got(r)[i] < Got(r)[j]

(* Each read returns consecutive bytes, as many as it asked for or fewer   *)
(* only from a closed buffer; with readers of one size only, a whole       *)
(* aligned record (#212).                                                  *)
RecordsWhole ==
    \A r \in Readers : \A k \in 1..Len(reads[r]) :
        LET c == reads[r][k] IN
            /\ c # <<>> /\ Len(c) <= LenOf(r)
            /\ \A i \in 1..(Len(c) - 1) : c[i + 1] = c[i] + 1
            /\ Len(c) < LenOf(r) => closed
            /\ (ByteReaders = {} /\ Len(c) = ReadLen) => (c[1] - 1) % ReadLen = 0

(* waitForAtLeast(n) returns fewer than n bytes only for a closed buffer    *)
(* (its JML postcondition). Before CheckedReturn the waiting branch read    *)
(* availableBytes again for the result, and a reader next to it could have  *)
(* lowered it below n on an open buffer (the WaitSnapshot2 model).          *)
WaitEnoughOrClosed ==
    \A w \in WaitCallers : wres[w] # -1 => wres[w] >= ReadLen \/ wclosed[w]

(* No write returns normally after a reader reported the end (F149). *)
NoWriteAfterEof == eofAt # -1 => Len(written) = eofAt

(* Only a closed buffer reports the end, and it stays empty from then on. *)
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ buf = <<>> /\ avail = 0

(* Liveness: every reader and every waitForAtLeast call returns, from      *)
(* every wait (no lost wake-up, F278).                                     *)
AllReadersFinish == <>(\A r \in Readers : rpc[r] = "done")
=============================================================================
