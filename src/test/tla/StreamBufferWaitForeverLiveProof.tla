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
EXTENDS StreamBufferWaitForeverLive, StreamBufferWaitLiveProof, StreamBufferWaitForeverEnabled,
        NaturalsInduction, TLAPS

\* the parts of the measure in the notation of the counting lemmas
LEMMA FParts ==
  /\ FIP = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS + spurious
  /\ FIP' = 2 * (Bytes - w') + (Bytes - t') + 2 * WS' + WW' + 2 * CC' + CS' + spurious'
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
    <2>2 spurious \in Nat
      BY DEF LiveInv, SafeInv, TypeOK
    <2> QED
      BY <2>1, <2>2, FParts
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
    <2>2 Bytes - w' \in Nat /\ Bytes - t' \in Nat /\ Buffered' \in Nat /\ spurious' \in Nat
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
  <1>4 FIP = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS + spurious
       /\ FIP' = 2 * (Bytes - w') + (Bytes - t') + 2 * WS' + WW' + 2 * CC' + CS' + spurious'
    BY FParts
  <1>5 spurious \in Nat /\ spurious' = spurious
    BY <1>1 DEF WStep, CStep, WriterWrite, WriterSigLock, CloserClose, CloserSigLock, SafeInv,
           TypeOK
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
          BY ONLY <4>1, <4>2, <2>a, <1>2, <1>3, <1>4, <1>5
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
          BY ONLY <4>1, <4>2, <4>3, <2>a, <1>2, <1>3, <1>4, <1>5
      <3> QED
        BY <3>3, <3>4
    <2>2 CASE WriterSigLock(i)
      <3>1 WS' = WS - 1 /\ WW' <= WW + 1
        BY <2>2, <2>b, <2>c, <1>1, <1>2 DEF WriterSigLock, WGo, WriterNext, SafeInv, TypeOK
      <3>2 w' = w /\ Buffered' = Buffered
        BY <2>2 DEF WriterSigLock, Buffered, InFlight
      <3> QED
        BY ONLY <3>1, <3>2, <2>a, <1>2, <1>3, <1>4, <1>5
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
        BY ONLY <3>1, <2>a, <1>2, <1>3, <1>4, <1>5
    <2>2 CASE CloserSigLock(c)
      <3>1 CC' = CC /\ CS' = CS - 1
        BY <2>2, <2>b, <2>c, <1>1, <1>2 DEF CloserSigLock, CGo, SafeInv, TypeOK
      <3> QED
        BY ONLY <3>1, <2>a, <1>2, <1>3, <1>4, <1>5
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

LEMMA ThreadBasics ==
  ASSUME LiveInv, NEW q \in Threads, ThreadStep(q), ~ThreadFinish(q)
  PROVE /\ \A x \in Threads \ {q} : /\ rpc'[x] = rpc[x] /\ op'[x] = op[x]
                                     /\ hold'[x] = hold[x] /\ left'[x] = left[x]
        /\ avail' = avail /\ closed' = closed /\ w' = w /\ t' = t /\ wpc' = wpc /\ cpc' = cpc
        /\ (~ThreadCopy(q) => Buffered' = Buffered) /\ spurious' = spurious
  <1>0 SafeInv
    BY DEF LiveInv
  <1> USE <1>0, ConstAssump DEF SafeInv, TypeOK, BufLock, HoldLeft, WaitLockInv, Go, Return,
                                 EndCall, Want, Buffered, InFlight
  <1>1 CASE ThreadStart(q)
    BY <1>1 DEF ThreadStart, ThreadCopy
  <1>2 CASE ThreadReread(q)
    BY <1>2 DEF ThreadReread, ThreadCopy
  <1>3 CASE ThreadWaitLock(q)
    BY <1>3 DEF ThreadWaitLock, ThreadCopy
  <1>4 CASE ThreadInc(q)
    BY <1>4 DEF ThreadInc, ThreadCopy
  <1>5 CASE ThreadTest(q)
    BY <1>5 DEF ThreadTest, ThreadCopy
  <1>6 CASE ThreadWaitReturn(q)
    BY <1>6 DEF ThreadWaitReturn, ThreadCopy
  <1>7 CASE ThreadLock(q)
    <2>1 hold[q] = 0
      BY <1>7 DEF ThreadLock
    <2> QED
      BY <1>7, <2>1 DEF ThreadLock, ThreadCopy
  <1>8 CASE ThreadDecide(q)
    <2>1 hold[q] = 0
      BY <1>8 DEF ThreadDecide
    <2> QED
      BY <1>8, <2>1 DEF ThreadDecide, ThreadCopy
  <1>9 CASE ThreadCopy(q)
    BY <1>9 DEF ThreadCopy
  <1>10 CASE ThreadRet0(q)
    BY <1>10 DEF ThreadRet0, ThreadCopy
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10 DEF ThreadStep

\* the other threads keep their stage and their membership in FBadSet
LEMMA OthersSame ==
  ASSUME NEW q \in Threads,
         \A x \in Threads \ {q} : rpc'[x] = rpc[x] /\ op'[x] = op[x],
         avail' = avail, closed' = closed
  PROVE \A x \in Threads \ {q} : FVF'[x] = FVF[x] /\ (x \in FBadSet' <=> x \in FBadSet)
  BY DEF FVF, FV, FPass, Want, FBadSet, FOk

\* a thread step that keeps FIP and Buffered changes the measure by the change of q's parts
LEMMA ThreadCombine ==
  ASSUME LiveInv, LiveInv', NEW q \in Threads, NEW r \in Threads,
         FIP' = FIP, Buffered' = Buffered,
         \A x \in Threads \ {q} : FVF'[x] = FVF[x] /\ (x \in FBadSet' <=> x \in FBadSet),
         q # r => FRank(r)' = FRank(r)
  PROVE FMeas(r)' - FMeas(r)
          = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
            + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
  <1>1 FVF[q] = FV(q) /\ FVF'[q] = FV(q)' /\ FV(q) \in 0..9 /\ FV(q)' \in 0..9
    BY DEF FVF, FV
  <1>2 FSumV' = FSumV - FV(q) + FV(q)'
    <2>1 LSum(Threads, FVF') = LSum(Threads, FVF) - FVF[q] + FVF'[q]
      BY <1>1, Fin, LSumExcept
    <2> QED
      BY <2>1, <1>1, FParts
  <1>3 FBad' = FBad - (IF q \in FBadSet THEN 1 ELSE 0) + (IF q \in FBadSet' THEN 1 ELSE 0)
    <2>1 FBadSet \subseteq Threads /\ FBadSet' \subseteq Threads
         /\ FBadSet \ {q} = FBadSet' \ {q}
      BY DEF FBadSet
    <2> QED
      BY <2>1, Fin, SetExcept DEF FBad
  <1>4 FRank(r) \in 0..6 /\ FRank(r)' \in 0..6 /\ FRank(q) \in 0..6 /\ FRank(q)' \in 0..6
    BY DEF FRank
  <1>5 FW \in Nat /\ FIP \in Nat /\ Buffered \in Nat /\ FBad \in Nat /\ FSumV \in Nat
    BY FTypes
  <1>6 FIP' \in Nat /\ Buffered' \in Nat /\ FBad' \in Nat /\ FSumV' \in Nat
    BY FTypesP
  <1>7 FMeas(r) = FW * FIP + Buffered + 8 * FBad + 2 * FSumV + FRank(r)
       /\ FMeas(r)' = FW * FIP' + Buffered' + 8 * FBad' + 2 * FSumV' + FRank(r)'
    BY DEF FMeas
  <1>0 FW * FIP' = FW * FIP /\ Buffered' = Buffered
    OBVIOUS
  <1>8 CASE q = r
    BY ONLY <1>0, <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8
  <1>9 CASE q # r
    <2>1 FRank(r)' = FRank(r)
      BY <1>9
    <2> QED
      BY ONLY <1>0, <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>9, <2>1
  <1> QED
    BY <1>8, <1>9

