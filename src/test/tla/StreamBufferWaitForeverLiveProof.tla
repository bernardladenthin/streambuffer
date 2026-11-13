\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------- MODULE StreamBufferWaitForeverLiveProof -------------------
(***************************************************************************)
(* TLAPS proof (TODO, A13 follow-up): with at least one closer, in every   *)
(* behaviour of StreamBufferWaitForever.tla with the fairness by role      *)
(* (StreamBufferWaitForeverLive.tla), every call of every thread returns,  *)
(* although threads call forever, for any number of threads, writers and   *)
(* closers.                                                                *)
(***************************************************************************)
EXTENDS StreamBufferWaitForeverLive, StreamBufferWaitLiveProof, NaturalsInduction, TLAPS

\* the parts of the measure in the notation of the counting lemmas
LEMMA FParts ==
  /\ FIP = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS
  /\ FIP' = 2 * (Bytes - w') + (Bytes - t') + 2 * WS' + WW' + 2 * CC' + CS'
  /\ FSumV = LSum(Threads, FVF)
  /\ FSumV' = LSum(Threads, FVF')
  /\ FNT = NT
  BY DEF FIP, WS, WW, CC, CS, At, FSumV, FLay, LSum, LLo, LHi, Lay, FNT, NT

LEMMA FVRange == ASSUME NEW q \in Threads PROVE FV(q) \in 0..9 /\ FVF[q] = FV(q)
  BY DEF FV, FVF

LEMMA FRankRange == ASSUME NEW q PROVE FRank(q) \in 0..6
  BY DEF FRank

\* the parts are natural numbers, the lower ones bounded
LEMMA FTypes ==
  ASSUME LiveInv
  PROVE /\ FNT \in Nat /\ FW \in Nat /\ FW = 30 * FNT + 10
        /\ FIP \in Nat /\ Buffered \in Nat
        /\ FBad \in Nat /\ FBad <= FNT
        /\ FSumV \in Nat /\ FSumV <= 10 * FNT
  <1>1 FNT \in Nat /\ FW \in Nat /\ FW = 30 * FNT + 10
    BY Fin, FParts DEF FW
  <1>2 FIP \in Nat /\ Buffered \in Nat
    <2>1 WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat /\ Bytes - w \in Nat
         /\ Bytes - t \in Nat /\ Buffered \in Nat
      BY PartsType DEF LiveInv
    <2> QED
      BY <2>1, FParts
  <1>3 FBad \in Nat /\ FBad <= FNT
    <2>1 FBadSet \subseteq Threads
      BY DEF FBadSet
    <2> QED
      BY <2>1, Fin, SubCard DEF FBad, FNT
  <1>4 FSumV \in Nat /\ FSumV <= 10 * FNT
    BY Fin, LSumType, FParts DEF FNT
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4

LEMMA FTypesP ==
  ASSUME LiveInv'
  PROVE /\ FIP' \in Nat /\ Buffered' \in Nat
        /\ FBad' \in Nat /\ FBad' <= FNT
        /\ FSumV' \in Nat /\ FSumV' <= 10 * FNT
  <1>1 FIP' \in Nat /\ Buffered' \in Nat
    <2>1 /\ WW' \in Nat /\ WS' \in Nat /\ CC' \in Nat /\ CS' \in Nat
      BY Fin, AtType DEF WW, WS, CC, CS
    <2>2 Bytes - w' \in Nat /\ Bytes - t' \in Nat /\ Buffered' \in Nat
      BY ConstAssump DEF LiveInv, SafeInv, TypeOK, BufNonNeg, Buffered, InFlight
    <2> QED
      BY <2>1, <2>2, FParts
  <1>2 FBad' \in Nat /\ FBad' <= FNT
    <2>1 FBadSet' \subseteq Threads
      BY DEF FBadSet
    <2> QED
      BY <2>1, Fin, SubCard DEF FBad, FNT
  <1>3 FSumV' \in Nat /\ FSumV' <= 10 * FNT
    BY Fin, LSumType, FParts DEF FNT
  <1> QED
    BY <1>1, <1>2, <1>3

LEMMA FMeasNat == ASSUME LiveInv, NEW r \in Threads PROVE FMeas(r) \in Nat
  BY FTypes, FRankRange DEF FMeas

\* the arithmetic of a drop of the first part: it pays for any rise of the others
LEMMA ArithIP ==
  ASSUME NEW n \in Nat, NEW a \in Nat, NEW b \in Nat, NEW x \in Nat, NEW x2 \in Nat,
         NEW y \in Nat, NEW y2 \in Nat, b < a, x2 - x <= a - b, y2 <= 28 * n + 6
  PROVE (30 * n + 10) * b + x2 + y2 < (30 * n + 10) * a + x + y
  <1> DEFINE d == a - b
             f == 30 * n + 10
  <1>1 d \in Nat /\ d >= 1 /\ f \in Nat /\ f >= 1
    OBVIOUS
  <1>2 f * a = f * b + f * d
    OBVIOUS
  <1>3 (f - 1) * d >= f - 1
    BY <1>1, MulGe
  <1>4 f * d = (f - 1) * d + d
    OBVIOUS
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4

