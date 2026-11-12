\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------- MODULE StreamBufferCountersProof ----------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): SafeInv of StreamBufferCounters is an    *)
(* inductive invariant for ANY number of readers N and any number of bytes, *)
(* so the safety properties hold in every reachable state. Apalache checks  *)
(* IndInv (SafeInv and the waitingReaders count) for fixed N               *)
(* (inductive.sh); this proof removes the bound on the readers too.         *)
(***************************************************************************)
EXTENDS StreamBufferCounters, TLAPS

ASSUME ConstAssump == /\ N \in Nat /\ N >= 1
                      /\ Bytes \in Nat /\ Bytes >= 1
                      /\ ReCheck = TRUE

Spec0 == Init /\ [][Next]_vars

LEMMA InitSafe == Init => SafeInv
  BY ConstAssump DEF Init, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Readers, None, States, BufLock, HoldInv, BufNonNeg, CopyHasByte, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv

LEMMA StepSafe == SafeInv /\ [Next]_vars => SafeInv'
  <1> SUFFICES ASSUME SafeInv, [Next]_vars PROVE SafeInv'
    OBVIOUS
  <1> USE ConstAssump DEF SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Readers, None, States, BufLock, HoldInv, BufNonNeg, CopyHasByte, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv
<1>1 CASE WriterWrite
  BY <1>1 DEF WriterWrite
<1>2 CASE WriterSigRead
  BY <1>2 DEF WriterSigRead, WriterNext
<1>3 CASE WriterSigLock
  BY <1>3 DEF WriterSigLock, WakeAll, WriterNext
<1>4 CASE CloserClose
  BY <1>4 DEF CloserClose
<1>5 CASE CloserSigRead
  BY <1>5 DEF CloserSigRead