\* a thread step other than a commit or a copy changes the measure by the change of q's parts
LEMMA StepDelta ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadStep(q), ~ThreadFinish(q),
         ~ThreadCopy(q)
  PROVE FMeas(r)' - FMeas(r)
          = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
            + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
  <1>1 LiveInv'
    BY LiveStepF DEF NextF, Next
  <1>2 /\ \A x \in Threads \ {q} : /\ rpc'[x] = rpc[x] /\ op'[x] = op[x]
                                    /\ hold'[x] = hold[x] /\ left'[x] = left[x]
       /\ avail' = avail /\ closed' = closed /\ w' = w /\ t' = t /\ wpc' = wpc /\ cpc' = cpc
       /\ Buffered' = Buffered
    BY ThreadBasics
  <1>3 \A x \in Threads \ {q} : FVF'[x] = FVF[x] /\ (x \in FBadSet' <=> x \in FBadSet)
    BY <1>2, OthersSame
  <1>4 FIP' = FIP
    BY <1>2, ThreadBasics DEF FIP
  <1>5 q # r => FRank(r)' = FRank(r)
    BY <1>2 DEF FRank
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, ThreadCombine

\* a step of another thread in start, reread or ret0 that takes no lock moves no lock holder
LEMMA EqFrame ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, q # r, ThreadStep(q), ~ThreadFinish(q),
         rpc[q] \in {"start", "reread", "ret0"}, bl' = bl, wl' = wl, parked' = parked
  PROVE FFrame(r)
  <1>1 /\ \A x \in Threads \ {q} : /\ rpc'[x] = rpc[x] /\ op'[x] = op[x]
                                    /\ hold'[x] = hold[x] /\ left'[x] = left[x]
       /\ wpc' = wpc /\ cpc' = cpc
    BY ThreadBasics
  <1>2 bl # q /\ wl # q
    BY DEF LiveInv, SafeInv, BufLock, WaitLockInv
  <1> QED
    BY <1>1, <1>2 DEF FFrame

LEMMA FMeasBoth ==
  ASSUME LiveInv, LiveInv', NEW r \in Threads
  PROVE FMeas(r) \in Nat /\ FMeas(r)' \in Nat
  <1>1 FW \in Nat /\ FIP \in Nat /\ Buffered \in Nat /\ FBad \in Nat /\ FSumV \in Nat
    BY FTypes
  <1>2 FIP' \in Nat /\ Buffered' \in Nat /\ FBad' \in Nat /\ FSumV' \in Nat
    BY FTypesP
  <1>3 FRank(r) \in 0..6 /\ FRank(r)' \in 0..6
    BY DEF FRank
  <1> QED
    BY <1>1, <1>2, <1>3 DEF FMeas

\* the facts the action lemmas share
LEMMA ActPre ==
  ASSUME LiveInv, NEW q \in Threads, ThreadStep(q), ~ThreadFinish(q)
  PROVE /\ LiveInv'
        /\ op \in [Threads -> Ops] /\ rpc \in [Threads -> States]
        /\ \A x \in Threads : K[x] \in Nat /\ M[x] \in Nat /\ Want(x) \in Nat
        /\ avail \in Nat /\ avail' = avail /\ closed' = closed
  <1>1 LiveInv'
    BY LiveStepF DEF NextF, Next
  <1>2 avail' = avail /\ closed' = closed
    BY ThreadBasics
  <1> QED
    BY <1>1, <1>2, ConstAssump DEF LiveInv, SafeInv, TypeOK, Want

\* the stage, the rank and the stale lock of q in the states the actions reach
LEMMA FVAt ==
  ASSUME NEW q \in Threads
  PROVE /\ rpc[q] \in {"start", "reread", "ret0"} => FV(q) = 4
        /\ rpc[q] \in {"lockwait", "woken"} => FV(q) = IF FPass(q) THEN 9 ELSE 3
        /\ rpc[q] = "inc" => FV(q) = IF FPass(q) THEN 8 ELSE 2
        /\ rpc[q] = "test" => FV(q) = IF FPass(q) THEN 7 ELSE 1
        /\ rpc[q] = "wret" => FV(q) = 5
        /\ rpc[q] = "lock" => FV(q) = 3
        /\ rpc[q] = "decide" => FV(q) = 2
        /\ rpc[q] \in {"copy", "finish"} => FV(q) = 1
        /\ rpc[q] \in {"parked", "done"} => FV(q) = 0
        /\ rpc[q] = "start" => FRank(q) = 6
        /\ rpc[q] \in {"reread", "lockwait", "woken"} => FRank(q) = 5
        /\ rpc[q] \in {"ret0", "inc", "lock"} => FRank(q) = 4
        /\ rpc[q] \in {"test", "decide"} => FRank(q) = 3
        /\ rpc[q] \in {"wret", "copy"} => FRank(q) = 2
        /\ rpc[q] \in {"parked", "finish"} => FRank(q) = 1
        /\ rpc[q] = "done" => FRank(q) = 0
        /\ rpc[q] \notin {"lock", "decide"} => q \notin FBadSet
        /\ rpc[q] \in {"lock", "decide"} => (q \in FBadSet <=> ~FOk(q))
  BY DEF FV, FRank, FBadSet

LEMMA FVAtP ==
  ASSUME NEW q \in Threads
  PROVE /\ rpc'[q] \in {"start", "reread", "ret0"} => FV(q)' = 4
        /\ rpc'[q] \in {"lockwait", "woken"} => FV(q)' = IF FPass(q)' THEN 9 ELSE 3
        /\ rpc'[q] = "inc" => FV(q)' = IF FPass(q)' THEN 8 ELSE 2
        /\ rpc'[q] = "test" => FV(q)' = IF FPass(q)' THEN 7 ELSE 1
        /\ rpc'[q] = "wret" => FV(q)' = 5
        /\ rpc'[q] = "lock" => FV(q)' = 3
        /\ rpc'[q] = "decide" => FV(q)' = 2
        /\ rpc'[q] \in {"copy", "finish"} => FV(q)' = 1
        /\ rpc'[q] \in {"parked", "done"} => FV(q)' = 0
        /\ rpc'[q] = "start" => FRank(q)' = 6
        /\ rpc'[q] \in {"reread", "lockwait", "woken"} => FRank(q)' = 5
        /\ rpc'[q] \in {"ret0", "inc", "lock"} => FRank(q)' = 4
        /\ rpc'[q] \in {"test", "decide"} => FRank(q)' = 3
        /\ rpc'[q] \in {"wret", "copy"} => FRank(q)' = 2
        /\ rpc'[q] \in {"parked", "finish"} => FRank(q)' = 1
        /\ rpc'[q] = "done" => FRank(q)' = 0
        /\ rpc'[q] \notin {"lock", "decide"} => q \notin FBadSet'
        /\ rpc'[q] \in {"lock", "decide"} => (q \in FBadSet' <=> ~FOk(q)')
  BY DEF FV, FRank, FBadSet

\* how the measure goes: d is the change of StepDelta
LEMMA Decide ==
  ASSUME LiveInv, LiveInv', NEW r \in Threads, NEW d \in Int, FMeas(r)' - FMeas(r) = d
  PROVE (d < 0 => FMeas(r)' < FMeas(r)) /\ (d = 0 => FMeas(r)' = FMeas(r))
  BY FMeasBoth