\* a step that lowers FIP lowers the measure, if Buffered rises by no more than FIP drops
LEMMA IPStep ==
  ASSUME NEW r \in Threads, LiveInv, LiveInv', FIP' < FIP, Buffered' - Buffered <= FIP - FIP'
  PROVE FMeas(r)' < FMeas(r)
  <1>1 FNT \in Nat /\ FW = 30 * FNT + 10 /\ FIP \in Nat /\ Buffered \in Nat
       /\ FBad \in Nat /\ FSumV \in Nat
    BY FTypes
  <1>2 FIP' \in Nat /\ Buffered' \in Nat /\ FBad' \in Nat /\ FBad' <= FNT
       /\ FSumV' \in Nat /\ FSumV' <= 10 * FNT
    BY FTypesP
  <1>3 FRank(r) \in 0..6 /\ FRank(r)' \in 0..6
    BY FRankRange DEF FRank
  <1> DEFINE y == 8 * FBad + 2 * FSumV + FRank(r)
             y2 == 8 * FBad' + 2 * FSumV' + FRank(r)'
  <1>4 y \in Nat /\ y2 \in Nat /\ y2 <= 28 * FNT + 6
    BY <1>1, <1>2, <1>3
  <1>5 (30 * FNT + 10) * FIP' + Buffered' + y2 < (30 * FNT + 10) * FIP + Buffered + y
    BY <1>1, <1>2, <1>4, ArithIP
  <1>6 FMeas(r) = FW * FIP + Buffered + y /\ FMeas(r)' = FW * FIP' + Buffered' + y2
    BY <1>1, <1>2, <1>3, FTypes DEF FMeas, y, y2
  <1>7 FW * FIP = (30 * FNT + 10) * FIP /\ FW * FIP' = (30 * FNT + 10) * FIP'
    BY <1>1
  <1> QED
    BY ONLY <1>5, <1>6, <1>7

\* the invariant holds for NextF too: Refill changes only the budget
LEMMA LiveStepF == LiveInv /\ [NextF]_vars => LiveInv'
  <1> SUFFICES ASSUME LiveInv, [NextF]_vars PROVE LiveInv'
    OBVIOUS
  <1>1 CASE Next
    BY <1>1, LiveStep
  <1>2 CASE Refill
    BY <1>2 DEF Refill, LiveInv, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable,
           WaitEnoughOrClosed, WholeRead, RecordsAligned, Uniform, NoWriteAfterEof,
           EofOnlyWhenClosedAndEmpty, Buffered, InFlight, BufLock, HoldLeft, BufNonNeg,
           CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv,
           WriterInv, ClosedNoPark, Want
  <1>3 CASE UNCHANGED vars
    BY <1>3, LiveStep
  <1> QED
    BY <1>1, <1>2, <1>3 DEF NextF

