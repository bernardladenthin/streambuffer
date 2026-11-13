\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------- MODULE StreamBufferWaitLiveProof ---------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): with at least one closer and a finite   *)
(* set of threads, every behaviour of StreamBufferWait with weak fairness  *)
(* of Next ends with every call returned and every thread, writer and      *)
(* closer done, for ANY number of threads, writers and closers, any read   *)
(* sizes and requests, bytes, chunking and budget of calls. The steps:     *)
(* LiveInv is an invariant, the natural number Pot goes down with every    *)
(* step, a step is possible until all are done, and an induction over Pot *)
(* (StreamBufferWaitLive.tla).                                             *)
(***************************************************************************)
EXTENDS StreamBufferWaitLive, StreamBufferWaitEnabled, StreamBufferCountLemmas, NaturalsInduction, TLAPS

ASSUME LiveAssump == IsFiniteSet(Threads) /\ NC >= 1

\* the parts of Pot
WW == Cardinality(At(Writers, wpc, "write"))
WS == Cardinality(At(Writers, wpc, "siglock"))
CC == Cardinality(At(Closers, cpc, "close"))
CS == Cardinality(At(Closers, cpc, "siglock"))
TP == LSum(Threads, RankF)
GP == GlobalPot

LEMMA Fin == /\ IsFiniteSet(Threads) /\ IsFiniteSet(Writers) /\ IsFiniteSet(Closers)
             /\ NT \in Nat /\ Wake \in Nat /\ Wake = 10 * NT + 2
             /\ Cardinality(Writers) = NW /\ Cardinality(Closers) = NC
  <1>1 IsFiniteSet(Writers) /\ Cardinality(Writers) = NW
    BY ConstAssump, FS_Interval DEF Writers
  <1>2 IsFiniteSet(Closers) /\ Cardinality(Closers) = NC
    BY ConstAssump, FS_Interval DEF Closers
  <1>3 NT \in Nat
    BY LiveAssump, FS_CardinalityType DEF NT
  <1> QED
    BY <1>1, <1>2, <1>3, LiveAssump DEF Wake

\* a * b >= a for b >= 1
LEMMA MulGe == ASSUME NEW a \in Nat, NEW b \in Nat, b >= 1 PROVE a * b >= a /\ a * b \in Nat
  OBVIOUS

LEMMA RankRange == RankF \in [Threads -> 0..10]
  BY DEF RankF, Rank

LEMMA PotSplit == Pot = TP + (WW + Wake * WS) + ((Wake + 1) * CC + Wake * CS) + GP
  BY DEF Pot, ThreadPot, Layer, LSum, LLo, LHi, Lay, WriterPot, CloserPot, At, TP, WW, WS, CC, CS, GP, GlobalPot

\* the parts are natural numbers in a state of SafeInv
LEMMA PartsType ==
  ASSUME SafeInv
  PROVE /\ TP \in Nat /\ TP <= 10 * NT
        /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
        /\ Bytes - w \in Nat /\ Bytes - t \in Nat /\ Buffered \in Nat /\ calls \in Nat
        /\ spurious \in Nat /\ GP \in Nat /\ Pot \in Nat
  <1>1 TP \in Nat /\ TP <= 10 * NT
    BY Fin, LSumType DEF TP, NT
  <1>2 WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
    BY Fin, AtType DEF WW, WS, CC, CS
  <1>3 Bytes - w \in Nat /\ Bytes - t \in Nat /\ Buffered \in Nat /\ calls \in Nat
       /\ spurious \in Nat
    BY ConstAssump DEF SafeInv, TypeOK, BufNonNeg, Buffered, InFlight
  <1>4 GP \in Nat
    BY <1>3, Fin DEF GP, GlobalPot
  <1>5 Pot \in Nat
    BY <1>1, <1>2, <1>4, Fin, PotSplit
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5

LEMMA LiveInit == Init => LiveInv
  <1> SUFFICES ASSUME Init PROVE LiveInv
    OBVIOUS
  <1>1 SafeInv
    BY InitSafe
  <1>2 ClosedNoPark
    BY DEF Init, ClosedNoPark
  <1> QED
    BY <1>1, <1>2 DEF LiveInv