LEMMA ActStart ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadStart(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadStart, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "start" /\ FV(q) = 4 /\ FRank(q) = 6 /\ q \notin FBadSet
    BY FVAt DEF ThreadStart
  <1>4 CASE avail >= Want(q) /\ op[q] = "wait"
    <2>1 rpc'[q] \in {"start", "done"} /\ bl' = bl /\ wl' = wl /\ parked' = parked
      BY <1>4 DEF ThreadStart, Return, EndCall, Go, LiveInv, SafeInv, TypeOK
    <2>2 q # r
      BY <2>1, <1>0, <1>3 DEF Ret
    <2>3 q \notin FBadSet' /\ (FV(q)' = 4 \/ FV(q)' = 0) /\ (FV(q)' = 4 => rpc'[q] = rpc[q])
      BY <2>1, <1>3, FVAtP
    <2>4 CASE FV(q)' = 4
      <3>1 FMeas(r)' = FMeas(r)
        BY <1>1, <1>2, <1>3, <2>2, <2>3, <2>4, Decide
      <3>2 FFrame(r)
        BY <1>0, <1>3, <2>1, <2>2, EqFrame
      <3> QED
        BY <3>1, <3>2 DEF FKeeps
    <2>5 CASE FV(q)' = 0
      BY <1>1, <1>2, <1>3, <2>2, <2>3, <2>5, Decide DEF FKeeps
    <2> QED
      BY <2>3, <2>4, <2>5
  <1>5 CASE ~(avail >= Want(q) /\ op[q] = "wait") /\ avail >= Want(q)
    <2>1 rpc'[q] = "lock" /\ op'[q] = op[q] /\ op[q] = "read"
      BY <1>5, <1>1 DEF ThreadStart, Go, Ops, LiveInv, SafeInv, TypeOK
    <2>2 FOk(q)'
      BY <2>1, <1>5, <1>1 DEF FOk, Want
    <2>3 q \notin FBadSet' /\ FV(q)' = 3 /\ FRank(q)' = 4
      BY <2>1, <2>2, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>3, Decide DEF FKeeps
  <1>6 CASE ~(avail >= Want(q)) /\ closed
    <2>1 rpc'[q] = "reread" /\ bl' = bl /\ wl' = wl /\ parked' = parked
      BY <1>6 DEF ThreadStart, Go, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet' /\ FV(q)' = 4 /\ FRank(q)' = 5
      BY <2>1, FVAtP
    <2>3 CASE q = r
      BY <1>1, <1>2, <1>3, <2>2, <2>3, Decide DEF FKeeps
    <2>4 CASE q # r
      <3>1 FMeas(r)' = FMeas(r)
        BY <1>1, <1>2, <1>3, <2>2, <2>4, Decide
      <3>2 FFrame(r)
        BY <1>0, <1>3, <2>1, <2>4, EqFrame
      <3> QED
        BY <3>1, <3>2 DEF FKeeps
    <2> QED
      BY <2>3, <2>4
  <1>7 CASE ~(avail >= Want(q)) /\ ~closed
    <2>1 rpc'[q] = "lockwait" /\ op'[q] = op[q]
      BY <1>7 DEF ThreadStart, Go, LiveInv, SafeInv, TypeOK
    <2>2 ~FPass(q)'
      BY <2>1, <1>7, <1>1 DEF FPass, Want
    <2>3 q \notin FBadSet' /\ FV(q)' = 3 /\ FRank(q)' = 5
      BY <2>1, <2>2, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>3, Decide DEF FKeeps
  <1> QED
    BY <1>4, <1>5, <1>6, <1>7

LEMMA ActReread ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadReread(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadReread, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "reread" /\ FV(q) = 4 /\ FRank(q) = 5 /\ q \notin FBadSet /\ closed
    BY FVAt DEF ThreadReread, LiveInv, SafeInv, RereadClosed
  <1>4 CASE op[q] = "wait"
    <2>1 rpc'[q] \in {"start", "done"} /\ bl' = bl /\ wl' = wl /\ parked' = parked
      BY <1>4 DEF ThreadReread, Return, EndCall, Go, LiveInv, SafeInv, TypeOK
    <2>2 q # r
      BY <2>1, <1>0, <1>3 DEF Ret
    <2>3 q \notin FBadSet' /\ (FV(q)' = 4 \/ FV(q)' = 0) /\ (FV(q)' = 4 => rpc'[q] = "start")
      BY <2>1, FVAtP
    <2>4 CASE FV(q)' = 4
      <3>1 FMeas(r)' = FMeas(r)
        BY <1>1, <1>2, <1>3, <2>2, <2>3, <2>4, Decide
      <3>2 FFrame(r)
        BY <1>0, <1>3, <2>1, <2>2, EqFrame
      <3> QED
        BY <3>1, <3>2 DEF FKeeps
    <2>5 CASE FV(q)' = 0
      BY <1>1, <1>2, <1>3, <2>2, <2>3, <2>5, Decide DEF FKeeps
    <2> QED
      BY <2>3, <2>4, <2>5
  <1>5 CASE op[q] # "wait" /\ avail >= 1
    <2>1 rpc'[q] = "lock"
      BY <1>5 DEF ThreadReread, Go, LiveInv, SafeInv, TypeOK
    <2>2 FOk(q)'
      BY <1>5, <1>3, <1>1 DEF FOk
    <2>3 q \notin FBadSet' /\ FV(q)' = 3 /\ FRank(q)' = 4
      BY <2>1, <2>2, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>3, Decide DEF FKeeps
  <1>6 CASE op[q] # "wait" /\ ~(avail >= 1)
    <2>1 rpc'[q] = "ret0" /\ bl' = bl /\ wl' = wl /\ parked' = parked
      BY <1>6 DEF ThreadReread, Go, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet' /\ FV(q)' = 4 /\ FRank(q)' = 4
      BY <2>1, FVAtP
    <2>3 CASE q = r
      BY <1>1, <1>2, <1>3, <2>2, <2>3, Decide DEF FKeeps
    <2>4 CASE q # r
      <3>1 FMeas(r)' = FMeas(r)
        BY <1>1, <1>2, <1>3, <2>2, <2>4, Decide
      <3>2 FFrame(r)
        BY <1>0, <1>3, <2>1, <2>4, EqFrame
      <3> QED
        BY <3>1, <3>2 DEF FKeeps
    <2> QED
      BY <2>3, <2>4
  <1> QED
    BY <1>4, <1>5, <1>6

LEMMA ActWaitLock ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadWaitLock(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadWaitLock, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 (FPass(q)' <=> FPass(q)) /\ q \notin FBadSet /\ FRank(q) = 5
    BY <1>1, FVAt DEF ThreadWaitLock, FPass, Want
  <1>4 CASE rpc[q] = "lockwait"
    <2>1 rpc'[q] = "inc"
      BY <1>4 DEF ThreadWaitLock, Go, LiveInv, SafeInv, TypeOK
    <2>2 FV(q) = (IF FPass(q) THEN 9 ELSE 3) /\ FV(q)' = (IF FPass(q) THEN 8 ELSE 2)
         /\ q \notin FBadSet' /\ FRank(q)' = 4
      BY <1>3, <1>4, <2>1, FVAt, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>2, Decide DEF FKeeps
  <1>5 CASE rpc[q] = "woken"
    <2>1 rpc'[q] = "test"
      BY <1>5 DEF ThreadWaitLock, Go, LiveInv, SafeInv, TypeOK
    <2>2 FV(q) = (IF FPass(q) THEN 9 ELSE 3) /\ FV(q)' = (IF FPass(q) THEN 7 ELSE 1)
         /\ q \notin FBadSet' /\ FRank(q)' = 3
      BY <1>3, <1>5, <2>1, FVAt, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>2, Decide DEF FKeeps
  <1> QED
    BY <1>4, <1>5 DEF ThreadWaitLock

LEMMA ActInc ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadInc(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadInc, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 (FPass(q)' <=> FPass(q)) /\ rpc[q] = "inc" /\ rpc'[q] = "test"
    BY <1>1 DEF ThreadInc, Go, FPass, Want, LiveInv, SafeInv, TypeOK
  <1>4 FV(q) = (IF FPass(q) THEN 8 ELSE 2) /\ FV(q)' = (IF FPass(q) THEN 7 ELSE 1)
       /\ q \notin FBadSet /\ q \notin FBadSet' /\ FRank(q) = 4 /\ FRank(q)' = 3
    BY <1>3, FVAt, FVAtP
  <1> QED
    BY <1>1, <1>2, <1>4, Decide DEF FKeeps

LEMMA ActTest ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadTest(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadTest, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "test" /\ q \notin FBadSet /\ FRank(q) = 3
       /\ FV(q) = (IF FPass(q) THEN 7 ELSE 1)
    BY FVAt DEF ThreadTest
  <1>4 CASE FPass(q) /\ op[q] = "wait" /\ CheckedReturn /\ avail >= Want(q)
    <2>1 rpc'[q] \in {"start", "done"}
      BY <1>4 DEF ThreadTest, Return, EndCall, Go, FPass, LiveInv, SafeInv, TypeOK
    <2>2 q # r
      BY <2>1, <1>0, <1>3 DEF Ret
    <2>3 q \notin FBadSet' /\ (FV(q)' = 4 \/ FV(q)' = 0)
      BY <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <1>4, <2>2, <2>3, Decide DEF FKeeps
  <1>5 CASE FPass(q) /\ op[q] = "wait" /\ ~(CheckedReturn /\ avail >= Want(q))
    <2>1 rpc'[q] = "wret"
      BY <1>5 DEF ThreadTest, Go, FPass, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet' /\ FV(q)' = 5 /\ FRank(q)' = 2
      BY <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <1>5, <2>2, Decide DEF FKeeps
  <1>6 CASE FPass(q) /\ op[q] # "wait" /\ avail >= 1
    <2>1 rpc'[q] = "lock" /\ op[q] = "read"
      BY <1>6, <1>1 DEF ThreadTest, Go, FPass, Ops, LiveInv, SafeInv, TypeOK
    <2>2 FOk(q)'
      BY <1>6, <2>1, <1>1 DEF FOk, FPass, Want
    <2>3 q \notin FBadSet' /\ FV(q)' = 3 /\ FRank(q)' = 4
      BY <2>1, <2>2, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <1>6, <2>3, Decide DEF FKeeps
  <1>7 CASE FPass(q) /\ op[q] # "wait" /\ ~(avail >= 1)
    <2>1 rpc'[q] = "ret0"
      BY <1>7 DEF ThreadTest, Go, FPass, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet' /\ FV(q)' = 4 /\ FRank(q)' = 4
      BY <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <1>7, <2>2, Decide DEF FKeeps
  <1>8 CASE ~FPass(q)
    <2>1 rpc'[q] = "parked"
      BY <1>8 DEF ThreadTest, Go, FPass, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet' /\ FV(q)' = 0 /\ FRank(q)' = 1
      BY <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <1>8, <2>2, Decide DEF FKeeps
  <1> QED
    BY <1>4, <1>5, <1>6, <1>7, <1>8

LEMMA ActWaitReturn ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadWaitReturn(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadWaitReturn, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "wret" /\ q \notin FBadSet /\ FV(q) = 5
    BY FVAt DEF ThreadWaitReturn
  <1>4 rpc'[q] \in {"start", "done"}
    BY DEF ThreadWaitReturn, Return, EndCall, Go, LiveInv, SafeInv, TypeOK
  <1>5 q # r
    BY <1>4, <1>0, <1>3 DEF Ret
  <1>6 q \notin FBadSet' /\ (FV(q)' = 4 \/ FV(q)' = 0)
    BY <1>4, FVAtP
  <1> QED
    BY <1>1, <1>2, <1>3, <1>5, <1>6, Decide DEF FKeeps

LEMMA ActLock ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadLock(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadLock, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "lock" /\ rpc'[q] = "decide" /\ (FOk(q)' <=> FOk(q))
    BY <1>1 DEF ThreadLock, Go, FOk, LiveInv, SafeInv, TypeOK
  <1>4 FV(q) = 3 /\ FV(q)' = 2 /\ FRank(q) = 4 /\ FRank(q)' = 3
       /\ (q \in FBadSet' <=> q \in FBadSet)
    BY <1>3, FVAt, FVAtP
  <1> QED
    BY <1>1, <1>2, <1>4, Decide DEF FKeeps

LEMMA ActDecide ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadDecide(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadDecide, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "decide" /\ FV(q) = 2 /\ FRank(q) = 3 /\ (q \in FBadSet <=> ~FOk(q))
    BY FVAt DEF ThreadDecide
  <1>4 CASE FOk(q)
    <2>1 rpc'[q] = "copy"
      BY <1>4 DEF ThreadDecide, Go, FOk, LiveInv, SafeInv, TypeOK
    <2>2 q \notin FBadSet /\ q \notin FBadSet' /\ FV(q)' = 1 /\ FRank(q)' = 2
      BY <1>3, <1>4, <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>2, Decide DEF FKeeps
  <1>5 CASE ~FOk(q)
    <2>1 rpc'[q] = "start"
      BY <1>5 DEF ThreadDecide, Go, FOk, LiveInv, SafeInv, TypeOK
    <2>2 q \in FBadSet /\ q \notin FBadSet' /\ FV(q)' = 4 /\ FRank(q)' = 6
      BY <1>3, <1>5, <2>1, FVAtP
    <2> QED
      BY <1>1, <1>2, <1>3, <2>2, Decide DEF FKeeps
  <1> QED
    BY <1>4, <1>5

LEMMA ActRet0 ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadRet0(q), ~Ret(r)
  PROVE FKeeps(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q) /\ ~ThreadCopy(q)
    BY DEF ThreadStep, ThreadRet0, ThreadFinish, ThreadCopy
  <1>1 /\ LiveInv' /\ op \in [Threads -> Ops]
       /\ \A x \in Threads : Want(x) \in Nat /\ K[x] \in Nat
       /\ avail \in Nat /\ avail' = avail /\ closed' = closed
    BY <1>0, ActPre
  <1>2 FMeas(r)' - FMeas(r)
         = 8 * ((IF q \in FBadSet' THEN 1 ELSE 0) - (IF q \in FBadSet THEN 1 ELSE 0))
           + 2 * (FV(q)' - FV(q)) + (IF q = r THEN FRank(q)' - FRank(q) ELSE 0)
    BY <1>0, StepDelta
  <1>3 rpc[q] = "ret0" /\ FV(q) = 4 /\ q \notin FBadSet
    BY FVAt DEF ThreadRet0
  <1>4 rpc'[q] \in {"start", "done"} /\ bl' = bl /\ wl' = wl /\ parked' = parked
    BY DEF ThreadRet0, EndCall, Go, LiveInv, SafeInv, TypeOK
  <1>5 q # r
    BY <1>4, <1>0, <1>3 DEF Ret
  <1>6 q \notin FBadSet' /\ (FV(q)' = 4 \/ FV(q)' = 0)
    BY <1>4, FVAtP
  <1>7 CASE FV(q)' = 4
    <2>1 FMeas(r)' = FMeas(r)
      BY <1>1, <1>2, <1>3, <1>5, <1>6, <1>7, Decide
    <2>2 FFrame(r)
      BY <1>0, <1>3, <1>4, <1>5, EqFrame
    <2> QED
      BY <2>1, <2>2 DEF FKeeps
  <1>8 CASE FV(q)' = 0
    BY <1>1, <1>2, <1>3, <1>5, <1>6, <1>8, Decide DEF FKeeps
  <1> QED
    BY <1>6, <1>7, <1>8

\* a copy turn takes k >= 1 bytes: Buffered drops by k, q's parts stay
LEMMA ActCopy ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadCopy(q)
  PROVE FMeas(r)' < FMeas(r)
  <1>0 ThreadStep(q) /\ ~ThreadFinish(q)
    BY DEF ThreadStep, ThreadCopy, ThreadFinish
  <1>1 LiveInv'
    BY <1>0, LiveStepF DEF NextF, Next
  <1>2 /\ \A x \in Threads \ {q} : /\ rpc'[x] = rpc[x] /\ op'[x] = op[x]
                                    /\ hold'[x] = hold[x] /\ left'[x] = left[x]
       /\ avail' = avail /\ closed' = closed /\ w' = w /\ t' = t /\ wpc' = wpc /\ cpc' = cpc
    BY <1>0, ThreadBasics
  <1>3 \A x \in Threads \ {q} : FVF'[x] = FVF[x] /\ (x \in FBadSet' <=> x \in FBadSet)
    BY <1>2, OthersSame
  <1>4 FIP' = FIP
    BY <1>0, <1>2, ThreadBasics DEF FIP
  <1>5 rpc[q] = "copy" /\ bl = q /\ left[q] >= 1 /\ Buffered >= left[q] /\ hold[q] \in Nat
       /\ left[q] \in Nat /\ w \in Nat /\ t \in Nat /\ Buffered \in Nat
    BY DEF ThreadCopy, LiveInv, SafeInv, TypeOK, BufLock, HoldLeft, CopyHasBytes, BufNonNeg,
           Buffered, InFlight
  <1>6 PICK k \in 0..left[q] : /\ k >= 1 /\ k <= Buffered
                                /\ hold' = [hold EXCEPT ![q] = @ + k]
                                /\ left' = [left EXCEPT ![q] = @ - k]
                                /\ Go(q, IF left[q] = k THEN "finish" ELSE "copy")
    BY <1>5 DEF ThreadCopy
  <1>7 Buffered' = Buffered - k /\ k \in Nat /\ k >= 1
    <2>1 bl' = bl /\ hold'[q] = hold[q] + k
      BY <1>5, <1>6 DEF ThreadCopy, LiveInv, SafeInv, TypeOK
    <2> QED
      BY <1>2, <1>5, <1>6, <2>1, ConstAssump DEF Buffered, InFlight
  <1>8 rpc'[q] \in {"copy", "finish"}
    BY <1>6 DEF Go, LiveInv, SafeInv, TypeOK
  <1>9 FVF[q] = 1 /\ FVF'[q] = 1 /\ q \notin FBadSet /\ q \notin FBadSet'
    BY <1>5, <1>8 DEF FVF, FV, FBadSet
  <1>10 FSumV' = FSumV
    <2>1 LSum(Threads, FVF') = LSum(Threads, FVF) - FVF[q] + FVF'[q]
      BY <1>3, <1>9, Fin, LSumExcept
    <2> QED
      BY <2>1, <1>9, FParts, Fin, LSumType
  <1>11 FBad' = FBad
    <2>1 FBadSet' = FBadSet
      BY <1>3, <1>9 DEF FBadSet
    <2> QED
      BY <2>1 DEF FBad
  <1>12 FRank(r)' <= FRank(r) /\ FRank(r) \in 0..6 /\ FRank(r)' \in 0..6
    <2>1 CASE q = r
      BY <2>1, <1>5, <1>8 DEF FRank
    <2>2 CASE q # r
      BY <2>2, <1>2 DEF FRank
    <2> QED
      BY <2>1, <2>2
  <1>13 FW \in Nat /\ FIP \in Nat /\ FBad \in Nat /\ FSumV \in Nat
    BY FTypes
  <1>14 FMeas(r) = FW * FIP + Buffered + 8 * FBad + 2 * FSumV + FRank(r)
        /\ FMeas(r)' = FW * FIP' + Buffered' + 8 * FBad' + 2 * FSumV' + FRank(r)'
    BY DEF FMeas
  <1>15 FW * FIP' = FW * FIP
    BY <1>4
  <1> QED
    BY ONLY <1>5, <1>7, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15

\* a commit lowers FIP by the bytes held and keeps Buffered
LEMMA ActFinish ==
  ASSUME LiveInv, NEW q \in Threads, NEW r \in Threads, ThreadFinish(q)
  PROVE FMeas(r)' < FMeas(r)
  <1>1 LiveInv'
    BY LiveStepF DEF NextF, Next, ThreadStep
  <1>2 rpc[q] = "finish" /\ bl = q /\ hold[q] >= 1 /\ hold[q] \in Nat /\ w \in Nat /\ t \in Nat
       /\ Bytes \in Nat
    BY ConstAssump DEF ThreadFinish, LiveInv, SafeInv, TypeOK, BufLock, HoldLeft
  <1>3 /\ t' = t + hold[q] /\ w' = w /\ wpc' = wpc /\ cpc' = cpc /\ bl' = None
       /\ spurious' = spurious
    BY DEF ThreadFinish
  <1>4 FIP' = FIP - hold[q]
    <2>1 /\ WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
      BY <1>3 DEF WW, WS, CC, CS
    <2>2 /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
         /\ Bytes - w \in Nat /\ Bytes - t \in Nat
      BY PartsType DEF LiveInv
    <2>3 spurious \in Nat
      BY DEF LiveInv, SafeInv, TypeOK
    <2> QED
      BY ONLY <2>1, <2>2, <2>3, <1>2, <1>3, FParts
  <1>5 Buffered' = Buffered
    BY <1>2, <1>3, ConstAssump DEF Buffered, InFlight
  <1>6 FIP' < FIP /\ Buffered' - Buffered <= FIP - FIP'
    BY <1>2, <1>4, <1>5, FTypes
  <1> QED
    BY <1>1, <1>6, IPStep

\* Refill changes the budget only
LEMMA ActRefill ==
  ASSUME LiveInv, NEW r \in Threads, Refill
  PROVE FMeas(r)' = FMeas(r) /\ FFrame(r)
  <1>1 \A x \in Threads : FV(x)' = FV(x) /\ (x \in FBadSet' <=> x \in FBadSet)
    BY DEF Refill, FV, FPass, Want, FBadSet, FOk
  <1>2 FVF' = FVF /\ FBadSet' = FBadSet
    BY <1>1 DEF FVF, FBadSet
  <1> QED
    BY <1>2 DEF Refill, FMeas, FIP, Buffered, InFlight, FBad, FSumV, FLay, FRank, FFrame

\* a spurious wake-up uses up one of the budget, which pays for the waking
LEMMA ActSpurious ==
  ASSUME LiveInv, NEW r \in Threads, NEW q \in Threads, SpuriousWake(q)
  PROVE FMeas(r)' < FMeas(r)
  <1>1 LiveInv'
    BY LiveStepF DEF NextF, Next
  <1>2 /\ w' = w /\ t' = t /\ wpc' = wpc /\ cpc' = cpc /\ Buffered' = Buffered
       /\ spurious \in Nat /\ spurious > 0 /\ spurious' = spurious - 1
       /\ w \in Nat /\ t \in Nat /\ Bytes \in Nat
    BY ConstAssump DEF SpuriousWake, LiveInv, SafeInv, TypeOK, Buffered, InFlight
  <1>3 /\ WW' = WW /\ WS' = WS /\ CC' = CC /\ CS' = CS
    BY <1>2 DEF WW, WS, CC, CS
  <1>4 /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
       /\ Bytes - w \in Nat /\ Bytes - t \in Nat
    BY PartsType DEF LiveInv
  <1>5 FIP' = FIP - 1
    <2>1 /\ FIP = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS + spurious
         /\ FIP' = 2 * (Bytes - w') + (Bytes - t') + 2 * WS' + WW' + 2 * CC' + CS' + spurious'
      BY FParts
    <2>2 FIP' = 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS + (spurious - 1)
      BY ONLY <2>1, <1>2, <1>3
    <2> DEFINE A == 2 * (Bytes - w) + (Bytes - t) + 2 * WS + WW + 2 * CC + CS
    <2>3 A \in Nat
      BY ONLY <1>4 DEF A
    <2>4 FIP = A + spurious /\ FIP' = A + (spurious - 1)
      BY ONLY <2>1, <2>2 DEF A
    <2> HIDE DEF A
    <2> QED
      BY ONLY <2>3, <2>4, <1>2
  <1>6 FIP' < FIP /\ Buffered' - Buffered <= FIP - FIP'
    BY <1>2, <1>5, FTypes
  <1> QED
    BY <1>1, <1>6, IPStep

\* every step but a return of r keeps the measure or lowers it (FKeeps)
LEMMA StepKeeps ==
  ASSUME LiveInv, NEW r \in Threads, NextF, ~Ret(r)
  PROVE FKeeps(r)
  <1>1 CASE (\E i \in Writers : WStep(i)) \/ (\E c \in Closers : CStep(c))
    BY <1>1, WCStep DEF FKeeps
  <1>2 CASE Refill
    BY <1>2, ActRefill DEF FKeeps
  <1>3 CASE \E q \in Threads : ThreadStep(q)
    <2> PICK q \in Threads : ThreadStep(q)
      BY <1>3
    <2>1 CASE ThreadStart(q)
      BY <2>1, ActStart
    <2>2 CASE ThreadReread(q)
      BY <2>2, ActReread
    <2>3 CASE ThreadWaitLock(q)
      BY <2>3, ActWaitLock
    <2>4 CASE ThreadInc(q)
      BY <2>4, ActInc
    <2>5 CASE ThreadTest(q)
      BY <2>5, ActTest
    <2>6 CASE ThreadWaitReturn(q)
      BY <2>6, ActWaitReturn
    <2>7 CASE ThreadLock(q)
      BY <2>7, ActLock
    <2>8 CASE ThreadDecide(q)
      BY <2>8, ActDecide
    <2>9 CASE ThreadCopy(q)
      BY <2>9, ActCopy DEF FKeeps
    <2>10 CASE ThreadFinish(q)
      BY <2>10, ActFinish DEF FKeeps
    <2>11 CASE ThreadRet0(q)
      BY <2>11, ActRet0
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11 DEF ThreadStep
  <1>4 CASE \E q \in Threads : SpuriousWake(q)
    BY <1>4, ActSpurious DEF FKeeps
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4 DEF NextF, Next, WStep, CStep

\* a step of r that is no return moves r: its stage, or its copy under bufferLock
LEMMA OwnMoves ==
  ASSUME LiveInv, NEW r \in Threads, ThreadStep(r), ~Ret(r)
  PROVE rpc'[r] # rpc[r] \/ (hold'[r] # hold[r] /\ bl = r)
  <1> USE DEF LiveInv, SafeInv, TypeOK, Go, Ret
  <1>1 CASE ThreadStart(r)
    BY <1>1 DEF ThreadStart, Return, EndCall, ThreadStep
  <1>2 CASE ThreadReread(r)
    BY <1>2 DEF ThreadReread, Return, EndCall, ThreadStep
  <1>3 CASE ThreadWaitLock(r)
    BY <1>3 DEF ThreadWaitLock
  <1>4 CASE ThreadInc(r)
    BY <1>4 DEF ThreadInc
  <1>5 CASE ThreadTest(r)
    BY <1>5 DEF ThreadTest, Return, EndCall, ThreadStep
  <1>6 CASE ThreadWaitReturn(r)
    BY <1>6 DEF ThreadWaitReturn, Return, EndCall, ThreadStep
  <1>7 CASE ThreadLock(r)
    BY <1>7 DEF ThreadLock
  <1>8 CASE ThreadDecide(r)
    BY <1>8 DEF ThreadDecide
  <1>9 CASE ThreadCopy(r)
    <2>1 bl = r /\ left[r] >= 1 /\ Buffered >= left[r] /\ hold[r] \in Nat
      BY <1>9 DEF ThreadCopy, BufLock, HoldLeft, CopyHasBytes
    <2> QED
      BY <1>9, <2>1 DEF ThreadCopy
  <1>10 CASE ThreadFinish(r)
    BY <1>10 DEF ThreadFinish, EndCall, ThreadStep
  <1>11 CASE ThreadRet0(r)
    BY <1>11 DEF ThreadRet0, EndCall, ThreadStep
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11 DEF ThreadStep

\* a step of a lock holder moves it
LEMMA HolderMoves ==
  ASSUME LiveInv, NEW q \in Threads, ThreadStep(q), bl = q \/ wl = q
  PROVE rpc'[q] # rpc[q] \/ hold'[q] # hold[q]
  <1> USE DEF LiveInv, SafeInv, TypeOK, Go
  <1>1 rpc[q] \in {"decide", "copy", "finish", "inc", "test", "wret"}
    BY DEF BufLock, WaitLockInv
  <1>2 CASE rpc[q] = "copy"
    <2>1 ThreadCopy(q) /\ left[q] >= 1 /\ Buffered >= left[q] /\ hold[q] \in Nat
      BY <1>2 DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
             ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0,
             HoldLeft, CopyHasBytes
    <2> QED
      BY <2>1 DEF ThreadCopy
  <1>3 CASE rpc[q] # "copy"
    BY <1>1, <1>3 DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc,
           ThreadTest, ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish,
           ThreadRet0, Return, EndCall
  <1> QED
    BY <1>2, <1>3

-----------------------------------------------------------------------------
(* The liveness argument for a thread r: a natural number that every step  *)
(* but a return of r keeps or lowers, and that a fair step lowers in every *)
(* state in which r has not stopped.                                       *)

\* r does not stop without a return
LEMMA NotDone ==
  ASSUME LiveInv, NEW r \in Threads, [NextF]_vars, ~Ret(r), rpc[r] # "done"
  PROVE rpc'[r] # "done"
  <1> USE DEF LiveInv, SafeInv, TypeOK
  <1> SUFFICES ASSUME rpc'[r] = "done" PROVE FALSE
    OBVIOUS
  <1>1 CASE (\E i \in Writers : WStep(i)) \/ (\E c \in Closers : CStep(c))
    BY <1>1 DEF WStep, CStep, WriterWrite, WriterSigLock, CloserClose, CloserSigLock, WakeAll,
           WGo, CGo
  <1>2 CASE Refill
    BY <1>2 DEF Refill
  <1>3 CASE UNCHANGED vars
    BY <1>3 DEF vars
  <1>4 CASE \E q \in Threads : ThreadStep(q)
    <2> PICK q \in Threads : ThreadStep(q)
      BY <1>4
    <2>1 CASE q # r
      BY <2>1 DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
             ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0,
             Go, Return, EndCall
    <2>2 CASE q = r
      <3>1 rpc[r] # "decide"
        BY <2>2 DEF ThreadStep, ThreadStart, ThreadReread, ThreadWaitLock, ThreadInc, ThreadTest,
               ThreadWaitReturn, ThreadLock, ThreadDecide, ThreadCopy, ThreadFinish, ThreadRet0,
               Go, Return, EndCall
      <3> QED
        BY <2>2, <3>1 DEF Ret
    <2> QED
      BY <2>1, <2>2
  <1>5 CASE \E q \in Threads : SpuriousWake(q)
    BY <1>5 DEF SpuriousWake, Go
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF NextF, Next, WStep, CStep

LEMMA StutterM ==
  ASSUME NEW r \in Threads, UNCHANGED vars
  PROVE FMeas(r)' = FMeas(r)
  BY DEF vars, FMeas, FIP, Buffered, InFlight, FBad, FBadSet, FOk, FSumV, FLay, FVF, FV, FPass,
         Want, FRank

\* a step that is no return of r: the measure goes down, or it stays and the frame holds
LEMMA KeepOrDrop ==
  ASSUME LiveInv, NEW r \in Threads, rpc[r] # "done", [NextF]_vars, [~Ret(r)]_vars
  PROVE /\ LiveInv' /\ rpc'[r] # "done"
        /\ \/ FMeas(r)' < FMeas(r)
           \/ /\ FMeas(r)' = FMeas(r) /\ rpc'[r] = rpc[r] /\ bl' = bl /\ wl' = wl
              /\ parked' = parked /\ wpc' = wpc /\ cpc' = cpc
  <1>1 LiveInv'
    BY LiveStepF
  <1>2 CASE UNCHANGED vars
    BY <1>1, <1>2, StutterM DEF vars
  <1>3 CASE NextF /\ ~Ret(r)
    <2>1 rpc'[r] # "done"
      BY <1>3, NotDone
    <2>2 FKeeps(r)
      BY <1>3, StepKeeps
    <2> QED
      BY <1>1, <2>1, <2>2 DEF FKeeps, FFrame
  <1> QED
    BY <1>2, <1>3

\* the steps of the fair actions lower the measure
LEMMA DropOwn ==
  ASSUME LiveInv, NEW r \in Threads, NextF, ~Ret(r), ThreadStep(r)
  PROVE FMeas(r)' < FMeas(r)
  <1>1 FKeeps(r)
    BY StepKeeps
  <1>2 rpc'[r] # rpc[r] \/ (hold'[r] # hold[r] /\ bl = r)
    BY OwnMoves
  <1> QED
    BY <1>1, <1>2 DEF FKeeps, FFrame

LEMMA DropHolder ==
  ASSUME LiveInv, NEW r \in Threads, NextF, ~Ret(r), BLHolder \/ WLHolder
  PROVE FMeas(r)' < FMeas(r)
  <1>1 FKeeps(r)
    BY StepKeeps
  <1> PICK q \in Threads : (bl = q \/ wl = q) /\ ThreadStep(q)
    BY DEF BLHolder, WLHolder
  <1>2 rpc'[q] # rpc[q] \/ hold'[q] # hold[q]
    BY HolderMoves
  <1> QED
    BY <1>1, <1>2 DEF FKeeps, FFrame

LEMMA DropWC ==
  ASSUME LiveInv, NEW r \in Threads, Signal \/ Closing
  PROVE FMeas(r)' < FMeas(r)
  BY WCStep DEF Signal, Closing, WStep, CStep

\* the cases of r's state, and the fair action that lowers the measure in each
FSig == (\E i \in Writers : wpc[i] = "siglock") \/ (\E c \in Closers : cpc[c] = "siglock")
C1(r) == RFree(r)
C2(r) == rpc[r] = "lock" /\ bl # None
C3(r) == rpc[r] \in {"lockwait", "woken", "parked"} /\ wl # None
C4(r) == rpc[r] = "parked" /\ wl = None /\ FSig
C5(r) == rpc[r] = "parked" /\ wl = None /\ ~FSig /\ bl # None
C6(r) == rpc[r] = "parked" /\ wl = None /\ ~FSig /\ bl = None

LEMMA Cover ==
  ASSUME LiveInv, NEW r \in Threads, rpc[r] # "done"
  PROVE C1(r) \/ C2(r) \/ C3(r) \/ C4(r) \/ C5(r) \/ C6(r)
  <1>1 rpc[r] \in States /\ rpc[r] # "nsee"
    BY DEF LiveInv, SafeInv, TypeOK, Safety, NoEmptyTake
  <1> QED
    BY <1>1 DEF States, C1, C2, C3, C4, C5, C6, RFree

\* C6: no closer is done (r is parked), none signals, so one is at close
LEMMA CloserAtClose ==
  ASSUME LiveInv, NEW r \in Threads, C6(r)
  PROVE \E c \in Closers : cpc[c] = "close"
  <1>1 parked # {}
    BY DEF C6, LiveInv, SafeInv, ParkedInv
  <1>2 \A c \in Closers : cpc[c] # "done" /\ cpc[c] # "siglock"
    BY <1>1 DEF C6, FSig, LiveInv, ClosedNoPark
  <1>3 1 \in Closers
    BY LiveAssump DEF Closers
  <1> QED
    BY <1>2, <1>3 DEF LiveInv, SafeInv, TypeOK

\* the premises of WF1 for each case (Base: r has not stopped, the measure is n)
Base(r, n) == LiveInv /\ FMeas(r) = n /\ rpc[r] # "done"
Goal(r, n) == LiveInv /\ FMeas(r) < n /\ rpc[r] # "done"

LEMMA FairParts ==
  ASSUME NEW r \in Threads
  PROVE SpecRole => /\ [][NextF]_vars /\ WF_vars(ThreadStep(r))
                    /\ WF_vars(BLHolder) /\ WF_vars(WLHolder) /\ WF_vars(Signal)
                    /\ WF_vars(Closing)
  BY DEF SpecRole, FairRole

\* the two premises shared by the cases: a step keeps the case or reaches the goal; a step that
\* lowers the measure reaches the goal
LEMMA KeepCase ==
  ASSUME NEW r \in Threads, NEW n \in Nat, Base(r, n), [NextF]_vars, [~Ret(r)]_vars
  PROVE \/ Goal(r, n)'
        \/ /\ Base(r, n)' /\ rpc'[r] = rpc[r] /\ bl' = bl /\ wl' = wl /\ parked' = parked
           /\ wpc' = wpc /\ cpc' = cpc
  BY KeepOrDrop DEF Base, Goal

LEMMA DropCase ==
  ASSUME NEW r \in Threads, NEW n \in Nat, Base(r, n), [NextF]_vars, [~Ret(r)]_vars,
         FMeas(r)' < FMeas(r)
  PROVE Goal(r, n)'
  BY KeepOrDrop DEF Base, Goal

LEMMA StepOf ==
  ASSUME NEW r \in Threads, NEW ACTION A, [NextF]_vars, [~Ret(r)]_vars, <<A>>_vars
  PROVE NextF /\ ~Ret(r) /\ A
  OBVIOUS

LEMMA Case1 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C1(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C1(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C1(r))' \/ Goal(r, n)'
    BY KeepCase DEF C1, RFree
  <1>2 Base(r, n) /\ C1(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<ThreadStep(r)>>_vars => Goal(r, n)'
    BY StepOf, DropOwn, DropCase DEF Base
  <1>3 Base(r, n) /\ C1(r) => ENABLED <<ThreadStep(r)>>_vars
    <2> SUFFICES ASSUME Base(r, n), C1(r) PROVE ENABLED <<ThreadStep(r)>>_vars
      OBVIOUS
    <2>1 SafeInv /\ RFree(r)
      BY DEF Base, C1, LiveInv
    <2>2 EnR(r)
      BY <2>1, EnThreadR
    <2> QED
      BY <2>2 DEF EnR
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

LEMMA Case2 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C2(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C2(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C2(r))' \/ Goal(r, n)'
    BY KeepCase DEF C2
  <1>2 Base(r, n) /\ C2(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<BLHolder>>_vars => Goal(r, n)'
    BY StepOf, DropHolder, DropCase DEF Base
  <1>3 Base(r, n) /\ C2(r) => ENABLED <<BLHolder>>_vars
    BY EnBL DEF Base, C2, LiveInv
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

LEMMA Case3 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C3(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C3(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C3(r))' \/ Goal(r, n)'
    BY KeepCase DEF C3
  <1>2 Base(r, n) /\ C3(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<WLHolder>>_vars => Goal(r, n)'
    BY StepOf, DropHolder, DropCase DEF Base
  <1>3 Base(r, n) /\ C3(r) => ENABLED <<WLHolder>>_vars
    BY EnWL DEF Base, C3, LiveInv
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

LEMMA Case4 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C4(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C4(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C4(r))' \/ Goal(r, n)'
    BY KeepCase DEF C4, FSig
  <1>2 Base(r, n) /\ C4(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<Signal>>_vars => Goal(r, n)'
    BY StepOf, DropWC, DropCase DEF Base
  <1>3 Base(r, n) /\ C4(r) => ENABLED <<Signal>>_vars
    <2> SUFFICES ASSUME Base(r, n), C4(r) PROVE ENABLED <<Signal>>_vars
      OBVIOUS
    <2>1 parked # {}
      BY DEF Base, C4, LiveInv, SafeInv, ParkedInv
    <2> QED
      BY <2>1, EnSignal DEF Base, C4, FSig, LiveInv
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

LEMMA Case5 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C5(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C5(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C5(r))' \/ Goal(r, n)'
    BY KeepCase DEF C5, FSig
  <1>2 Base(r, n) /\ C5(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<BLHolder>>_vars => Goal(r, n)'
    BY StepOf, DropHolder, DropCase DEF Base
  <1>3 Base(r, n) /\ C5(r) => ENABLED <<BLHolder>>_vars
    BY EnBL DEF Base, C5, LiveInv
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

LEMMA Case6 ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ C6(r) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) /\ C6(r) /\ [NextF]_vars /\ [~Ret(r)]_vars => (Base(r, n) /\ C6(r))' \/ Goal(r, n)'
    BY KeepCase DEF C6, FSig
  <1>2 Base(r, n) /\ C6(r) /\ [NextF]_vars /\ [~Ret(r)]_vars /\ <<Closing>>_vars => Goal(r, n)'
    BY StepOf, DropWC, DropCase DEF Base
  <1>3 Base(r, n) /\ C6(r) => ENABLED <<Closing>>_vars
    <2> SUFFICES ASSUME Base(r, n), C6(r) PROVE ENABLED <<Closing>>_vars
      OBVIOUS
    <2>1 \E c \in Closers : cpc[c] = "close"
      BY CloserAtClose DEF Base
    <2> QED
      BY <2>1, EnClosing DEF Base, C6, LiveInv
  <1> QED
    BY <1>1, <1>2, <1>3, FairParts, PTL

\* from every state in which r has not stopped, the measure goes down, or r returns
LEMMA Lower ==
  ASSUME NEW r \in Threads, NEW n \in Nat
  PROVE SpecRole => [](Base(r, n) /\ [][~Ret(r)]_vars => <>Goal(r, n))
  <1>1 Base(r, n) => C1(r) \/ C2(r) \/ C3(r) \/ C4(r) \/ C5(r) \/ C6(r)
    BY Cover DEF Base
  <1> QED
    BY <1>1, Case1, Case2, Case3, Case4, Case5, Case6, PTL

\* the measure is bounded by a constant
MB == FW * (3 * Bytes + 3 * NW + 3 * NC + Spurious) + Bytes + 28 * FNT + 6

LEMMA MeasBound ==
  ASSUME LiveInv, NEW r \in Threads
  PROVE FMeas(r) <= MB /\ MB \in Nat
  <1>1 FNT \in Nat /\ FW \in Nat /\ FIP \in Nat /\ Buffered \in Nat /\ FBad \in Nat
       /\ FBad <= FNT /\ FSumV \in Nat /\ FSumV <= 10 * FNT
    BY FTypes
  <1>2 /\ WW \in Nat /\ WS \in Nat /\ CC \in Nat /\ CS \in Nat
       /\ WW <= NW /\ WS <= NW /\ CC <= NC /\ CS <= NC
    BY Fin, AtType DEF WW, WS, CC, CS
  <1>3 /\ w \in Nat /\ t \in Nat /\ w <= Bytes /\ t <= w /\ Bytes \in Nat /\ NW \in Nat
       /\ NC \in Nat /\ Buffered <= Bytes
       /\ spurious \in Nat /\ spurious <= Spurious /\ Spurious \in Nat
    BY ConstAssump DEF LiveInv, SafeInv, TypeOK, BufNonNeg, Buffered, InFlight
  <1>4 FIP <= 3 * Bytes + 3 * NW + 3 * NC + Spurious
    <2>1 FIP - spurious <= 3 * Bytes + 3 * NW + 3 * NC
      BY ONLY <1>2, <1>3, FParts
    <2> QED
      BY ONLY <2>1, <1>1, <1>3
  <1>5 FW * FIP <= FW * (3 * Bytes + 3 * NW + 3 * NC + Spurious)
    <2> DEFINE b == 3 * Bytes + 3 * NW + 3 * NC + Spurious
    <2>1 b \in Nat /\ b - FIP \in Nat
      BY <1>1, <1>3, <1>4
    <2>2 FW * b = FW * FIP + FW * (b - FIP) /\ FW * (b - FIP) \in Nat
      BY <1>1, <2>1
    <2> QED
      BY <1>1, <2>1, <2>2
  <1>6 FRank(r) \in 0..6
    BY DEF FRank
  <1> QED
    BY <1>1, <1>3, <1>5, <1>6 DEF FMeas, MB

THEOREM LiveInvariantF == SpecRole => []LiveInv
  BY LiveInit, LiveStepF, PTL DEF SpecRole

\* the liveness of r: every call of r returns, or r stopped
THEOREM ForeverLivenessOf ==
  ASSUME NEW r \in Threads
  PROVE SpecRole => ([]<><<Ret(r)>>_vars \/ <>(rpc[r] = "done"))
  <1> DEFINE P(n) == SpecRole => [](Goal(r, n) => <><<Ret(r)>>_vars)
  <1> HIDE DEF P
  <1>1 \A n \in Nat : P(n)
    <2>1 P(0)
      <3>1 Goal(r, 0) => FALSE
        BY FMeasNat DEF Goal
      <3> QED
        BY <3>1, PTL DEF P
    <2>2 ASSUME NEW n \in Nat PROVE P(n) => P(n + 1)
      <3>1 Goal(r, n + 1) => Goal(r, n) \/ Base(r, n)
        BY FMeasNat DEF Goal, Base
      <3>2 SpecRole => [](Base(r, n) /\ [][~Ret(r)]_vars => <>Goal(r, n))
        BY Lower
      <3> QED
        BY <3>1, <3>2, PTL DEF P
    <2> QED
      BY <2>1, <2>2, NatInduction, Isa
  <1>2 P(MB + 1)
    <2>1 MB \in Nat
      BY Fin, FParts, ConstAssump DEF MB, FW
    <2> QED
      BY <1>1, <2>1
  <1>3 LiveInv /\ ~(rpc[r] = "done") => Goal(r, MB + 1)
    <2> SUFFICES ASSUME LiveInv, ~(rpc[r] = "done") PROVE Goal(r, MB + 1)
      OBVIOUS
    <2>1 FMeas(r) <= MB /\ MB \in Nat /\ FMeas(r) \in Nat
      BY MeasBound, FMeasNat
    <2> QED
      BY <2>1 DEF Goal
  <1> QED
    BY <1>2, <1>3, LiveInvariantF, PTL DEF P

THEOREM ForeverLiveness == SpecRole => EveryCallReturns
  <1>1 \A r \in Threads : SpecRole => ([]<><<Ret(r)>>_vars \/ <>(rpc[r] = "done"))
    BY ForeverLivenessOf
  <1> QED
    BY <1>1 DEF EveryCallReturns
=============================================================================