\* a step of a writer or a closer lowers FIP, and Buffered rises by no more
LEMMA WCDrop ==
  ASSUME LiveInv, (\E i \in Writers : WStep(i)) \/ (\E c \in Closers : CStep(c))
  PROVE FIP' < FIP /\ Buffered' - Buffered <= FIP - FIP'
  <1>0 Next
    BY DEF Next, WStep, CStep
  <1>1 SafeInv /\ SafeInv'
    BY <1>0, StepSafe DEF LiveInv
  <1>2 /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
       /\ WW' \in Nat /\ WS' \in Nat /\ CC' \in Nat /\ CS' \in Nat
    BY Fin, AtType DEF WW, WS, CC, CS
  <1>3 /\ Bytes - w \in Nat /\ Bytes - t \in Nat /\ Bytes - w' \in Nat /\ Bytes - t' \in Nat
       /\ Buffered \in Nat /\ Buffered' \in Nat
       /\ w \in Nat /\ w' \in Nat /\ t \in Nat /\ t' \in Nat /\ Bytes \in Nat
    BY <1>1, ConstAssump DEF SafeInv, TypeOK, BufNonNeg, Buffered, InFlight
  <1>4 FIP = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS
       /\ FIP' = 2 * (Bytes - w') + (Bytes - t') + 2 * WS' + WW' + 2 * CC' + CS'
    BY FParts
  <1> USE ConstAssump, LiveAssump
  <1>10 CASE \E i \in Writers : WStep(i)
    <2> PICK i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
      BY <1>10 DEF WStep
    <2>0 \A x \in Writers \ {i} : wpc'[x] = wpc[x]
      BY <1>1 DEF WriterWrite, WriterSigLock, WGo, SafeInv, TypeOK
    <2>a CC' = CC /\ CS' = CS /\ t' = t
      BY DEF WriterWrite, WriterSigLock, CC, CS
    <2>b WW' = WW - (IF wpc[i] = "write" THEN 1 ELSE 0) + (IF wpc'[i] = "write" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF WW
    <2>c WS' = WS - (IF wpc[i] = "siglock" THEN 1 ELSE 0) + (IF wpc'[i] = "siglock" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF WS
    <2>1 CASE WriterWrite(i)
      <3>3 CASE closed \/ w >= Bytes
        <4>1 WW' = WW - 1 /\ WS' = WS
          BY <3>3, <2>1, <2>b, <2>c, <1>1, <1>2 DEF WriterWrite, WGo, SafeInv, TypeOK
        <4>2 w' = w /\ Buffered' = Buffered
          BY <3>3, <2>1, <1>1 DEF WriterWrite, Buffered, InFlight, SafeInv, TypeOK
        <4> QED
          BY ONLY <4>1, <4>2, <2>a, <1>2, <1>3, <1>4
      <3>4 CASE ~(closed \/ w >= Bytes)
        <4> PICK c \in 1..Bytes : c <= Bytes - w /\ w' = w + c /\ avail' = avail + c
          BY <3>4, <2>1, <1>1 DEF WriterWrite, SafeInv, TypeOK
        <4>1 WW' = WW - 1 /\ WS' = WS + 1
          BY <3>4, <2>1, <2>b, <2>c, <1>1, <1>2 DEF WriterWrite, WGo, SafeInv, TypeOK
        <4>2 Buffered' = Buffered + c
          BY <2>1, <2>a, <1>1 DEF WriterWrite, Buffered, InFlight, SafeInv, TypeOK
        <4>3 c \in Nat /\ c >= 1 /\ w' = w + c
          OBVIOUS
        <4> QED
          BY ONLY <4>1, <4>2, <4>3, <2>a, <1>2, <1>3, <1>4
      <3> QED
        BY <3>3, <3>4
    <2>2 CASE WriterSigLock(i)
      <3>1 WS' = WS - 1 /\ WW' <= WW + 1
        BY <2>2, <2>b, <2>c, <1>1, <1>2 DEF WriterSigLock, WGo, WriterNext, SafeInv, TypeOK
      <3>2 w' = w /\ Buffered' = Buffered
        BY <2>2 DEF WriterSigLock, Buffered, InFlight
      <3> QED
        BY ONLY <3>1, <3>2, <2>a, <1>2, <1>3, <1>4
    <2> QED
      BY <2>1, <2>2
  <1>11 CASE \E c \in Closers : CStep(c)
    <2> PICK c \in Closers : CloserClose(c) \/ CloserSigLock(c)
      BY <1>11 DEF CStep
    <2>0 \A x \in Closers \ {c} : cpc'[x] = cpc[x]
      BY <1>1 DEF CloserClose, CloserSigLock, CGo, SafeInv, TypeOK
    <2>a WW' = WW /\ WS' = WS /\ w' = w /\ t' = t /\ Buffered' = Buffered
      BY DEF CloserClose, CloserSigLock, WW, WS, Buffered, InFlight
    <2>b CC' = CC - (IF cpc[c] = "close" THEN 1 ELSE 0) + (IF cpc'[c] = "close" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF CC
    <2>c CS' = CS - (IF cpc[c] = "siglock" THEN 1 ELSE 0) + (IF cpc'[c] = "siglock" THEN 1 ELSE 0)
      BY <2>0, Fin, AtExcept DEF CS
    <2>1 CASE CloserClose(c)
      <3>1 CC' = CC - 1 /\ CS' = CS + 1
        BY <2>1, <2>b, <2>c, <1>1, <1>2 DEF CloserClose, CGo, SafeInv, TypeOK
      <3> QED
        BY ONLY <3>1, <2>a, <1>2, <1>3, <1>4
    <2>2 CASE CloserSigLock(c)
      <3>1 CC' = CC /\ CS' = CS - 1
        BY <2>2, <2>b, <2>c, <1>1, <1>2 DEF CloserSigLock, CGo, SafeInv, TypeOK
      <3> QED
        BY ONLY <3>1, <2>a, <1>2, <1>3, <1>4
    <2> QED
      BY <2>1, <2>2
  <1> QED
    BY <1>10, <1>11

LEMMA WCStep ==
  ASSUME LiveInv, NEW r \in Threads, (\E i \in Writers : WStep(i)) \/ (\E c \in Closers : CStep(c))
  PROVE FMeas(r)' < FMeas(r)
  <1>1 LiveInv'
    BY LiveStepF DEF NextF, Next, WStep, CStep
  <1> QED
    BY <1>1, WCDrop, IPStep
=============================================================================