LEMMA LiveStep == LiveInv /\ [Next]_vars => LiveInv'
  <1> SUFFICES ASSUME LiveInv, [Next]_vars PROVE LiveInv'
    OBVIOUS
  <1>1 SafeInv /\ SafeInv'
    BY StepSafe DEF LiveInv
  <1>2 ClosedNoPark
    BY DEF LiveInv
  \* once a closer is done the buffer is closed, and a thread parks only on an open buffer
  <1>3 (\E c \in Closers : cpc[c] = "done") => closed
    BY <1>1 DEF SafeInv, CloserInv
  <1>4 ClosedNoPark'
    <2>1 CASE \E i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
      BY <2>1, <1>2 DEF WriterWrite, WriterSigLock, WakeAll, WGo, ClosedNoPark
    <2>2 CASE \E c \in Closers : CloserClose(c) \/ CloserSigLock(c)
      <3> PICK c \in Closers : CloserClose(c) \/ CloserSigLock(c)
        BY <2>2
      <3>1 CASE CloserClose(c)
        <4>1 \A x \in Closers : cpc'[x] = "done" => cpc[x] = "done"
          BY <3>1, <1>1 DEF CloserClose, CGo, SafeInv, TypeOK
        <4> QED
          BY <4>1, <3>1, <1>2 DEF CloserClose, ClosedNoPark
      <3>2 CASE CloserSigLock(c)
        BY <3>2 DEF CloserSigLock, WakeAll, CGo, ClosedNoPark
      <3> QED
        BY <3>1, <3>2
    <2>3 CASE \E r \in Threads : ThreadStep(r)
      <3> PICK r \in Threads : ThreadStep(r)
        BY <2>3
      <3>1 cpc' = cpc
        BY DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
               ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0,
               Go, Return, EndCall
      <3>2 parked' # parked => ThreadTest(r) /\ ~closed
        BY DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
               ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0,
               Go, Return, EndCall
      <3> QED
        BY <3>1, <3>2, <1>2, <1>3 DEF ClosedNoPark
    <2>4 CASE UNCHANGED vars
      BY <2>4, <1>2 DEF vars, ClosedNoPark
    <2>5 CASE \E r \in Threads : SpuriousWake(r)
      BY <2>5, <1>2 DEF SpuriousWake, Go, ClosedNoPark
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF Next
  <1> QED
    BY <1>1, <1>4 DEF LiveInv

