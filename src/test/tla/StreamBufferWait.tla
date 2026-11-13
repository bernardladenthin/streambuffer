\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------------- MODULE StreamBufferWait ---------------------------
(***************************************************************************)
(* A counter abstraction of the calls of the reading side (TODO roadmap    *)
(* A13): every thread r in Threads makes a sequence of calls, each either  *)
(* read(b, 0, K[r]) (K[r] = 1 is read()) or waitForAtLeast(M[r]), chosen  *)
(* anew for every call, the threads sharing a budget of Calls0 further     *)
(* calls (any number, any split; a thread may also stop); NW writers       *)
(* sharing Bytes bytes in any chunking (one FIFO entry per write); NC      *)
(* closers. The current code (Condition, re-check under bufferLock, all    *)
(* the bytes of a read in one hold, the count lowered once per read).      *)
(* Bytes, every K[r], every M[r] and the budget stay symbolic.             *)
(* CheckedReturn: the waiting branch returns the count it checked (since   *)
(* 2026-11-12); without it, it read availableBytes again.                  *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
    \* @type: Set(Int);
    Threads,
    \* @type: Int;
    None,
    \* @type: Int;
    NW,
    \* @type: Int;
    NC,
    \* @type: Int;
    Bytes,
    \* @type: Int -> Int;
    K,
    \* @type: Int -> Int;
    M,
    \* @type: Int;
    RecLen,
    \* @type: Int;
    Calls0,
    \* @type: Bool;
    CheckedReturn,
    \* how many spurious wake-ups of Condition.await() a run may have (any number)
    \* @type: Int;
    Spurious

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
    \* @type: Int -> Str;
    cpc,
    \* @type: Int -> Str;
    rpc,
    \* @type: Int -> Str;
    op,
    \* @type: Int;
    calls,
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
    bl,
    \* ghost: the spurious wake-ups this run may still have
    \* @type: Int;
    spurious

vars == <<w, t, avail, closed, wpc, cpc, rpc, op, calls, hold, left, off, wres, wclosed, eofAt,
          parked, wl, bl, spurious>>

Writers == 1..NW
Closers == 1..NC
Ops == {"read", "wait"}
Min(a, b) == IF a < b THEN a ELSE b

\* Apalache: the constants of a check -- the threads, writers and closers fixed; Bytes, every read
\* size K[r] and request M[r] symbolic (the function domains are literal sets: a constant is not
\* yet fixed inside --cinit)
ConstInit == Threads = {1, 2} /\ None = 0 /\ NW = 2 /\ NC = 2 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : K[r] >= 1)
             /\ M \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE /\ Spurious \in Nat
ConstInit3 == Threads = {1, 2, 3} /\ None = 0 /\ NW = 2 /\ NC = 2 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2, 3} -> Nat] /\ (\A r \in {1, 2, 3} : K[r] >= 1)
             /\ M \in [{1, 2, 3} -> Nat] /\ (\A r \in {1, 2, 3} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE /\ Spurious \in Nat
ConstInit4 == Threads = {1, 2, 3, 4} /\ None = 0 /\ NW = 2 /\ NC = 2 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2, 3, 4} -> Nat] /\ (\A r \in {1, 2, 3, 4} : K[r] >= 1)
             /\ M \in [{1, 2, 3, 4} -> Nat] /\ (\A r \in {1, 2, 3, 4} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE /\ Spurious \in Nat
ConstInitW3 == Threads = {1, 2} /\ None = 0 /\ NW = 3 /\ NC = 3 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : K[r] >= 1)
             /\ M \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE /\ Spurious \in Nat
\* the waiting branch before 2026-11-12: the invariant is not inductive
\* (one writer, one call per thread, so the bounded search stays short)
ConstInitUnchecked == Threads = {1, 2} /\ None = 0 /\ NW = 1 /\ NC = 1 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : K[r] >= 1)
             /\ M \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 = 0 /\ CheckedReturn = FALSE /\ Spurious \in Nat

States == {"start", "reread", "lockwait", "inc", "test", "parked", "woken", "wret", "lock",
           "decide", "copy", "finish", "ret0", "done", "nsee"}

InFlight == IF bl = None THEN 0 ELSE hold[bl]
Buffered == w - t - InFlight
Want(r) == IF op[r] = "wait" THEN M[r] ELSE K[r]
\* every read asks for RecLen bytes: the case in which RecordsAligned speaks
Uniform == \A r \in Threads : K[r] = RecLen

