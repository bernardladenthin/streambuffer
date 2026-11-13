\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

-------------------------- MODULE StreamBufferForever --------------------------
(***************************************************************************)
(* The detailed model with threads that call forever (TODO, A13 follow-up; *)
(* StreamBufferWaitForever.tla is the abstraction). In StreamBuffer.tla a  *)
(* reader reads until a call returns -1 and a WaitCallers thread calls     *)
(* waitForAtLeast once; here a thread that is done calls again (Restart):  *)
(* a reader reads again after -1, a WaitCallers thread waits again, for    *)
(* ever. Fairness is weak per thread, writer and closer, no lock fairness. *)
(***************************************************************************)
EXTENDS StreamBuffer

\* the next call: the read or the wait starts again (the results so far are kept)
Restart(r) ==
    /\ rpc[r] = "done"
    /\ Goto(r, "start")
    /\ UNCHANGED <<Shared, want, cur, hold, left, reads, wres, wclosed, eofAt, Sync>>

ThreadStepF(r) == ReaderStep(r) \/ Restart(r)

NextF == Next \/ \E r \in Readers : Restart(r)

SpecF ==
    /\ Init /\ [][NextF]_vars
    /\ WF_vars(WriterStep) /\ WF_vars(CloserStep)
    /\ \A r \in Readers : WF_vars(ThreadStepF(r))

\* a call of r returns: a read with its bytes or -1, a wait with its count (a failed re-check
\* under bufferLock and a semaphore acquire go back to "start" too, but the call goes on)
Ret(r) == ReaderStep(r) /\ rpc[r] \notin {"decide", "acquire"} /\ rpc'[r] \in {"start", "done"}

\* every call of every thread returns, again and again
EveryCallReturns == \A r \in Readers : []<><<Ret(r)>>_vars

\* negative control: only the system as a whole goes on while it can
SpecNextOnly == Init /\ [][NextF]_vars /\ WF_vars(NextF)
=============================================================================
