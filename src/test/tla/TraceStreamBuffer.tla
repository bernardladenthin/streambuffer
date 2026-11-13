\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------------- MODULE TraceStreamBuffer -------------------------
(***************************************************************************)
(* Trace validation of StreamBuffer.tla against recorded runs of the code  *)
(* (TODO roadmap A6; the approach of Cirstea, Kuppe, Merz et al. 2024).    *)
(*                                                                         *)
(* A trace (TraceLog) is the sequence of the accesses to shared state of   *)
(* one run, in the order they happened, as the test-side instrumentation   *)
(* (net.ladenthin.streambuffer.trace) logs them, plus the results of the   *)
(* calls. Each line is [t: thread, m: method, a: access, n: ordinal, v:   *)
(* value, b: bytes].                                                       *)
(*                                                                         *)
(* The model is coarser than the code: one step of it is several accesses *)
(* of the code (the fast path of the wait reads availableBytes and         *)
(* streamClosed in one step; ReaderTest also decrements waitingReaders).   *)
(* So a thread's model steps are not tied to single lines: before a line   *)
(* of thread t is consumed, t may take up to K steps of the model (Silent),*)
(* and then the line must agree with the model's state (Obs): the values   *)
(* read and written, who holds which lock, where the thread is, what its   *)
(* calls returned. Other threads move only at their own lines. The trace  *)
(* is accepted if some placement consumes every line: then the invariant   *)
(* TraceNotDone is violated (TLC 1.7.4 has no POSTCONDITION), and trace.sh  *)
(* reads that violation as the verdict "accepted".                          *)
(***************************************************************************)
EXTENDS StreamBuffer, TLC

CONSTANTS
    TraceLog,   \* the recorded lines
    K           \* the model steps a thread may take before one of its lines

VARIABLES
    l,          \* the next line
    k           \* the model steps taken since the last line

tvars == <<vars, l, k>>

Last(s) == s[Len(s)]

(* A model step of thread t. *)
StepOf(t) ==
    IF t = "w" THEN WriterStep
    ELSE IF t = "c" THEN CloserStep
    ELSE ReaderStep(t)

(***************************************************************************)
(* What a line says about the model's state once the thread's steps up to  *)
(* it are taken.                                                           *)
(***************************************************************************)
IsReader(t) == t \in Readers

(* The value checks: every access of availableBytes, streamClosed and     *)
(* waitingReaders. The model lowers waitingReaders in ReaderTest, the code *)
(* a few accesses later, so the model's count may be lower than the code's.*)
Values(e) ==
    /\ e.a \in {"getAvail", "putAvail"} => avail = e.v
    /\ e.a = "getClosed" => closed = (e.v = 1)
    /\ e.a = "putClosed" => closed
    /\ e.a \in {"waitersGet", "waitersInc", "waitersDec"} => waiters <= e.v

(* The locks. The writer and the closer hold bufferLock and waitLock only  *)
(* inside one model step each, so while they hold it no reader does.       *)
Locks(e) ==
    /\ e.a = "enter" => bl = (IF IsReader(e.t) THEN e.t ELSE None)
    /\ e.a = "exit" /\ IsReader(e.t) => bl # e.t
    /\ e.a = "wlock" => wl = (IF IsReader(e.t) THEN e.t ELSE None)
    /\ e.a = "wunlock" /\ IsReader(e.t) => wl # e.t

(* Where a reader is after a line of the wait. *)
WaitPc(e) ==
    LET r == e.t IN
    /\ (e.m = "waitForAtLeast" /\ e.a = "getAvail" /\ e.n = 0 /\ e.v >= LenOf(r)) =>
           IF r \in WaitCallers THEN rpc[r] = "done" /\ wres[r] = e.v ELSE rpc[r] = "lock"
    /\ (e.m = "waitForAtLeast" /\ e.a = "getClosed") =>
           IF e.v = 0 THEN rpc[r] = "lockwait" ELSE rpc[r] \in {"reread", "lock", "done"}
    /\ (e.m = "waitForAtLeast" /\ e.a = "getAvail" /\ e.n = 1) =>
           IF r \in WaitCallers THEN rpc[r] = "done" /\ wres[r] = e.v
           ELSE IF e.v >= 1 THEN rpc[r] = "lock" ELSE rpc[r] \in {"ret0", "lock"}
    /\ e.a = "waitersInc" => rpc[r] \notin {"lockwait", "inc"}
    /\ e.a = "park" => rpc[r] = "parked"
    /\ e.a = "unpark" => rpc[r] \notin {"parked", "woken"}
    /\ e.a = "waitersDec" => rpc[r] \notin {"lockwait", "inc", "test", "parked", "woken", "wret"}

(* The results of the calls (the lines the test adds). *)
Results(e) ==
    /\ e.a = "wret" => Len(written) = e.v /\ wpc \in {"write", "done"}
    /\ e.a = "wfail" => wpc = "failed"
    /\ e.a = "cret" => cpc = "done"
    /\ e.a = "ret" => rpc[e.t] = "start" /\ Len(reads[e.t]) = e.n /\ Last(reads[e.t]) = e.b
    /\ e.a = "eof" => rpc[e.t] = "done" /\ Len(reads[e.t]) = e.n
    /\ e.a = "wfa" => rpc[e.t] = "done" /\ wres[e.t] = e.v

(* The signal: the model's waitingReaders may be 0 where the code's is not *)
(* (see Values), then the model skips the signal; it wakes nobody then.    *)
Signal(e) ==
    /\ e.a = "waitersGet" /\ e.t = "w" => wpc # "sigread"
    /\ e.a = "waitersGet" /\ e.t = "c" => cpc # "sigread"
    /\ e.a = "signalAll" /\ e.t = "w" => wpc # "siglock"
    /\ e.a = "signalAll" /\ e.t = "c" => cpc # "siglock"

Obs(e) ==
    /\ Values(e) /\ Locks(e) /\ Signal(e) /\ Results(e)
    /\ IsReader(e.t) => WaitPc(e)

-----------------------------------------------------------------------------
TraceInit == Init /\ l = 1 /\ k = 0 /\ TLCSet(1, 0)

Silent ==
    /\ l <= Len(TraceLog) /\ k < K
    /\ StepOf(TraceLog[l].t)
    /\ k' = k + 1
    /\ UNCHANGED l

(* A rejected trace: the last "line" TLC prints is the first line no     *)
(* placement could consume.                                                *)
Consume ==
    /\ l <= Len(TraceLog)
    /\ Obs(TraceLog[l])
    /\ l + 1 > TLCGet(1) => TLCSet(1, l + 1) /\ PrintT(<<"line", l + 1>>)
    /\ l' = l + 1
    /\ k' = 0
    /\ UNCHANGED vars

TraceNext == Silent \/ Consume

TraceSpec == TraceInit /\ [][TraceNext]_tvars

(* Violated exactly when every line has been consumed: the trace is accepted. *)
TraceNotDone == l <= Len(TraceLog)

=============================================================================
