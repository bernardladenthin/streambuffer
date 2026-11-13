\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------- MODULE StreamBufferWaitForeverLive ---------------------
(***************************************************************************)
(* The argument that every call returns although threads call forever      *)
(* (StreamBufferWaitForever.tla), for any number of threads, writers and   *)
(* closers; the proof is StreamBufferWaitForeverLiveProof.tla.             *)
(*                                                                         *)
(* Fairness by role (FairRole): the thread r itself, the holder of         *)
(* bufferLock, the holder of waitLock, a signaling writer or closer, a     *)
(* closing closer. Each follows from the weak fairness per thread, writer  *)
(* and closer of FairProc: a holder stays the holder while its step is     *)
(* possible (only its own step releases the lock), and a closer at close   *)
(* or a signaler at siglock stays enabled while the shared lock it needs   *)
(* is free (TLC checks FairProc => FairRole in WaitForeverMeasure2.cfg).   *)
(*                                                                         *)
(* The measure of a thread r, FMeas(r), a natural number, is lowered by    *)
(* every step but a return of r, or kept, and a step that keeps it moves   *)
(* neither r nor a lock holder nor a writer or closer (FKeeps). Its parts, *)
(* each paying for the largest rise of the parts below it:                 *)
(* 1. FIP: what writers, closers and commits still have to do;             *)
(* 2. Buffered: the bytes a copy can still take;                           *)
(* 3. FBad: the threads at bufferLock whose re-check fails (stale since    *)
(*    a commit);                                                           *)
(* 4. FSumV: a stage per thread, the same on the cycles of returns that    *)
(*    take no lock (a fast-path return, -1, the closed branch), lower with *)
(*    every lock taken; a wait that will not park (FPass) ranks above one  *)
(*    that will;                                                           *)
(* 5. FRank(r): r's position in its call.                                  *)
(* With every part fixed, the steps of the other threads that keep the     *)
(* measure take no lock, so a thread that waits for a lock waits for its   *)
(* holder only, and that holder's step lowers the measure.                 *)
(***************************************************************************)
EXTENDS StreamBufferWaitForever

\* the wait of q would not park now; the re-check of q under bufferLock would succeed now
FPass(q) == avail >= Want(q) \/ closed
FOk(q) == avail >= K[q] \/ (closed /\ avail > 0)

FNT == Cardinality(Threads)

\* 1.
FIP ==
    2 * (Bytes - w) + (Bytes - t)
    + 2 * Cardinality({i \in Writers : wpc[i] = "siglock"})
    + Cardinality({i \in Writers : wpc[i] = "write"})
    + 2 * Cardinality({c \in Closers : cpc[c] = "close"})
    + Cardinality({c \in Closers : cpc[c] = "siglock"})

\* 3.
FBadSet == {q \in Threads : rpc[q] \in {"lock", "decide"} /\ ~FOk(q)}
FBad == Cardinality(FBadSet)

\* 4.
FV(q) ==
    CASE rpc[q] \in {"start", "reread", "ret0"} -> 4
      [] rpc[q] \in {"lockwait", "woken"} -> IF FPass(q) THEN 9 ELSE 3
      [] rpc[q] = "inc" -> IF FPass(q) THEN 8 ELSE 2
      [] rpc[q] = "test" -> IF FPass(q) THEN 7 ELSE 1
      [] rpc[q] = "wret" -> 5
      [] rpc[q] = "lock" -> 3
      [] rpc[q] = "decide" -> 2
      [] rpc[q] \in {"copy", "finish"} -> 1
      [] OTHER -> 0
FVF == [q \in Threads |-> FV(q)]
\* the sum of FV over the threads as 10 layers, layer k the number of threads with FV >= k
\* (LSum of StreamBufferCountLemmas.tla, which TLC cannot load)
FLay(k) == Cardinality({q \in Threads : FVF[q] >= k})
FSumV == (FLay(1) + FLay(2) + FLay(3) + FLay(4) + FLay(5))
         + (FLay(6) + FLay(7) + FLay(8) + FLay(9) + FLay(10))

\* 5.
FRank(q) ==
    CASE rpc[q] = "start" -> 6
      [] rpc[q] \in {"reread", "lockwait", "woken"} -> 5
      [] rpc[q] \in {"ret0", "inc", "lock"} -> 4
      [] rpc[q] \in {"test", "decide"} -> 3
      [] rpc[q] \in {"wret", "copy"} -> 2
      [] rpc[q] \in {"parked", "finish"} -> 1
      [] OTHER -> 0

\* a drop of FIP by one pays for any rise of the parts below it (Buffered rises with a write by
\* the bytes written, which lowers FIP by twice as many, less one)
FW == 30 * FNT + 10
FMeas(r) == FW * FIP + Buffered + 8 * FBad + 2 * FSumV + FRank(r)

\* a step that keeps the measure moves neither r nor a lock holder nor a writer or closer
FFrame(r) ==
    /\ rpc'[r] = rpc[r] /\ bl' = bl /\ wl' = wl /\ parked' = parked /\ wpc' = wpc /\ cpc' = cpc
    /\ \A q \in Threads : (rpc'[q] # rpc[q] \/ hold'[q] # hold[q] \/ left'[q] # left[q])
                             => bl # q /\ wl # q
FKeeps(r) == FMeas(r)' < FMeas(r) \/ (FMeas(r)' = FMeas(r) /\ FFrame(r))

-----------------------------------------------------------------------------
\* fairness by role
BLHolder == \E q \in Threads : bl = q /\ ThreadStep(q)
WLHolder == \E q \in Threads : wl = q /\ ThreadStep(q)
Signal == (\E i \in Writers : WriterSigLock(i)) \/ (\E c \in Closers : CloserSigLock(c))
Closing == \E c \in Closers : CloserClose(c)
FairRole ==
    /\ \A r \in Threads : WF_vars(ThreadStep(r))
    /\ WF_vars(BLHolder) /\ WF_vars(WLHolder) /\ WF_vars(Signal) /\ WF_vars(Closing)
SpecRole == Init /\ [][NextF]_vars /\ FairRole

-----------------------------------------------------------------------------
\* TLC probe of the argument (WaitForeverMeasure2.cfg)
MeasureSteps == [][\A r \in Threads : Ret(r) \/ FKeeps(r)]_vars
=============================================================================