Init ==
    /\ w = 0 /\ t = 0 /\ avail = 0 /\ closed = FALSE
    /\ wpc = [i \in Writers |-> "write"] /\ cpc = [c \in Closers |-> "close"]
    /\ rpc = [r \in Threads |-> "start"] /\ op \in [Threads -> Ops] /\ calls = Calls0
    /\ hold = [r \in Threads |-> 0] /\ left = [r \in Threads |-> 0] /\ off = 0
    /\ wres = [r \in Threads |-> -1] /\ wclosed = [r \in Threads |-> FALSE]
    /\ eofAt = -1 /\ parked = {} /\ wl = None /\ bl = None
    /\ spurious = Spurious

\* with nobody parked the signal does nothing and needs no lock (the code skips it then)
WriterNext == IF w >= Bytes THEN "done" ELSE "write"
WGo(i, s) == wpc' = [wpc EXCEPT ![i] = s]
CGo(c, s) == cpc' = [cpc EXCEPT ![c] = s]
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
    /\ UNCHANGED <<off, t, closed, cpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked,
                   wl, bl>>
    /\ UNCHANGED spurious

WriterSigLock(i) ==
    /\ wpc[i] = "siglock" /\ WakeAll /\ WGo(i, WriterNext)
    /\ UNCHANGED <<off, w, t, avail, closed, cpc, op, calls, hold, left, wres, wclosed, eofAt, wl,
                   bl>>
    /\ UNCHANGED spurious

\* closer c: close() sets streamClosed under bufferLock (again, if another closer was first)
CloserClose(c) ==
    /\ cpc[c] = "close" /\ bl = None /\ closed' = TRUE /\ CGo(c, "siglock")
    /\ UNCHANGED <<off, w, t, avail, wpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked,
                   wl, bl>>
    /\ UNCHANGED spurious

CloserSigLock(c) ==
    /\ cpc[c] = "siglock" /\ WakeAll /\ CGo(c, "done")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, op, calls, hold, left, wres, wclosed, eofAt, wl,
                   bl>>
    /\ UNCHANGED spurious

Go(r, s) == rpc' = [rpc EXCEPT ![r] = s]

\* a call returns: the thread makes its next call (s = "start"), a read or a wait, while calls are
\* left, or stops (s = "done"); the budget goes down by at least one per call (by any amount at a
\* stop), so it bounds every finite program (0..calls is never empty, see WriterWrite)
EndCall(r) ==
    \E n \in 0..calls : \E o \in Ops : \E s \in {"start", "done"} :
       /\ s = "start" => n < calls
       /\ calls' = n /\ op' = [op EXCEPT ![r] = o] /\ Go(r, s)

\* waitForAtLeast returns avail, noting streamClosed
Return(r) ==
    /\ wres' = [wres EXCEPT ![r] = avail]
    /\ wclosed' = [wclosed EXCEPT ![r] = closed]
    /\ EndCall(r)