<1>6 CASE CloserSigLock
  BY <1>6 DEF CloserSigLock, WakeAll
  <1>7 CASE \E r \in Readers : ReaderStep(r)
    <2> PICK r \in Readers : ReaderStep(r)
      BY <1>7
  <2>1 CASE ReaderStart(r)
    BY <2>1 DEF ReaderStart, Go
  <2>2 CASE ReaderReread(r)
    BY <2>2 DEF ReaderReread, Go
  <2>3 CASE ReaderWaitLock(r)
    <3> USE <2>3 DEF ReaderWaitLock, Go
    <3>1 TypeOK'
      OBVIOUS
    <3>2 Safety'
      OBVIOUS
    <3>3 BufLock'
      OBVIOUS
    <3>4 HoldInv'
      OBVIOUS
    <3>5 BufNonNeg'
      OBVIOUS
    <3>6 CopyHasByte'
      OBVIOUS
    <3>7 WaitLockInv'
      OBVIOUS
    <3>8 ParkedInv'
      OBVIOUS
    <3>9 RereadClosed'
      OBVIOUS
    <3>10 Ret0Empty'
      OBVIOUS
    <3>11 DoneEof'
      OBVIOUS
    <3>12 CloserInv'
      OBVIOUS
    <3>13 WriterInv'
      OBVIOUS
    <3> QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
  <2>4 CASE ReaderInc(r)
    <3> USE <2>4 DEF ReaderInc, Go
    <3>1 TypeOK'
      OBVIOUS
    <3>2 Safety'
      OBVIOUS
    <3>3 BufLock'
      OBVIOUS
    <3>4 HoldInv'
      OBVIOUS
    <3>5 BufNonNeg'
      OBVIOUS
    <3>6 CopyHasByte'
      OBVIOUS
    <3>7 WaitLockInv'
      OBVIOUS
    <3>8 ParkedInv'
      OBVIOUS
    <3>9 RereadClosed'
      OBVIOUS
    <3>10 Ret0Empty'
      OBVIOUS
    <3>11 DoneEof'
      OBVIOUS
    <3>12 CloserInv'
      OBVIOUS
    <3>13 WriterInv'
      OBVIOUS
    <3> QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
  <2>5 CASE ReaderTest(r)
    BY <2>5 DEF ReaderTest, Go
  <2>6 CASE ReaderLock(r)
    <3> USE <2>6 DEF ReaderLock, Go
    <3>1 TypeOK'
      OBVIOUS
    <3>2 Safety'
      OBVIOUS
    <3>3 BufLock'
      OBVIOUS
    <3>4 HoldInv'
      OBVIOUS
    <3>5 BufNonNeg'
      OBVIOUS
    <3>6 CopyHasByte'
      OBVIOUS
    <3>7 WaitLockInv'
      OBVIOUS
    <3>8 ParkedInv'
      OBVIOUS
    <3>9 RereadClosed'
      OBVIOUS
    <3>10 Ret0Empty'
      OBVIOUS
    <3>11 DoneEof'
      OBVIOUS
    <3>12 CloserInv'
      OBVIOUS
    <3>13 WriterInv'
      OBVIOUS
    <3> QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
  <2>7 CASE ReaderDecide(r)
    <3> USE <2>7 DEF ReaderDecide, Go
    <3>1 TypeOK'
      \* ReCheck: copy when a byte is counted, else release bufferLock and start over
      <4>1 CASE avail >= 1
        BY <4>1
      <4>2 CASE ~(avail >= 1)
        <5>1 rpc' = [rpc EXCEPT ![r] = "start"] /\ bl' = 0
          BY <4>2
        <5>2 rpc' \in [Readers -> States]
          BY <5>1
        <5> QED
          BY <5>1, <5>2
      <4> QED
        BY <4>1, <4>2
    <3>2 Safety'
      OBVIOUS
    <3>3 BufLock'
      OBVIOUS
    <3>4 HoldInv'
      OBVIOUS
    <3>5 BufNonNeg'
      OBVIOUS
    <3>6 CopyHasByte'
      OBVIOUS
    <3>7 WaitLockInv'
      OBVIOUS
    <3>8 ParkedInv'
      OBVIOUS
    <3>9 RereadClosed'
      OBVIOUS
    <3>10 Ret0Empty'
      OBVIOUS
    <3>11 DoneEof'
      OBVIOUS
    <3>12 CloserInv'
      OBVIOUS
    <3>13 WriterInv'
      OBVIOUS
    <3> QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
  <2>8 CASE ReaderCopy(r)
    BY <2>8 DEF ReaderCopy, Go
  <2>9 CASE ReaderFinish(r)
    BY <2>9 DEF ReaderFinish, Go
  <2>10 CASE ReaderRet0(r)
    <3> USE <2>10 DEF ReaderRet0, Go
    \* the end of the stream: nothing is in flight, the buffer is empty
    <3>0 InFlight = 0
      <4>1 avail = 0 /\ closed
        BY DEF Ret0Empty
      <4>2 InFlight \in {0, 1}
        BY DEF InFlight
      <4> QED
        BY <4>1, <4>2 DEF BufNonNeg, AvailLinearizable, Buffered
    <3>1 TypeOK'
      OBVIOUS
    <3>2 Safety'
      BY <3>0
    <3>3 BufLock'
      OBVIOUS
    <3>4 HoldInv'
      OBVIOUS
    <3>5 BufNonNeg'
      OBVIOUS
    <3>6 CopyHasByte'
      OBVIOUS
    <3>7 WaitLockInv'
      OBVIOUS
    <3>8 ParkedInv'
      OBVIOUS
    <3>9 RereadClosed'
      OBVIOUS
    <3>10 Ret0Empty'
      OBVIOUS
    <3>11 DoneEof'
      OBVIOUS
    <3>12 CloserInv'
      OBVIOUS
    <3>13 WriterInv'
      OBVIOUS
    <3> QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10 DEF ReaderStep
  <1>8 CASE UNCHANGED vars
    BY <1>8 DEF vars
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8 DEF Next

THEOREM SafeInvariant == Spec0 => []SafeInv
  BY InitSafe, StepSafe, PTL DEF Spec0

THEOREM SafetyHolds == Spec0 => []Safety
  <1>1 SafeInv => Safety
    BY DEF SafeInv
  <1> QED
    BY SafeInvariant, <1>1, PTL
=============================================================================
