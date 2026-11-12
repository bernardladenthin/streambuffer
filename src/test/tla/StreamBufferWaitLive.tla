\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------------- MODULE StreamBufferWaitLive -------------------------
(***************************************************************************)
(* Liveness of StreamBufferWait (TODO roadmap A13): with at least one      *)
(* closer, every behaviour in which the system does not halt while a step  *)
(* is possible (weak fairness of Next as a whole, no fairness per thread or *)
(* lock) ends with every call returned and every thread, writer and closer *)
(* done. The argument:                                                     *)
(* - Pot, a natural number, goes down with every step (PotDecreases): the  *)
(*   bytes to write and to commit, the bytes buffered, the calls left and  *)
(*   a rank per thread, writer and closer pay for every loop (a wake-up is *)
(*   paid by the signal, a failed re-check under bufferLock by the commit  *)
(*   that took the bytes, the next call by the budget);                    *)
(* - a step is possible until all are done (NoDeadlock): a lock holder can *)
(*   always go on, and no thread parks once a closer is done, which woke   *)
(*   every parked thread after the close.                                  *)
(* Rank(r) <= 10, so the thread part is the sum of 10 layers, each the     *)
(* number of threads of at least that rank: no sum over the threads.      *)
(***************************************************************************)
EXTENDS StreamBufferWait

FairSpec == CSpec /\ WF_vars(Next)

AllDone ==
    /\ \A i \in Writers : wpc[i] \in {"done", "failed"}
    /\ \A c \in Closers : cpc[c] = "done"
    /\ \A r \in Threads : rpc[r] = "done"
Termination == <>AllDone

\* once a closer is done, nobody is parked: its signal came after the close, and a thread that
\* tests after the close does not park
ClosedNoPark == (\E c \in Closers : cpc[c] = "done") => parked = {}
LiveInv == SafeInv /\ ClosedNoPark

\* the re-check under bufferLock succeeds now
Ok(r) == avail >= K[r] \/ (closed /\ avail > 0)

Rank(r) ==
    CASE rpc[r] = "finish" -> 1
      [] rpc[r] = "copy" -> 2
      [] rpc[r] = "decide" -> IF Ok(r) THEN 3 ELSE 9
      [] rpc[r] = "lock" -> IF Ok(r) THEN 4 ELSE 10
      [] rpc[r] \in {"ret0", "wret", "parked"} -> 1
      [] rpc[r] \in {"reread", "test"} -> 5
      [] rpc[r] \in {"inc", "woken"} -> 6
      [] rpc[r] = "lockwait" -> 7
      [] rpc[r] = "start" -> 8
      [] OTHER -> 0

RankF == [r \in Threads |-> Rank(r)]
Layer(k) == {r \in Threads : RankF[r] >= k}
ThreadPot ==
    (Cardinality(Layer(1)) + Cardinality(Layer(2)) + Cardinality(Layer(3)) + Cardinality(Layer(4))
     + Cardinality(Layer(5)))
    + (Cardinality(Layer(6)) + Cardinality(Layer(7)) + Cardinality(Layer(8)) + Cardinality(Layer(9))
       + Cardinality(Layer(10)))

NT == Cardinality(Threads)
\* a signal pays for any change of the thread ranks, which the 10 layers bound by 10 * NT
Wake == 10 * NT + 2
WriterPot ==
    Cardinality({i \in Writers : wpc[i] = "write"})
    + Wake * Cardinality({i \in Writers : wpc[i] = "siglock"})
CloserPot ==
    (Wake + 1) * Cardinality({c \in Closers : cpc[c] = "close"})
    + Wake * Cardinality({c \in Closers : cpc[c] = "siglock"})

\* the bytes to write and to commit, the bytes buffered, the calls left
GlobalPot == (Wake + 2) * (Bytes - w) + Buffered + (10 * NT + 1) * (Bytes - t) + 9 * calls
Pot == ThreadPot + WriterPot + CloserPot + GlobalPot

\* Pot in the initial state
Pot0 == 8 * NT + NW + (Wake + 1) * NC + (Wake + 2) * Bytes + (10 * NT + 1) * Bytes + 9 * Calls0

-----------------------------------------------------------------------------
\* Apalache (fixed threads): the parts of the argument, as invariants
PotDecreases == Pot' < Pot
\* the guards of the actions: one of them holds until all are done
Guard ==
    \/ \E i \in Writers : wpc[i] = "write" /\ bl = None
    \/ \E i \in Writers : wpc[i] = "siglock" /\ (parked = {} \/ wl = None)
    \/ \E c \in Closers : cpc[c] = "close" /\ bl = None
    \/ \E c \in Closers : cpc[c] = "siglock" /\ (parked = {} \/ wl = None)
    \/ \E r \in Threads :
          \/ rpc[r] \in {"start", "reread", "ret0"}
          \/ rpc[r] \in {"lockwait", "woken"} /\ wl = None
          \/ rpc[r] \in {"inc", "test", "wret", "decide", "copy", "finish"}
          \/ rpc[r] = "lock" /\ bl = None
NoDeadlock == AllDone \/ Guard
PotNat == Pot \in Nat /\ (~AllDone => Pot >= 1)
LiveDomains == Domains /\ LiveInv /\ OffMod
\* Apalache: the constants of a check need a closer
ConstInitLive == Threads = {1, 2} /\ None = 0 /\ NW = 2 /\ NC = 1 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : K[r] >= 1)
             /\ M \in [{1, 2} -> Nat] /\ (\A r \in {1, 2} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE
ConstInitLive3 == Threads = {1, 2, 3} /\ None = 0 /\ NW = 2 /\ NC = 2 /\ Bytes \in Nat /\ Bytes >= 1
             /\ K \in [{1, 2, 3} -> Nat] /\ (\A r \in {1, 2, 3} : K[r] >= 1)
             /\ M \in [{1, 2, 3} -> Nat] /\ (\A r \in {1, 2, 3} : M[r] >= 1)
             /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat /\ CheckedReturn = TRUE
=============================================================================