\* the lock-free fast path: enough bytes (a wait returns the count it checked), closed, or wait
ThreadStart(r) ==
    /\ rpc[r] = "start"
    /\ IF avail >= Want(r) /\ op[r] = "wait"
          THEN Return(r)
          ELSE /\ Go(r, IF avail >= Want(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")
               /\ UNCHANGED <<wres, wclosed, op, calls>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

\* closed seen: the wait returns availableBytes, read again
ThreadReread(r) ==
    /\ rpc[r] = "reread"
    /\ IF op[r] = "wait"
          THEN Return(r)
          ELSE /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0")
               /\ UNCHANGED <<wres, wclosed, op, calls>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

ThreadWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None /\ wl' = r
    /\ Go(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt,
                   parked, bl>>
    /\ UNCHANGED spurious

ThreadInc(r) ==
    /\ rpc[r] = "inc" /\ Go(r, "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt,
                   parked, wl, bl>>
    /\ UNCHANGED spurious

\* the loop condition under waitLock; a wait with enough bytes returns the checked count
\* (CheckedReturn), else, once enough or closed, reads availableBytes again under waitLock
ThreadTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= Want(r) \/ closed
          THEN IF op[r] = "wait"
                  THEN IF CheckedReturn /\ avail >= Want(r)
                          THEN /\ Return(r) /\ wl' = None /\ UNCHANGED parked
                          ELSE /\ Go(r, "wret") /\ UNCHANGED <<wl, parked, wres, wclosed, op, calls>>
                  ELSE /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0") /\ wl' = None
                       /\ UNCHANGED <<parked, wres, wclosed, op, calls>>
          ELSE /\ parked' = parked \cup {r} /\ Go(r, "parked") /\ wl' = None
               /\ UNCHANGED <<wres, wclosed, op, calls>>
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>
    /\ UNCHANGED spurious

ThreadWaitReturn(r) ==
    /\ rpc[r] = "wret" /\ wl = r /\ Return(r) /\ wl' = None
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, bl>>
    /\ UNCHANGED spurious

ThreadLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None /\ bl' = r /\ Go(r, "decide")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt,
                   parked, wl>>
    /\ UNCHANGED spurious

\* under bufferLock (reads only): the re-check -- all K[r] bytes, or what is left of a closed
\* stream -- then copy, or release and wait again
ThreadDecide(r) ==
    /\ rpc[r] = "decide" /\ bl = r
    /\ IF avail >= K[r] \/ (closed /\ avail > 0)
          THEN /\ left' = [left EXCEPT ![r] = Min(avail, K[r])] /\ Go(r, "copy") /\ UNCHANGED bl
          ELSE /\ Go(r, "start") /\ bl' = None /\ UNCHANGED left
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt,
                   parked, wl>>
    /\ UNCHANGED spurious

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
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, op, calls, wres, wclosed, eofAt, parked, wl,
                   bl>>
    /\ UNCHANGED spurious

\* under bufferLock: commit the bytes and the count, release; the read returns
ThreadFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ t' = t + hold[r] /\ avail' = avail - hold[r] /\ hold' = [hold EXCEPT ![r] = 0]
    \* ghost: the bytes of the current RecLen-byte record committed so far (t % RecLen while
    \* every read size is at most RecLen, kept linear)
    /\ off' = IF off + hold[r] >= RecLen THEN off + hold[r] - RecLen ELSE off + hold[r]
    /\ bl' = None /\ EndCall(r)
    /\ UNCHANGED <<left, w, closed, wpc, cpc, wres, wclosed, eofAt, parked, wl>>
    /\ UNCHANGED spurious

\* the read returns -1
ThreadRet0(r) ==
    /\ rpc[r] = "ret0" /\ eofAt' = (IF eofAt = -1 THEN w ELSE eofAt) /\ EndCall(r)
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, parked, wl, bl>>
    /\ UNCHANGED spurious

\* a step of the protocol keeps the budget of spurious wake-ups
ThreadStep(r) ==
    \/ ThreadStart(r) \/ ThreadReread(r) \/ ThreadWaitLock(r) \/ ThreadInc(r)
    \/ ThreadTest(r) \/ ThreadWaitReturn(r) \/ ThreadLock(r) \/ ThreadDecide(r)
    \/ ThreadCopy(r) \/ ThreadFinish(r) \/ ThreadRet0(r)

\* a spurious wake-up: Condition.await() may return without a signal (JDK); the thread takes
\* waitLock again and tests, as after a signal. At most Spurious in a run: safety for every
\* Spurious covers every run, liveness assumes finitely many. Not part of ThreadStep, so no
\* fairness forces it.
SpuriousWake(r) ==
    /\ rpc[r] = "parked" /\ spurious > 0
    /\ spurious' = spurious - 1 /\ parked' = parked \ {r} /\ Go(r, "woken")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, op, calls, hold, left, off, wres, wclosed, eofAt,
                   wl, bl>>

Next ==
    \/ \E i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
    \/ \E c \in Closers : CloserClose(c) \/ CloserSigLock(c)
    \/ \E r \in Threads : ThreadStep(r)
    \/ \E r \in Threads : SpuriousWake(r)

CSpec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Safety *)
NoEmptyTake == \A r \in Threads : rpc[r] # "nsee"
AvailLinearizable == avail = w - t
\* waitForAtLeast(M[r]) returns fewer than M[r] only for a closed buffer (its JML postcondition);
\* wres[r] is what r's last wait returned
WaitEnoughOrClosed == \A r \in Threads : wres[r] # -1 => wres[r] >= M[r] \/ wclosed[r]
\* a read takes K[r] bytes in one hold, fewer only from a closed buffer (#212)
WholeRead == \A r \in Threads : rpc[r] \in {"copy", "finish"} => hold[r] + left[r] = K[r] \/ closed
\* with one read size, every commit up to the close is a whole record (#212); off is t % RecLen
RecordsAligned == Uniform => off = 0 \/ closed
OffMod == (\A r \in Threads : K[r] <= RecLen) => off = t % RecLen
NoWriteAfterEof == eofAt # -1 => w = eofAt
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ Buffered = 0 /\ avail = 0
Safety == NoEmptyTake /\ AvailLinearizable /\ WaitEnoughOrClosed /\ WholeRead /\ RecordsAligned
          /\ NoWriteAfterEof /\ EofOnlyWhenClosedAndEmpty

TypeOK ==
    /\ w \in Nat /\ w <= Bytes /\ t \in Nat /\ t <= w /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in [Writers -> {"write", "siglock", "done", "failed"}]
    /\ cpc \in [Closers -> {"close", "siglock", "done"}]
    /\ rpc \in [Threads -> States] /\ op \in [Threads -> Ops] /\ calls \in Nat
    /\ hold \in [Threads -> Nat] /\ left \in [Threads -> Nat] /\ off \in Nat
    /\ wres \in [Threads -> Int] /\ wclosed \in [Threads -> BOOLEAN]
    /\ eofAt \in Int /\ eofAt >= -1 /\ eofAt <= Bytes
    /\ parked \subseteq Threads /\ wl \in Threads \cup {None} /\ bl \in Threads \cup {None}
    /\ spurious \in Nat /\ spurious <= Spurious

BufLock == \A r \in Threads : (rpc[r] \in {"decide", "copy", "finish"}) <=> bl = r
\* hold and left: zero outside a copy; in a copy hold + left is the read's size, at most K[r]
HoldLeft == \A r \in Threads :
    /\ rpc[r] \notin {"copy", "finish"} => hold[r] = 0 /\ left[r] = 0
    /\ rpc[r] = "copy" => left[r] >= 1
    /\ rpc[r] = "finish" => left[r] = 0 /\ hold[r] >= 1
    /\ rpc[r] \in {"copy", "finish"} => hold[r] + left[r] <= K[r]
BufNonNeg == Buffered >= 0
\* a reader copying has the bytes still to copy (the re-check under the lock)
CopyHasBytes == \A r \in Threads : rpc[r] = "copy" => Buffered >= left[r]
\* a wait never takes bufferLock, a read never returns through the waiting branch
OpStates == \A r \in Threads :
    /\ rpc[r] = "wret" => op[r] = "wait" /\ closed
    /\ rpc[r] \in {"lock", "decide", "copy", "finish", "ret0"} => op[r] = "read"
WaitLockInv == \A r \in Threads : (rpc[r] \in {"inc", "test", "wret"}) <=> wl = r
ParkedInv == parked = {r \in Threads : rpc[r] = "parked"}
RereadClosed == \A r \in Threads : rpc[r] = "reread" => closed
Ret0Empty == \A r \in Threads : rpc[r] = "ret0" => closed /\ avail = 0
CloserInv == closed <=> \E c \in Closers : cpc[c] # "close"
WriterInv == \A i \in Writers : /\ (wpc[i] = "done" => w = Bytes)
                                 /\ (wpc[i] = "siglock" => w >= 1)

SafeInv ==
    /\ TypeOK /\ Safety
    /\ BufLock /\ HoldLeft /\ BufNonNeg /\ CopyHasBytes /\ OpStates /\ WaitLockInv /\ ParkedInv
    /\ RereadClosed /\ Ret0Empty /\ CloserInv /\ WriterInv

Domains ==
    /\ w \in Nat /\ t \in Nat /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in [Writers -> {"write", "siglock", "done", "failed"}]
    /\ cpc \in [Closers -> {"close", "siglock", "done"}]
    /\ rpc \in [Threads -> States] /\ op \in [Threads -> Ops] /\ calls \in Nat
    /\ hold \in [Threads -> Nat] /\ left \in [Threads -> Nat] /\ off \in Nat
    /\ wres \in [Threads -> Int] /\ wclosed \in [Threads -> BOOLEAN]
    /\ eofAt \in Int /\ parked \in SUBSET Threads
    /\ wl \in Threads \cup {None} /\ bl \in Threads \cup {None}
    /\ spurious \in Nat
SafeInit == Domains /\ SafeInv
\* Apalache: SafeInv and the ghost's meaning, inductive together
SafeModInv == SafeInv /\ OffMod
SafeModInit == Domains /\ SafeModInv
=============================================================================