LEMMA PotDec == LiveInv /\ Next => Pot' < Pot
  <1> SUFFICES ASSUME LiveInv, Next PROVE Pot' < Pot
    OBVIOUS
  <1>1 SafeInv /\ SafeInv'
    BY StepSafe DEF LiveInv
  <1>2 Pot' = TP' + (WW' + Wake * WS') + ((Wake + 1) * CC' + Wake * CS') + GP'
    BY DEF Pot, ThreadPot, Layer, LSum, LLo, LHi, Lay, WriterPot, CloserPot, At, TP, WW, WS, CC, CS, GP, GlobalPot
  <1>3 /\ TP \in Nat /\ TP <= 10 * NT /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
       /\ Bytes - w \in Nat /\ Bytes - t \in Nat /\ Buffered \in Nat /\ calls \in Nat /\ GP \in Nat
       /\ spurious \in Nat
    BY <1>1, PartsType
  <1>4 /\ TP' \in Nat /\ TP' <= 10 * NT /\ WW' \in Nat /\ WS' \in Nat /\ CC' \in Nat /\ CS' \in Nat
       /\ Bytes - w' \in Nat /\ Bytes - t' \in Nat /\ Buffered' \in Nat /\ calls' \in Nat /\ GP' \in Nat
       /\ spurious' \in Nat
    <2>1 TP' \in Nat /\ TP' <= 10 * NT
      BY Fin, LSumType DEF TP, NT
    <2>2 WW' \in Nat /\ WS' \in Nat /\ CC' \in Nat /\ CS' \in Nat
      BY Fin, AtType DEF WW, WS, CC, CS
    <2>3 Bytes - w' \in Nat /\ Bytes - t' \in Nat /\ Buffered' \in Nat /\ calls' \in Nat
         /\ spurious' \in Nat
      BY <1>1, ConstAssump DEF SafeInv, TypeOK, BufNonNeg, Buffered, InFlight
    <2>4 GP' \in Nat
      BY <2>3, Fin DEF GP, GlobalPot
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4
  \* the types the case arithmetic needs, and nothing else (more facts make the SMT backend fail)
  <1>5 TP \in Nat /\ GP \in Nat /\ calls \in Nat
    BY <1>3
  <1>6 TP' \in Nat /\ GP' \in Nat /\ calls' \in Nat
    BY <1>4
  <1> USE ConstAssump, LiveAssump

  <1>10 CASE \E i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
    <2> PICK i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
      BY <1>10
    <2>0 \A x \in Writers \ {i} : wpc'[x] = wpc[x]
      BY <1>1 DEF WriterWrite, WriterSigLock, WGo, SafeInv, TypeOK
    <2>a CC' = CC /\ CS' = CS
      BY DEF WriterWrite, WriterSigLock, CC, CS
    <2>b WW' = WW - (IF wpc[i] = "write" THEN 1 ELSE 0) + (IF wpc'[i] = "write" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF WW
    <2>c WS' = WS - (IF wpc[i] = "siglock" THEN 1 ELSE 0) + (IF wpc'[i] = "siglock" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF WS
    <2>1 CASE WriterWrite(i)
      <3>1 \A x \in Threads : RankF'[x] \in Int /\ RankF[x] \in Int /\ RankF'[x] <= RankF[x]
        BY <2>1, <1>1 DEF WriterWrite, WGo, SafeInv, TypeOK, RankF, Rank, Ok
      <3>2 TP' <= TP
        BY <3>1, Fin, LSumMono DEF TP
      <3>3 CASE closed \/ w >= Bytes
        <4>1 WW' = WW - 1 /\ WS' = WS
          BY <3>3, <2>1, <2>b, <2>c, <1>1, <1>3, <1>4 DEF WriterWrite, WGo, SafeInv, TypeOK
        <4>2 GP' = GP
          BY <3>3, <2>1, <1>1, <1>3 DEF WriterWrite, GP, GlobalPot, Buffered, InFlight, SafeInv, TypeOK
        <4> QED
          BY <4>1, <4>2, <3>2, <2>a, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>4 CASE ~(closed \/ w >= Bytes)
        <4> PICK c \in 1..Bytes : c <= Bytes - w /\ w' = w + c /\ avail' = avail + c
          BY <3>4, <2>1, <1>1, <1>3 DEF WriterWrite, SafeInv, TypeOK
        <4>1 WW' = WW - 1 /\ WS' = WS + 1
          BY <3>4, <2>1, <2>b, <2>c, <1>1, <1>3, <1>4 DEF WriterWrite, WGo, SafeInv, TypeOK
        <4>2 Wake * WS' = Wake * WS + Wake
          BY <4>1, <1>3, Fin
        <4>3 Buffered' = Buffered + c /\ t' = t /\ calls' = calls /\ spurious' = spurious
          BY <2>1, <1>1 DEF WriterWrite, Buffered, InFlight, SafeInv, TypeOK
        <4>4 (Wake + 2) * (Bytes - w') = (Wake + 2) * (Bytes - w) - (Wake + 2) * c
          BY <1>1, <1>3, Fin DEF SafeInv, TypeOK
        <4>5 (Wake + 2) * c >= Wake + 1 + c
          <5>1 (Wake + 1) * c >= Wake + 1
            BY Fin, MulGe
          <5> QED
            BY <5>1, Fin
        <4>6 GP' <= GP - Wake - 1
          BY <4>3, <4>4, <4>5, <1>3, <1>4, Fin DEF GP, GlobalPot
        <4> QED
          BY <4>1, <4>2, <4>6, <3>2, <2>a, PotSplit, <1>2, <1>3, <1>4, Fin
      <3> QED
        BY <3>3, <3>4
    <2>2 CASE WriterSigLock(i)
      <3>1 WS' = WS - 1 /\ WW' <= WW + 1
        BY <2>2, <2>b, <2>c, <1>1, <1>3, <1>4 DEF WriterSigLock, WGo, WriterNext, SafeInv, TypeOK
      <3>2 Wake * WS' = Wake * WS - Wake
        BY <3>1, <1>3, Fin
      <3>3 GP' = GP
        BY <2>2 DEF WriterSigLock, GP, GlobalPot, Buffered, InFlight
      <3> QED
        BY <3>1, <3>2, <3>3, <2>a, PotSplit, <1>2, <1>3, <1>4, Fin
    <2> QED
      BY <2>1, <2>2

  <1>11 CASE \E c \in Closers : CloserClose(c) \/ CloserSigLock(c)
    <2> PICK c \in Closers : CloserClose(c) \/ CloserSigLock(c)
      BY <1>11
    <2>0 \A x \in Closers \ {c} : cpc'[x] = cpc[x]
      BY <1>1 DEF CloserClose, CloserSigLock, CGo, SafeInv, TypeOK
    <2>a WW' = WW /\ WS' = WS
      BY DEF CloserClose, CloserSigLock, WW, WS
    <2>b CC' = CC - (IF cpc[c] = "close" THEN 1 ELSE 0) + (IF cpc'[c] = "close" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF CC
    <2>c CS' = CS - (IF cpc[c] = "siglock" THEN 1 ELSE 0) + (IF cpc'[c] = "siglock" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF CS
    <2>d GP' = GP
      BY DEF CloserClose, CloserSigLock, GP, GlobalPot, Buffered, InFlight
    <2>1 CASE CloserClose(c)
      <3>1 \A x \in Threads : RankF'[x] \in Int /\ RankF[x] \in Int /\ RankF'[x] <= RankF[x]
        BY <2>1, <1>1 DEF CloserClose, CGo, SafeInv, TypeOK, RankF, Rank, Ok
      <3>2 TP' <= TP
        BY <3>1, Fin, LSumMono DEF TP
      <3>3 CC' = CC - 1 /\ CS' = CS + 1
        BY <2>1, <2>b, <2>c, <1>1, <1>3, <1>4 DEF CloserClose, CGo, SafeInv, TypeOK
      <3>4 (Wake + 1) * CC' + Wake * CS' = (Wake + 1) * CC + Wake * CS - 1
        BY <3>3, <1>3, Fin
      <3> QED
        BY <3>2, <3>4, <2>a, <2>d, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>2 CASE CloserSigLock(c)
      <3>1 CC' = CC /\ CS' = CS - 1
        BY <2>2, <2>b, <2>c, <1>1, <1>3, <1>4 DEF CloserSigLock, CGo, SafeInv, TypeOK
      <3>2 (Wake + 1) * CC' + Wake * CS' = (Wake + 1) * CC + Wake * CS - Wake
        BY <3>1, <1>3, Fin
      <3> QED
        BY <3>2, <2>a, <2>d, PotSplit, <1>2, <1>3, <1>4, Fin
    <2> QED
      BY <2>1, <2>2

  <1>12 CASE \E r \in Threads : ThreadStep(r)
    <2> PICK r \in Threads : ThreadStep(r)
      BY <1>12
    <2>0 spurious' = spurious
      BY DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
             ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0
    <2> USE <2>0
    <2>1 CASE ThreadStart(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>1 DEF ThreadStart, Go, Return, EndCall, Want, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>1, <1>1 DEF ThreadStart, Go, Return, EndCall, Want, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>1, <1>1 DEF ThreadStart, Go, Return, EndCall, Want, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>1, <1>1, <1>3, <1>4 DEF ThreadStart, Go, Return, EndCall, Want, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>2 CASE ThreadReread(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>2 DEF ThreadReread, Go, Return, EndCall, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>2, <1>1 DEF ThreadReread, Go, Return, EndCall, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>2, <1>1 DEF ThreadReread, Go, Return, EndCall, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>2, <1>1, <1>3, <1>4 DEF ThreadReread, Go, Return, EndCall, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>3 CASE ThreadWaitLock(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>3 DEF ThreadWaitLock, Go, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>3, <1>1 DEF ThreadWaitLock, Go, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>3, <1>1 DEF ThreadWaitLock, Go, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>3, <1>1, <1>3, <1>4 DEF ThreadWaitLock, Go, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>4 CASE ThreadInc(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>4 DEF ThreadInc, Go, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>4, <1>1 DEF ThreadInc, Go, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>4, <1>1 DEF ThreadInc, Go, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>4, <1>1, <1>3, <1>4 DEF ThreadInc, Go, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>5 CASE ThreadTest(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>5 DEF ThreadTest, Go, Return, EndCall, Want, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>5, <1>1 DEF ThreadTest, Go, Return, EndCall, Want, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>5, <1>1 DEF ThreadTest, Go, Return, EndCall, Want, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>5, <1>1, <1>3, <1>4 DEF ThreadTest, Go, Return, EndCall, Want, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>6 CASE ThreadWaitReturn(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>6 DEF ThreadWaitReturn, Go, Return, EndCall, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>6, <1>1 DEF ThreadWaitReturn, Go, Return, EndCall, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>6, <1>1 DEF ThreadWaitReturn, Go, Return, EndCall, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>6, <1>1, <1>3, <1>4 DEF ThreadWaitReturn, Go, Return, EndCall, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>7 CASE ThreadLock(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>7 DEF ThreadLock, Go, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>7, <1>1 DEF ThreadLock, Go, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>7, <1>1 DEF ThreadLock, Go, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>7, <1>1, <1>3, <1>4 DEF ThreadLock, Go, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>8 CASE ThreadDecide(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>8 DEF ThreadDecide, Go, Min, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>8, <1>1 DEF ThreadDecide, Go, Min, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>8, <1>1 DEF ThreadDecide, Go, Min, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>8, <1>1, <1>3, <1>4 DEF ThreadDecide, Go, Min, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>9 CASE ThreadCopy(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>9 DEF ThreadCopy, Go, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>9, <1>1 DEF ThreadCopy, Go, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' < Buffered /\ calls' = calls
        BY <2>9, <1>1, <1>3, <1>4 DEF ThreadCopy, Go, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' < GP
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] <= RankF[r]
        BY <2>9, <1>1 DEF ThreadCopy, Go, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY <3>2, <3>4, <3>6, <3>7, <1>3, <1>4
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>10 CASE ThreadFinish(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>10 DEF ThreadFinish, Go, EndCall, WW, WS, CC, CS
      <3>2 hold[r] \in Nat /\ hold[r] >= 1 /\ bl = r /\ t \in Nat /\ w \in Nat
        BY <2>10, <1>1 DEF ThreadFinish, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>3 Buffered' = Buffered /\ w' = w /\ t' = t + hold[r] /\ calls' <= calls /\ calls' \in Nat
        BY <2>10, <3>2, <1>1, <1>3 DEF ThreadFinish, Go, EndCall, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>4 (10 * NT + 1) * (Bytes - t') <= (10 * NT + 1) * (Bytes - t) - (10 * NT + 1)
        <4>1 (10 * NT + 1) * hold[r] >= 10 * NT + 1
          BY <3>2, Fin, MulGe
        <4>2 (10 * NT + 1) * (Bytes - t') = (10 * NT + 1) * (Bytes - t) - (10 * NT + 1) * hold[r]
          BY <3>2, <3>3, Fin
        <4> QED
          BY <4>1, <4>2, <3>2, <1>3, <1>4, Fin
      <3>5 GP' <= GP - (10 * NT + 1)
        BY <3>3, <3>4, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3> QED
        BY <3>1, <3>5, PotSplit, <1>2, <1>3, <1>4, Fin
    <2>11 CASE ThreadRet0(r)
      <3>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
        BY <2>11 DEF ThreadRet0, Go, EndCall, WW, WS, CC, CS
      <3>2 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
        BY <2>11, <1>1 DEF ThreadRet0, Go, EndCall, RankF, Rank, Ok, SafeInv, TypeOK
      <3>4 TP' = TP - RankF[r] + RankF'[r]
        BY <3>2, <3>3, Fin, LSumExcept DEF TP
      <3>5 w' = w /\ t' = t /\ Buffered' = Buffered
        BY <2>11, <1>1 DEF ThreadRet0, Go, EndCall, Buffered, InFlight, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>6 GP' - 9 * calls' = GP - 9 * calls
        BY <3>5, <1>3, <1>4, Fin DEF GP, GlobalPot
      <3>7 RankF'[r] + 9 * calls' < RankF[r] + 9 * calls
        BY <2>11, <1>1, <1>3, <1>4 DEF ThreadRet0, Go, EndCall, RankF, Rank, Ok, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WholeRead, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv, States, Ops, Writers, Closers
      <3>8 Pot' - Pot = (TP' - TP) + (GP' - GP)
        BY <3>1, PotSplit, <1>2, <1>3, <1>4, Fin
      <3>9 (TP' - TP) + (GP' - GP) < 0
        BY ONLY <3>2, <3>4, <3>6, <3>7, <1>5, <1>6
      <3> QED
        BY <3>8, <3>9, PotSplit, <1>2, <1>3, <1>4, Fin
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11 DEF ThreadStep
  \* a spurious wake-up lifts the woken thread's rank from 1 to 6 and pays 10 from the budget
  <1>13 CASE \E r \in Threads : SpuriousWake(r)
    <2> PICK r \in Threads : SpuriousWake(r)
      BY <1>13
    <2>1 WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
      BY DEF SpuriousWake, WW, WS, CC, CS
    <2>2 RankF[r] = 1 /\ RankF'[r] = 6
      BY <1>1 DEF SpuriousWake, Go, RankF, Rank, SafeInv, TypeOK
    <2>3 \A x \in Threads \ {r} : RankF'[x] = RankF[x]
      BY <1>1 DEF SpuriousWake, Go, RankF, Rank, Ok, SafeInv, TypeOK
    <2>4 TP' = TP - RankF[r] + RankF'[r]
      <3>1 RankF[r] \in 0..10 /\ RankF'[r] \in 0..10
        BY DEF RankF, Rank
      <3> QED
        BY <2>3, <3>1, Fin, LSumExcept DEF TP
    <2>5 GP' = GP - 10
      <3>1 w' = w /\ t' = t /\ calls' = calls /\ Buffered' = Buffered /\ spurious' = spurious - 1
        BY <1>1 DEF SpuriousWake, Buffered, InFlight, SafeInv, TypeOK
      <3> QED
        BY <3>1, <1>3, <1>4, Fin DEF GP, GlobalPot
    <2> QED
      BY <2>1, <2>2, <2>4, <2>5, PotSplit, <1>2, <1>3, <1>4, Fin
  <1> QED
    BY <1>10, <1>11, <1>12, <1>13 DEF Next

THEOREM LiveInvariant == CSpec => []LiveInv
  BY LiveInit, LiveStep, PTL DEF CSpec

LEMMA PotNatInv == LiveInv => Pot \in Nat
  BY PartsType DEF LiveInv

\* a stuttering step leaves Pot and AllDone as they are
LEMMA Stutter == ASSUME UNCHANGED vars PROVE Pot' = Pot /\ (AllDone' <=> AllDone)
  BY DEF vars, Pot, ThreadPot, Layer, RankF, Rank, Ok, WriterPot, CloserPot, GlobalPot, Buffered,
         InFlight, AllDone, Wake, NT

\* a step is possible until all are done (StreamBufferWaitEnabled.tla)
LEMMA EnabledLive == LiveInv /\ ~AllDone => ENABLED <<Next>>_vars
  BY Progress, LiveAssump DEF LiveInv, ClosedNoPark, AllDone

\* an upper bound of Pot in the initial state
PotMax == 10 * NT + NW + (Wake + 1) * NC + (Wake + 2) * Bytes + (10 * NT + 1) * Bytes + 9 * Calls0
          + 10 * Spurious

LEMMA InitPot == Init => Pot <= PotMax /\ PotMax \in Nat
  <1> SUFFICES ASSUME Init PROVE Pot <= PotMax /\ PotMax \in Nat
    OBVIOUS
  <1>1 SafeInv
    BY InitSafe
  <1>2 TP <= 10 * NT /\ TP \in Nat
    BY <1>1, PartsType
  <1>3 WW <= NW /\ WW \in Nat
    BY Fin, AtType DEF WW
  <1>4 At(Writers, wpc, "siglock") = {} /\ At(Closers, cpc, "siglock") = {}
       /\ At(Closers, cpc, "close") = Closers
    BY DEF Init, At
  <1>5 WS = 0 /\ CS = 0 /\ CC = NC
    BY <1>4, Fin, FS_EmptySet DEF WS, CS, CC
  <1>6 GP = (Wake + 2) * Bytes + (10 * NT + 1) * Bytes + 9 * Calls0 + 10 * Spurious
    BY ConstAssump, Fin DEF Init, GP, GlobalPot, Buffered, InFlight
  <1>7 PotMax \in Nat
    BY Fin, ConstAssump DEF PotMax
  <1>8 Wake * WS = 0 /\ Wake * CS = 0 /\ (Wake + 1) * CC = (Wake + 1) * NC
    BY <1>5, Fin
  <1> QED
    BY PotSplit, <1>2, <1>3, <1>5, <1>6, <1>7, <1>8, Fin, ConstAssump DEF PotMax

\* the liveness theorem: every behaviour of FairSpec ends with all done
THEOREM Liveness == FairSpec => Termination
  <1>1 FairSpec => []LiveInv
    BY LiveInvariant, PTL DEF FairSpec
  <1> DEFINE P(n) == FairSpec => [](LiveInv /\ Pot < n => <>AllDone)
  <1> HIDE DEF P
  <1>2 \A n \in Nat : P(n)
    <2>1 P(0)
      <3>1 LiveInv /\ Pot < 0 => AllDone
        BY PotNatInv
      <3> QED
        BY <3>1, PTL DEF P
    <2>2 ASSUME NEW n \in Nat PROVE P(n) => P(n + 1)
      <3> DEFINE P0 == LiveInv /\ Pot = n /\ ~AllDone
                 Q0 == (LiveInv /\ Pot < n) \/ AllDone
      <3>1 LiveInv /\ Pot < n + 1 => (LiveInv /\ Pot < n) \/ P0 \/ AllDone
        BY PotNatInv
      <3>2 P0 /\ [Next]_vars => P0' \/ Q0'
        <4> SUFFICES ASSUME P0, [Next]_vars PROVE P0' \/ Q0'
          OBVIOUS
        <4>1 LiveInv'
          BY LiveStep
        <4>2 CASE Next
          BY <4>1, <4>2, PotDec
        <4>3 CASE UNCHANGED vars
          BY <4>1, <4>3, Stutter
        <4> QED
          BY <4>2, <4>3
      <3>3 P0 /\ <<Next>>_vars => Q0'
        BY LiveStep, PotDec
      <3>4 P0 => ENABLED <<Next>>_vars
        BY EnabledLive
      <3> QED
        BY <1>1, <3>1, <3>2, <3>3, <3>4, PTL DEF P, FairSpec, CSpec
    <2> QED
      BY <2>1, <2>2, NatInduction, Isa
  <1>3 P(PotMax + 1)
    BY <1>2, InitPot, Fin, ConstAssump DEF PotMax
  <1>4 Init => LiveInv /\ Pot < PotMax + 1
    BY LiveInit, InitPot, PotNatInv
  <1> QED
    BY <1>3, <1>4, PTL DEF P, FairSpec, CSpec, Termination
=============================================================================
