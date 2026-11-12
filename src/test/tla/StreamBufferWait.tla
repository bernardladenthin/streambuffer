\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------------- MODULE StreamBufferWait ---------------------------
(***************************************************************************)
(* A counter abstraction of waitForAtLeast next to readers (TODO roadmap   *)
(* A13): threads 1..NR call read(b, 0, K) until -1 (K = 1 is read()),       *)
(* each thread r in NR+1..N calls waitForAtLeast(M[r]) once, each with its *)
(* own request; NW writers sharing Bytes bytes in any chunking (one FIFO    *)
(* entry per write), a closer; the current code (Condition, re-check under *)
(* bufferLock, all the bytes of a read in one hold, the count lowered once  *)
(* per read). K, every M[r] and Bytes stay symbolic. CheckedReturn: the     *)
(* waiting branch returns the count it checked                              *)
(* (since 2026-11-12); without it, it read availableBytes again.            *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
    \* @type: Int;
    N,
    \* @type: Int;
    NW,
    \* @type: Int;
    NR,
    \* @type: Int;
    Bytes,
    \* @type: Int -> Int;
    M,
    \* @type: Int;
    K,
    \* @type: Bool;
    CheckedReturn

VARIABLES
    \* @type: Int;
    w,
    \* @type: Int;
    t,
    \* @type: Int;
    avail,
    \* @type: Bool;
    closed,
    \* @type: Int -> Str;
    wpc,
    \* @type: Str;
    cpc,
    \* @type: Int -> Str;
    rpc,
    \* @type: Int -> Int;
    hold,
    \* @type: Int -> Int;
    left,
    \* @type: Int;
    off,
    \* @type: Int -> Int;
    wres,
    \* @type: Int -> Bool;
    wclosed,
    \* @type: Int;
    eofAt,
    \* @type: Set(Int);
    parked,
    \* @type: Int;
    wl,
    \* @type: Int;
    bl

vars == <<w, t, avail, closed, wpc, cpc, rpc, hold, left, off, wres, wclosed, eofAt, parked, wl, bl>>

Threads == 1..N
Writers == 1..NW
IsWaiter(r) == r > NR
None == 0
Min(a, b) == IF a < b THEN a ELSE b

\* Apalache: the constants of a check -- readers and waiters fixed; Bytes, K and each waiter's
\* request M[r] symbolic (the function domain must be a literal range here: Threads is not
\* constant yet inside --cinit)
ConstInit == N = 2 /\ NW = 2 /\ NR = 1 /\ Bytes \in Nat /\ Bytes >= 1 /\ M \in [1..2 -> Nat] /\ (\A r \in 1..2 : M[r] >= 1) /\ K \in Nat /\ K >= 1 /\ CheckedReturn = TRUE
ConstInit22 == N = 4 /\ NW = 2 /\ NR = 2 /\ Bytes \in Nat /\ Bytes >= 1 /\ M \in [1..4 -> Nat] /\ (\A r \in 1..4 : M[r] >= 1) /\ K \in Nat /\ K >= 1 /\ CheckedReturn = TRUE
ConstInit13 == N = 4 /\ NW = 2 /\ NR = 1 /\ Bytes \in Nat /\ Bytes >= 1 /\ M \in [1..4 -> Nat] /\ (\A r \in 1..4 : M[r] >= 1) /\ K \in Nat /\ K >= 1 /\ CheckedReturn = TRUE
ConstInit31 == N = 4 /\ NW = 2 /\ NR = 3 /\ Bytes \in Nat /\ Bytes >= 1 /\ M \in [1..4 -> Nat] /\ (\A r \in 1..4 : M[r] >= 1) /\ K \in Nat /\ K >= 1 /\ CheckedReturn = TRUE
\* the waiting branch before 2026-11-12: the invariant is not inductive
ConstInitUnchecked == N = 2 /\ NW = 2 /\ NR = 1 /\ Bytes \in Nat /\ Bytes >= 1 /\ M \in [1..2 -> Nat] /\ (\A r \in 1..2 : M[r] >= 1) /\ K \in Nat /\ K >= 1 /\ CheckedReturn = FALSE

States == {"start", "reread", "lockwait", "inc", "test", "parked", "woken", "wret", "lock",
           "decide", "copy", "finish", "ret0", "done", "nsee"}

InFlight == IF bl = None THEN 0 ELSE hold[bl]
Buffered == w - t - InFlight
Want(r) == IF IsWaiter(r) THEN M[r] ELSE K

Init ==
    /\ w = 0 /\ t = 0 /\ avail = 0 /\ closed = FALSE
    /\ wpc = [i \in Writers |-> "write"] /\ cpc = "close"
    /\ rpc = [r \in Threads |-> "start"] /\ hold = [r \in Threads |-> 0]
    /\ left = [r \in Threads |-> 0] /\ off = 0
    /\ wres = [r \in Threads |-> -1] /\ wclosed = [r \in Threads |-> FALSE]
    /\ eofAt = -1 /\ parked = {} /\ wl = None /\ bl = None

\* with nobody parked the signal does nothing and needs no lock (the code skips it then)
WriterNext == IF w >= Bytes THEN "done" ELSE "write"
WGo(i, s) == wpc' = [wpc EXCEPT ![i] = s]
WakeAll ==
    IF parked = {}
       THEN UNCHANGED <<rpc, parked>>
       ELSE /\ wl = None
            /\ rpc' = [r \in Threads |-> IF r \in parked THEN "woken" ELSE rpc[r]]
            /\ parked' = {}

\* writer i: one write of c bytes, one FIFO entry -- any chunking, the writers sharing the budget
WriterWrite(i) ==
    /\ wpc[i] = "write" /\ bl = None
    /\ IF closed
          THEN /\ WGo(i, "failed") /\ UNCHANGED <<w, avail>>
          ELSE IF w >= Bytes
                  THEN /\ WGo(i, "done") /\ UNCHANGED <<w, avail>>
                  \* a range that is never empty: Apalache 0.63.0 asserts the bounds of \E c \in a..b
                  \* globally, so a range empty in some state (1..(Bytes - w) at w = Bytes) cut every
                  \* path through that state, whichever action it took (README, A13)
                  ELSE /\ \E c \in 1..Bytes : c <= Bytes - w /\ w' = w + c /\ avail' = avail + c
                       /\ WGo(i, "siglock")
    /\ UNCHANGED <<left, off, t, closed, cpc, rpc, hold, wres, wclosed, eofAt, parked, wl, bl>>

WriterSigLock(i) ==
    /\ wpc[i] = "siglock" /\ WakeAll /\ WGo(i, WriterNext)
    /\ UNCHANGED <<left, off, w, t, avail, closed, cpc, hold, wres, wclosed, eofAt, wl, bl>>

CloserClose ==
    /\ cpc = "close" /\ bl = None /\ closed' = TRUE /\ cpc' = "siglock"
    /\ UNCHANGED <<left, off, w, t, avail, wpc, rpc, hold, wres, wclosed, eofAt, parked, wl, bl>>

CloserSigLock ==
    /\ cpc = "siglock" /\ WakeAll /\ cpc' = "done"
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, hold, wres, wclosed, eofAt, wl, bl>>

Go(r, s) == rpc' = [rpc EXCEPT ![r] = s]

\* waitForAtLeast returns avail to w, noting streamClosed
Return(r) ==
    /\ wres' = [wres EXCEPT ![r] = avail]
    /\ wclosed' = [wclosed EXCEPT ![r] = closed]
    /\ Go(r, "done")

\* the lock-free fast path: enough bytes (a waiter returns the count it checked), closed, or wait
ThreadStart(r) ==
    /\ rpc[r] = "start"
    /\ IF avail >= Want(r) /\ IsWaiter(r)
          THEN Return(r)
          ELSE /\ Go(r, IF avail >= Want(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")
               /\ UNCHANGED <<wres, wclosed>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>

\* closed seen: the wait returns availableBytes, read again
ThreadReread(r) ==
    /\ rpc[r] = "reread"
    /\ IF IsWaiter(r)
          THEN Return(r)
          ELSE /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0") /\ UNCHANGED <<wres, wclosed>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>

ThreadWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None /\ wl' = r
    /\ Go(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, eofAt, parked, bl>>

ThreadInc(r) ==
    /\ rpc[r] = "inc" /\ Go(r, "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, eofAt, parked, wl, bl>>

\* the loop condition under waitLock; a waiter with enough bytes returns the checked count
\* (CheckedReturn), else, once enough or closed, reads availableBytes again under waitLock
ThreadTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= Want(r) \/ closed
          THEN IF IsWaiter(r)
                  THEN IF CheckedReturn /\ avail >= Want(r)
                          THEN /\ Return(r) /\ wl' = None /\ UNCHANGED parked
                          ELSE /\ Go(r, "wret") /\ UNCHANGED <<wl, parked, wres, wclosed>>
                  ELSE /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0") /\ wl' = None
                       /\ UNCHANGED <<parked, wres, wclosed>>
          ELSE /\ parked' = parked \cup {r} /\ Go(r, "parked") /\ wl' = None
               /\ UNCHANGED <<wres, wclosed>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>

ThreadWaitReturn(r) ==
    /\ rpc[r] = "wret" /\ wl = r /\ Return(r) /\ wl' = None
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, bl>>

ThreadLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None /\ bl' = r /\ Go(r, "decide")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, eofAt, parked, wl>>

\* under bufferLock (readers only): the re-check -- all K bytes, or what is left of a closed
\* stream -- then copy, or release and wait again
ThreadDecide(r) ==
    /\ rpc[r] = "decide" /\ bl = r
    /\ IF avail >= K \/ (closed /\ avail > 0)
          THEN /\ left' = [left EXCEPT ![r] = Min(avail, K)] /\ Go(r, "copy") /\ UNCHANGED bl
          ELSE /\ Go(r, "start") /\ bl' = None /\ UNCHANGED left
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, eofAt, parked, wl>>

\* under bufferLock: one turn of the copy loop takes k bytes, any k up to what is left
ThreadCopy(r) ==
    /\ rpc[r] = "copy" /\ bl = r
    /\ IF Buffered = 0
          THEN /\ Go(r, "nsee") /\ UNCHANGED <<hold, left>>
          \* 0..left[r] is never empty (left is a Nat), unlike 1..left[r] (see WriterWrite)
          ELSE \E k \in 0..left[r] :
                  /\ k >= 1 /\ k <= Buffered
                  /\ hold' = [hold EXCEPT ![r] = @ + k] /\ left' = [left EXCEPT ![r] = @ - k]
                  /\ Go(r, IF left[r] = k THEN "finish" ELSE "copy")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, wres, wclosed, eofAt, parked, wl, bl>>

ThreadFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ t' = t + hold[r] /\ avail' = avail - hold[r] /\ hold' = [hold EXCEPT ![r] = 0]
    \* ghost: the bytes of the current record committed so far (t % K, kept linear)
    /\ off' = IF off + hold[r] >= K THEN off + hold[r] - K ELSE off + hold[r]
    /\ bl' = None /\ Go(r, "start")
    /\ UNCHANGED <<left, w, closed, wpc, cpc, wres, wclosed, eofAt, parked, wl>>

ThreadRet0(r) ==
    /\ rpc[r] = "ret0" /\ eofAt' = (IF eofAt = -1 THEN w ELSE eofAt) /\ Go(r, "done")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, parked, wl, bl>>

ThreadStep(r) ==
    \/ ThreadStart(r) \/ ThreadReread(r) \/ ThreadWaitLock(r) \/ ThreadInc(r)
    \/ ThreadTest(r) \/ ThreadWaitReturn(r) \/ ThreadLock(r) \/ ThreadDecide(r)
    \/ ThreadCopy(r) \/ ThreadFinish(r) \/ ThreadRet0(r)

Next ==
    \/ \E i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
    \/ CloserClose \/ CloserSigLock
    \/ \E r \in Threads : ThreadStep(r)

CSpec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Safety *)
NoEmptyTake == \A r \in Threads : rpc[r] # "nsee"
AvailLinearizable == avail = w - t
\* waitForAtLeast(M[r]) returns fewer than M[r] only for a closed buffer (its JML postcondition)
WaitEnoughOrClosed == \A r \in Threads : IsWaiter(r) /\ wres[r] # -1 => wres[r] >= M[r] \/ wclosed[r]
\* every commit up to the close is a whole record (#212); off is t % K (OffMod)
RecordsAligned == off = 0 \/ closed
OffMod == off = t % K
NoWriteAfterEof == eofAt # -1 => w = eofAt
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ Buffered = 0 /\ avail = 0
Safety == NoEmptyTake /\ AvailLinearizable /\ WaitEnoughOrClosed /\ RecordsAligned /\ NoWriteAfterEof
          /\ EofOnlyWhenClosedAndEmpty

TypeOK ==
    /\ w \in Nat /\ w <= Bytes /\ t \in Nat /\ t <= w /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in [Writers -> {"write", "siglock", "done", "failed"}]
    /\ cpc \in {"close", "siglock", "done"}
    /\ rpc \in [Threads -> States] /\ hold \in [Threads -> Nat] /\ left \in [Threads -> Nat]
    /\ off \in Nat /\ off < K
    /\ wres \in [Threads -> Int] /\ wclosed \in [Threads -> BOOLEAN]
    /\ eofAt \in Int /\ eofAt >= -1 /\ eofAt <= Bytes
    /\ parked \subseteq Threads /\ wl \in 0..N /\ bl \in 0..N

BufLock == \A r \in Threads : (rpc[r] \in {"decide", "copy", "finish"}) <=> bl = r
\* hold and left: zero outside a copy; in a copy hold + left is the read's size, at most K
HoldLeft == \A r \in Threads :
    /\ rpc[r] \notin {"copy", "finish"} => hold[r] = 0 /\ left[r] = 0
    /\ rpc[r] = "copy" => left[r] >= 1
    /\ rpc[r] = "finish" => left[r] = 0 /\ hold[r] >= 1
    /\ rpc[r] \in {"copy", "finish"} => hold[r] + left[r] <= K
BufNonNeg == Buffered >= 0
\* a reader copying has the bytes still to copy (the re-check under the lock)
CopyHasBytes == \A r \in Threads : rpc[r] = "copy" => Buffered >= left[r]
\* a whole record per read, fewer only from a closed buffer (#212)
WholeRead == \A r \in Threads : rpc[r] \in {"copy", "finish"} => hold[r] + left[r] = K \/ closed
\* a waiter never takes bufferLock; it returns with enough bytes, or once it saw the close
WaiterStates == \A r \in Threads : IsWaiter(r) =>
    /\ rpc[r] \in {"start", "reread", "lockwait", "inc", "test", "parked", "woken", "wret", "done"}
    /\ (rpc[r] = "done") <=> wres[r] # -1
    /\ (rpc[r] = "wret" => closed)
ReaderStates == \A r \in Threads : ~IsWaiter(r) => rpc[r] \notin {"wret"} /\ wres[r] = -1
WaitLockInv == \A r \in Threads : (rpc[r] \in {"inc", "test", "wret"}) <=> wl = r
ParkedInv == parked = {r \in Threads : rpc[r] = "parked"}
RereadClosed == \A r \in Threads : rpc[r] = "reread" => closed
Ret0Empty == \A r \in Threads : rpc[r] = "ret0" => closed /\ avail = 0
DoneEof == \A r \in Threads : ~IsWaiter(r) /\ rpc[r] = "done" => eofAt # -1
CloserInv == (cpc = "close") <=> ~closed
WriterInv == \A i \in Writers : /\ (wpc[i] = "done" => w = Bytes)
                                 /\ (wpc[i] = "siglock" => w >= 1)

SafeInv ==
    /\ TypeOK /\ Safety
    /\ BufLock /\ HoldLeft /\ BufNonNeg /\ CopyHasBytes /\ WholeRead
    /\ WaiterStates /\ ReaderStates /\ WaitLockInv /\ ParkedInv
    /\ RereadClosed /\ Ret0Empty /\ DoneEof /\ CloserInv /\ WriterInv

Domains ==
    /\ w \in Nat /\ t \in Nat /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in [Writers -> {"write", "siglock", "done", "failed"}]
    /\ cpc \in {"close", "siglock", "done"}
    /\ rpc \in [Threads -> States] /\ hold \in [Threads -> Nat] /\ left \in [Threads -> Nat]
    /\ off \in Nat
    /\ wres \in [Threads -> Int] /\ wclosed \in [Threads -> BOOLEAN]
    /\ eofAt \in Int /\ parked \in SUBSET Threads /\ wl \in 0..N /\ bl \in 0..N
SafeInit == Domains /\ SafeInv
\* Apalache: SafeInv and the ghost's meaning, inductive together
SafeModInv == SafeInv /\ OffMod
SafeModInit == Domains /\ SafeModInv
=============================================================================
