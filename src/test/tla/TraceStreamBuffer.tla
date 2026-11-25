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
(* of the code (the finally block of the wait, decrement and unlock, is   *)
(* one step; the closed branch of a read()'s wait reads streamClosed and  *)
(* the count in one).                                                     *)
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
    K,          \* the model steps a thread may take before one of its lines
    WriterName, \* the thread name of writer i in the trace: WriterName[i]
    CloserName  \* the thread name of closer c in the trace: CloserName[c]

VARIABLES
    l,          \* the next line
    k           \* the model steps taken since the last line

tvars == <<vars, l, k>>

Last(s) == s[Len(s)]

(* A model step of thread t: a step of the protocol, or for a reader a    *)
(* spurious wake-up (within the trace's budget Spurious).                  *)
IsWriter(t) == \E i \in Writers : WriterName[i] = t
IsCloser(t) == \E c \in Closers : CloserName[c] = t
WriterOf(t) == CHOOSE i \in Writers : WriterName[i] = t
CloserOf(t) == CHOOSE c \in Closers : CloserName[c] = t

StepOf(t) ==
    IF IsWriter(t) THEN WriterStep(WriterOf(t))
    ELSE IF IsCloser(t) THEN CloserStep(CloserOf(t))
    ELSE ReaderStep(t) \/ SpuriousWake(t)

(* The signal of a writer or closer is a step only at the code's lines of *)
(* it: its read of waitingReaders (WriterSigRead, CloserSigRead) right     *)
(* before its waitersGet line, its signal (WriterSigLock, CloserSigLock)   *)
(* right before its signalAll line. Otherwise the model could signal where *)
(* the code does not: a class whose write never signals was accepted, the  *)
(* closer's signal waking its reader later (every scenario has a closer).  *)
(* Now its writer stays at "sigread", and its wret line is rejected.       *)
SignalAt(e) ==
    /\ IsWriter(e.t) =>
           /\ wpc[WriterOf(e.t)] = "sigread" => e.a = "waitersGet"
           /\ wpc[WriterOf(e.t)] = "siglock" => e.a = "signalAll"
    /\ IsCloser(e.t) =>
           /\ cpc[CloserOf(e.t)] = "sigread" => e.a = "waitersGet"
           /\ cpc[CloserOf(e.t)] = "siglock" => e.a = "signalAll"

(* A model step of the thread of line e, before e is consumed. *)
StepFor(e) == SignalAt(e) /\ StepOf(e.t)

(***************************************************************************)
(* What a line says about the model's state once the thread's steps up to  *)
(* it are taken.                                                           *)
(***************************************************************************)
IsReader(t) == t \in Readers

(* The value checks: every access of availableBytes, streamClosed and     *)
(* waitingReaders. The model changes waitingReaders where the code does    *)
(* (ReaderInc, ReaderWaitExit), so the counts agree; until A18 found a     *)
(* word only a spurious wake-up explained, the model lowered it with the   *)
(* return and the check allowed a lower count.                             *)
Values(e) ==
    /\ e.a \in {"getAvail", "putAvail"} => avail = e.v
    /\ e.a = "getClosed" => closed = (e.v = 1)
    /\ e.a = "putClosed" => closed
    /\ e.a \in {"waitersGet", "waitersInc", "waitersDec"} => waiters = e.v

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
    /\ e.a = "waitersDec" => rpc[r] \notin {"lockwait", "inc", "test", "waitclosed", "parked",
                                            "woken", "wret"} \cup WaitExits

(* The results of the calls (the lines the test adds). *)
Results(e) ==
    \* a wret has the bytes of all writers up to its writer's last commit (TraceScenario numbers
    \* them in commit order); with several writers another may commit before the line
    /\ e.a = "wret" => (IF NW = 1 THEN Len(written) = e.v ELSE Len(written) >= e.v)
                       /\ wpc[WriterOf(e.t)] \in {"write", "done"}
    /\ e.a = "wfail" => wpc[WriterOf(e.t)] = "failed"
    /\ e.a = "cret" => cpc[CloserOf(e.t)] = "done"
    /\ e.a = "ret" => rpc[e.t] = "start" /\ Len(reads[e.t]) = e.n /\ Last(reads[e.t]) = e.b
    /\ e.a = "eof" => rpc[e.t] = "done" /\ Len(reads[e.t]) = e.n
    /\ e.a = "wfa" => rpc[e.t] = "done" /\ wres[e.t] = e.v

(* The signal: the read of waitingReaders and the signal itself are the   *)
(* model's WriterSigRead and WriterSigLock, taken by the line.             *)
Signal(e) ==
    /\ e.a = "waitersGet" /\ IsWriter(e.t) => wpc[WriterOf(e.t)] # "sigread"
    /\ e.a = "waitersGet" /\ IsCloser(e.t) => cpc[CloserOf(e.t)] # "sigread"
    /\ e.a = "signalAll" /\ IsWriter(e.t) => wpc[WriterOf(e.t)] # "siglock"
    /\ e.a = "signalAll" /\ IsCloser(e.t) => cpc[CloserOf(e.t)] # "siglock"

Obs(e) ==
    /\ Values(e) /\ Locks(e) /\ Signal(e) /\ Results(e)
    /\ IsReader(e.t) => WaitPc(e)

-----------------------------------------------------------------------------
(* The trace through a definition of its own: TLC 1.7.4 evaluates a       *)
(* constant substituted in the cfg (TraceLog <- TTrace) anew at every use, *)
(* the whole trace at each step, but a definition of constant level once   *)
(* (tlaplus issue 648). check.sh counts the evaluations (ConstCacheTrace). *)
Log == TraceLog

TraceInit == Init /\ l = 1 /\ k = 0 /\ TLCSet(1, 0)

Silent ==
    /\ l <= Len(Log) /\ k < K
    /\ StepFor(Log[l])
    /\ k' = k + 1
    /\ UNCHANGED l

(* A rejected trace: the last "line" TLC prints is the first line no     *)
(* placement could consume.                                                *)
Consume ==
    /\ l <= Len(Log)
    /\ Obs(Log[l])
    /\ l + 1 > TLCGet(1) => TLCSet(1, l + 1) /\ PrintT(<<"line", l + 1>>)
    /\ l' = l + 1
    /\ k' = 0
    /\ UNCHANGED vars

TraceNext == Silent \/ Consume

TraceSpec == TraceInit /\ [][TraceNext]_tvars

(* Violated exactly when every line has been consumed: the trace is accepted. *)
TraceNotDone == l <= Len(Log)

=============================================================================
