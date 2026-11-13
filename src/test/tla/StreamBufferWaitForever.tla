\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------- MODULE StreamBufferWaitForever -----------------------
(***************************************************************************)
(* Liveness of StreamBufferWait with threads that call forever (TODO, A13  *)
(* follow-up). StreamBufferWait bounds the calls by a shared budget; here  *)
(* the ghost step Refill tops it up whenever it is used up, so a thread    *)
(* can always call again. Every run in which threads call forever is a run *)
(* of this module with a Refill after each return; the module also has     *)
(* runs in which threads stop, which only adds behaviours, so a property   *)
(* of all its fair runs holds for the forever runs.                        *)
(*                                                                         *)
(* Fairness is per process and weak: a thread, writer or closer that can   *)
(* go on all the time eventually does (the scheduler runs a runnable       *)
(* thread). No lock fairness: a thread waiting for a lock that is free     *)
(* only now and then may never get it (the JDK's monitor and the           *)
(* ReentrantLock(false) of waitLock barge).                                *)
(*                                                                         *)
(* The infinite stream: the ghost step Shift lowers w and t together by    *)
(* RecLen. The code sees only their difference (availableBytes and the     *)
(* buffered bytes), so with Shift the writer writes forever in a finite    *)
(* state space (its backlog bounded by Bytes, a subset of its runs).       *)
(***************************************************************************)
EXTENDS StreamBufferWait

Refill ==
    /\ calls = 0 /\ calls' = 1
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, rpc, op, hold, left, off, wres, wclosed, eofAt,
                   parked, wl, bl>>

NextF == Next \/ Refill

WStep(i) == WriterWrite(i) \/ WriterSigLock(i)
CStep(c) == CloserClose(c) \/ CloserSigLock(c)

\* weak fairness per thread, writer and closer; Refill is a ghost and always taken
FairProc ==
    /\ \A i \in Writers : WF_vars(WStep(i))
    /\ \A c \in Closers : WF_vars(CStep(c))
    /\ \A r \in Threads : WF_vars(ThreadStep(r))
    /\ WF_vars(Refill)

SpecF == Init /\ [][NextF]_vars /\ FairProc

\* negative control: only the system as a whole goes on while it can (the fairness of
\* StreamBufferWaitLive.tla), nothing per thread
SpecNextOnly == Init /\ [][NextF]_vars /\ WF_vars(NextF)

\* a call of r returns (a failed re-check under bufferLock goes back to "start" too, but the
\* call goes on)
Ret(r) == ThreadStep(r) /\ rpc[r] # "decide" /\ rpc'[r] \in {"start", "done"}

\* every call of every thread returns: a thread returns again and again, or it stopped
EveryCallReturns == \A r \in Threads : []<><<Ret(r)>>_vars \/ <>(rpc[r] = "done")

\* probe that must fail: every fair run ends with all threads stopped (it fails because some
\* fair runs call forever, so the property above speaks about them)
AllStop == <>(\A r \in Threads : rpc[r] = "done")

-----------------------------------------------------------------------------
(* The infinite stream (no closer in its models) *)
Shift ==
    /\ t >= RecLen /\ eofAt = -1 /\ w' = w - RecLen /\ t' = t - RecLen
    /\ UNCHANGED <<avail, closed, wpc, cpc, rpc, op, calls, hold, left, off, wres, wclosed, eofAt,
                   parked, wl, bl>>

NextI == NextF \/ Shift

\* the strongest fairness per thread: every thread step strongly fair (fair locks, and more)
FairStrong ==
    /\ \A i \in Writers : WF_vars(WStep(i))
    /\ \A r \in Threads : SF_vars(ThreadStep(r))
    /\ WF_vars(Refill) /\ WF_vars(Shift)

SpecI == Init /\ [][NextI]_vars /\ FairStrong

\* the writer writes forever (it does not stop at the bound of the backlog)
WritesForever == []<><<\E i \in Writers : WriterWrite(i) /\ w' > w>>_vars
\* expected to fail: a reader can starve next to another one, whatever the lock fairness
StarvationFree == WritesForever => EveryCallReturns

-----------------------------------------------------------------------------
(* Constants for the TLC models (the threads are 1..n) *)
KOne == [r \in Threads |-> 1]
\* thread 1 reads single bytes, the others records of 2
KMixed == [r \in Threads |-> IF r = 1 THEN 1 ELSE 2]
MTwo == [r \in Threads |-> 2]
=============================================================================
