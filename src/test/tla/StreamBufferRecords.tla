\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

-------------------------- MODULE StreamBufferRecords --------------------------
(***************************************************************************)
(* A counter abstraction of the record configuration of StreamBuffer.tla   *)
(* (TODO roadmap A13): readers 1..N calling read(b, 0, K) until -1, one    *)
(* writer of Bytes single-byte writes (one FIFO entry each), a closer, the  *)
(* code since F279 (Condition, re-check under bufferLock, the count lowered *)
(* once per read). Counts as in StreamBufferCounters: w written, t          *)
(* committed; per reader hold (bytes copied in this lock hold), left (bytes *)
(* still to copy in it) and cur (bytes of the current call committed before,*)
(* only for the two-phase read before #212). Bytes and K stay symbolic.     *)
(* AtomicRead: read(b, off, len) takes all its bytes in one hold (#212);    *)
(* without it, the first byte, then the rest in a second hold.              *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
    \* @type: Int;
    N,
    \* @type: Int;
    Bytes,
    \* @type: Int;
    K,
    \* @type: Bool;
    AtomicRead

VARIABLES
    \* @type: Int;
    w,
    \* @type: Int;
    t,
    \* @type: Int;
    avail,
    \* @type: Bool;
    closed,
    \* @type: Str;
    wpc,
    \* @type: Str;
    cpc,
    \* @type: Int -> Str;
    rpc,
    \* @type: Int -> Int;
    hold,
    \* @type: Int -> Int;
    left,
    \* @type: Int -> Int;
    cur,
    \* @type: Int;
    off,
    \* @type: Int;
    eofAt,
    \* @type: Set(Int);
    parked,
    \* @type: Int;
    wl,
    \* @type: Int;
    bl

vars == <<w, t, avail, closed, wpc, cpc, rpc, hold, left, cur, off, eofAt, parked, wl, bl>>

Readers == 1..N
None == 0
Min(a, b) == IF a < b THEN a ELSE b

\* Apalache: the constants of a check -- N readers, any record size, any number of bytes
ConstInit == N = 2 /\ Bytes \in Nat /\ Bytes >= 1 /\ K \in Nat /\ K >= 1 /\ AtomicRead = TRUE
ConstInit3 == N = 3 /\ Bytes \in Nat /\ Bytes >= 1 /\ K \in Nat /\ K >= 1 /\ AtomicRead = TRUE
ConstInit4 == N = 4 /\ Bytes \in Nat /\ Bytes >= 1 /\ K \in Nat /\ K >= 1 /\ AtomicRead = TRUE
\* the read before #212 (two phases): the invariant is not inductive
ConstInitTwoPhase == N = 2 /\ Bytes \in Nat /\ Bytes >= 1 /\ K \in Nat /\ K >= 2 /\ AtomicRead = FALSE

States == {"start", "reread", "lockwait", "inc", "test", "parked", "woken", "lock",
           "decide", "copy", "finish", "ret0", "done", "nsee"}

InFlight == IF bl = None THEN 0 ELSE hold[bl]
Buffered == w - t - InFlight
\* what the current wait waits for: the whole record, or (two-phase) first byte, then the rest
Want(r) == IF AtomicRead THEN K ELSE IF cur[r] = 0 THEN 1 ELSE K - cur[r]

Init ==
    /\ w = 0 /\ t = 0 /\ avail = 0 /\ closed = FALSE
    /\ wpc = "write" /\ cpc = "close"
    /\ rpc = [r \in Readers |-> "start"]
    /\ hold = [r \in Readers |-> 0] /\ left = [r \in Readers |-> 0] /\ cur = [r \in Readers |-> 0]
    /\ off = 0 /\ eofAt = -1 /\ parked = {} /\ wl = None /\ bl = None

\* waitingReaders steers only whether a signal is skipped; safety does not depend on it, so the
\* abstraction has no count: with nobody parked the signal does nothing and needs no lock (the
\* code skips it then, waitingReaders being 0), else it takes waitLock and wakes every parked reader
WriterNext == IF w >= Bytes THEN "done" ELSE "write"
WakeAll ==
    IF parked = {}
       THEN UNCHANGED <<rpc, parked>>
       ELSE /\ wl = None
            /\ rpc' = [r \in Readers |-> IF r \in parked THEN "woken" ELSE rpc[r]]
            /\ parked' = {}

WriterWrite ==
    /\ wpc = "write" /\ bl = None
    /\ IF closed
          THEN /\ wpc' = "failed" /\ UNCHANGED <<w, avail>>
          \* one write of c bytes, one FIFO entry: any chunking of the Bytes bytes
          ELSE /\ \E c \in 1..(Bytes - w) : w' = w + c /\ avail' = avail + c
               /\ wpc' = "siglock"
    /\ UNCHANGED <<off, t, closed, cpc, rpc, hold, left, cur, eofAt, parked, wl, bl>>

WriterSigLock ==
    /\ wpc = "siglock" /\ WakeAll /\ wpc' = WriterNext
    /\ UNCHANGED <<off, w, t, avail, closed, cpc, hold, left, cur, eofAt, wl, bl>>

CloserClose ==
    /\ cpc = "close" /\ bl = None /\ closed' = TRUE /\ cpc' = "siglock"
    /\ UNCHANGED <<off, w, t, avail, wpc, rpc, hold, left, cur, eofAt, parked, wl, bl>>

CloserSigLock ==
    /\ cpc = "siglock" /\ WakeAll /\ cpc' = "done"
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, hold, left, cur, eofAt, wl, bl>>

Go(r, s) == rpc' = [rpc EXCEPT ![r] = s]

ReaderStart(r) ==
    /\ rpc[r] = "start"
    /\ Go(r, IF avail >= Want(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, parked, wl, bl>>

ReaderReread(r) ==
    /\ rpc[r] = "reread" /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, parked, wl, bl>>

ReaderWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None /\ wl' = r
    /\ Go(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, parked, bl>>

ReaderInc(r) ==
    /\ rpc[r] = "inc" /\ Go(r, "test")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, parked, wl, bl>>

ReaderTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= Want(r) \/ closed
          THEN /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0") /\ UNCHANGED parked
          ELSE /\ parked' = parked \cup {r} /\ Go(r, "parked")
    /\ wl' = None
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, bl>>

ReaderLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None /\ bl' = r /\ Go(r, "decide")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, cur, eofAt, parked, wl>>

\* under bufferLock: how many bytes to copy (the re-check), or release and wait again
ReaderDecide(r) ==
    /\ rpc[r] = "decide" /\ bl = r
    /\ LET n == IF AtomicRead
                   THEN IF avail >= K \/ (closed /\ avail > 0) THEN Min(avail, K) ELSE 0
                   ELSE Min(avail, Want(r))
       IN IF n > 0
             THEN /\ left' = [left EXCEPT ![r] = n] /\ Go(r, "copy") /\ UNCHANGED bl
             ELSE /\ Go(r, "start") /\ bl' = None /\ UNCHANGED left
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, cur, eofAt, parked, wl>>

\* under bufferLock: one turn of the copy loop takes the rest of the head entry, k bytes; any k
\* from 1 to what is left, so every chunking of the writes is covered (a FIFO entry per write)
ReaderCopy(r) ==
    /\ rpc[r] = "copy" /\ bl = r
    /\ IF Buffered = 0
          THEN /\ Go(r, "nsee") /\ UNCHANGED <<hold, left>>
          ELSE \E k \in 1..left[r] :
                  /\ k <= Buffered
                  /\ hold' = [hold EXCEPT ![r] = @ + k] /\ left' = [left EXCEPT ![r] = @ - k]
                  /\ Go(r, IF left[r] = k THEN "finish" ELSE "copy")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, cur, eofAt, parked, wl, bl>>

\* under bufferLock: commit the bytes and the count, release; the read returns or goes on
ReaderFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ t' = t + hold[r] /\ avail' = avail - hold[r]
    \* ghost: the bytes of the current record committed so far (t % K, kept linear)
    /\ off' = IF off + hold[r] >= K THEN off + hold[r] - K ELSE off + hold[r]
    /\ cur' = [cur EXCEPT ![r] = IF AtomicRead \/ cur[r] + hold[r] = K THEN 0 ELSE cur[r] + hold[r]]
    /\ hold' = [hold EXCEPT ![r] = 0] /\ bl' = None /\ Go(r, "start")
    /\ UNCHANGED <<w, closed, wpc, cpc, left, eofAt, parked, wl>>

\* the wait returned 0 (closed and empty): -1, or (two-phase) the short read so far
ReaderRet0(r) ==
    /\ rpc[r] = "ret0"
    /\ IF cur[r] = 0
          THEN /\ eofAt' = (IF eofAt = -1 THEN w ELSE eofAt) /\ Go(r, "done") /\ UNCHANGED cur
          ELSE /\ cur' = [cur EXCEPT ![r] = 0] /\ Go(r, "start") /\ UNCHANGED eofAt
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, left, parked, wl, bl>>

ReaderStep(r) ==
    \/ ReaderStart(r) \/ ReaderReread(r) \/ ReaderWaitLock(r) \/ ReaderInc(r)
    \/ ReaderTest(r) \/ ReaderLock(r) \/ ReaderDecide(r) \/ ReaderCopy(r)
    \/ ReaderFinish(r) \/ ReaderRet0(r)

Next ==
    \/ WriterWrite \/ WriterSigLock \/ CloserClose \/ CloserSigLock
    \/ \E r \in Readers : ReaderStep(r)

CSpec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Safety *)
NoEmptyTake == \A r \in Readers : rpc[r] # "nsee"
AvailLinearizable == avail = w - t
\* every commit up to the close is a whole record: the committed count stays a multiple of K
RecordsAligned == off = 0 \/ closed
\* the ghost is t % K (checked by Apalache and TLC; the TLAPS proof works with off alone)
OffMod == off = t % K
NoWriteAfterEof == eofAt # -1 => w = eofAt
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ Buffered = 0 /\ avail = 0
Safety == NoEmptyTake /\ AvailLinearizable /\ RecordsAligned /\ NoWriteAfterEof
          /\ EofOnlyWhenClosedAndEmpty

TypeOK ==
    /\ w \in Nat /\ w <= Bytes /\ t \in Nat /\ t <= w /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in {"write", "siglock", "done", "failed"}
    /\ cpc \in {"close", "siglock", "done"}
    /\ rpc \in [Readers -> States]
    /\ hold \in [Readers -> Nat] /\ left \in [Readers -> Nat] /\ cur \in [Readers -> Nat]
    /\ off \in Nat /\ off < K
    /\ eofAt \in Int /\ eofAt >= -1 /\ eofAt <= Bytes
    /\ parked \subseteq Readers /\ wl \in 0..N /\ bl \in 0..N

BufLock == \A r \in Readers : (rpc[r] \in {"decide", "copy", "finish"}) <=> bl = r
\* hold and left: zero outside a copy; in a copy hold + left is the read's size, at least 1
HoldLeft == \A r \in Readers :
    /\ rpc[r] \notin {"copy", "finish"} => hold[r] = 0 /\ left[r] = 0
    /\ rpc[r] = "copy" => left[r] >= 1
    /\ rpc[r] = "finish" => left[r] = 0 /\ hold[r] >= 1
    /\ rpc[r] \in {"copy", "finish"} => hold[r] + left[r] <= K
BufNonNeg == Buffered >= 0
\* a reader copying has the bytes still to copy (the re-check under the lock)
CopyHasBytes == \A r \in Readers : rpc[r] = "copy" => Buffered >= left[r]
\* a whole record per read, fewer only from a closed buffer (#212)
WholeRead == \A r \in Readers : rpc[r] \in {"copy", "finish"} => hold[r] + left[r] = K \/ closed
CurZero == \A r \in Readers : cur[r] = 0
WaitLockInv == \A r \in Readers : (rpc[r] \in {"inc", "test"}) <=> wl = r
ParkedInv == parked = {r \in Readers : rpc[r] = "parked"}
RereadClosed == \A r \in Readers : rpc[r] = "reread" => closed
Ret0Empty == \A r \in Readers : rpc[r] = "ret0" => closed /\ avail = 0
DoneEof == \A r \in Readers : rpc[r] = "done" => eofAt # -1
CloserInv == (cpc = "close") <=> ~closed
WriterInv == /\ (wpc = "write" => w < Bytes)
             /\ (wpc = "done" => w = Bytes)
             /\ (wpc = "siglock" => w >= 1)

SafeInv ==
    /\ TypeOK /\ Safety
    /\ BufLock /\ HoldLeft /\ BufNonNeg /\ CopyHasBytes /\ WholeRead /\ CurZero
    /\ WaitLockInv /\ ParkedInv
    /\ RereadClosed /\ Ret0Empty /\ DoneEof /\ CloserInv /\ WriterInv

Domains ==
    /\ w \in Nat /\ t \in Nat /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in {"write", "siglock", "done", "failed"}
    /\ cpc \in {"close", "siglock", "done"}
    /\ rpc \in [Readers -> States]
    /\ hold \in [Readers -> Nat] /\ left \in [Readers -> Nat] /\ cur \in [Readers -> Nat]
    /\ off \in Nat /\ eofAt \in Int /\ parked \in SUBSET Readers /\ wl \in 0..N /\ bl \in 0..N
SafeInit == Domains /\ SafeInv
\* Apalache: SafeInv and the ghost's meaning, inductive together
SafeModInv == SafeInv /\ OffMod
SafeModInit == Domains /\ SafeModInv
=============================================================================
