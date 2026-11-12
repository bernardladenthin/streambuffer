\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------- MODULE StreamBufferRecordsProof -----------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): SafeInv of StreamBufferRecords is an     *)
(* inductive invariant for ANY number of readers N, any record size K, any  *)
(* number of bytes and any chunking of the writes, so the safety properties *)
(* hold in every reachable state -- whole aligned records included (#212).  *)
(***************************************************************************)
EXTENDS StreamBufferRecords, TLAPS

ASSUME ConstAssump == /\ N \in Nat /\ N >= 1
                      /\ Bytes \in Nat /\ Bytes >= 1
                      /\ K \in Nat /\ K >= 1
                      /\ AtomicRead = TRUE

LEMMA InitSafe == Init => SafeInv
  BY ConstAssump DEF Init, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, RecordsAligned, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Readers, None, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, WholeRead, CurZero, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv

LEMMA StepSafe == SafeInv /\ [Next]_vars => SafeInv'
  <1> SUFFICES ASSUME SafeInv, [Next]_vars PROVE SafeInv'
    OBVIOUS
  <1> USE ConstAssump DEF SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, RecordsAligned, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Readers, None, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, WholeRead, CurZero, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv
  <1>1 CASE WriterWrite
    <2> USE <1>1 DEF WriterWrite
    <2>1 TypeOK'
      OBVIOUS
    <2>2 Safety'
      OBVIOUS
    <2>3 BufLock'
      OBVIOUS
    <2>4 HoldLeft'
      OBVIOUS
    <2>5 BufNonNeg'
      OBVIOUS
    <2>6 CopyHasBytes'
      OBVIOUS
    <2>7 WholeRead'
      OBVIOUS
    <2>8 CurZero'
      OBVIOUS
    <2>9 WaitLockInv'
      OBVIOUS
    <2>10 ParkedInv'
      OBVIOUS
    <2>11 RereadClosed'
      OBVIOUS
    <2>12 Ret0Empty'
      OBVIOUS
    <2>13 DoneEof'
      OBVIOUS
    <2>14 CloserInv'
      OBVIOUS
    <2>15 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15 DEF SafeInv
  <1>2 CASE WriterSigLock
    <2> USE <1>2 DEF WriterSigLock, WakeAll, WriterNext
    <2>1 TypeOK'
      OBVIOUS
    <2>2 Safety'
      OBVIOUS
    <2>3 BufLock'
      OBVIOUS
    <2>4 HoldLeft'
      OBVIOUS
    <2>5 BufNonNeg'
      OBVIOUS
    <2>6 CopyHasBytes'
      OBVIOUS
    <2>7 WholeRead'
      OBVIOUS
    <2>8 CurZero'
      OBVIOUS
    <2>9 WaitLockInv'
      OBVIOUS
    <2>10 ParkedInv'
      OBVIOUS
    <2>11 RereadClosed'
      OBVIOUS
    <2>12 Ret0Empty'
      OBVIOUS
    <2>13 DoneEof'
      OBVIOUS
    <2>14 CloserInv'
      OBVIOUS
    <2>15 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15 DEF SafeInv
  <1>3 CASE CloserClose
    <2> USE <1>3 DEF CloserClose
    <2>1 TypeOK'
      OBVIOUS
    <2>2 Safety'
      OBVIOUS
    <2>3 BufLock'
      OBVIOUS
    <2>4 HoldLeft'
      OBVIOUS
    <2>5 BufNonNeg'
      OBVIOUS
    <2>6 CopyHasBytes'
      OBVIOUS
    <2>7 WholeRead'
      OBVIOUS
    <2>8 CurZero'
      OBVIOUS
    <2>9 WaitLockInv'
      OBVIOUS
    <2>10 ParkedInv'
      OBVIOUS
    <2>11 RereadClosed'
      OBVIOUS
    <2>12 Ret0Empty'
      OBVIOUS
    <2>13 DoneEof'
      OBVIOUS
    <2>14 CloserInv'
      OBVIOUS
    <2>15 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15 DEF SafeInv
  <1>4 CASE CloserSigLock
    <2> USE <1>4 DEF CloserSigLock, WakeAll
    <2>1 TypeOK'
      OBVIOUS
    <2>2 Safety'
      OBVIOUS
    <2>3 BufLock'
      OBVIOUS
    <2>4 HoldLeft'
      OBVIOUS
    <2>5 BufNonNeg'
      OBVIOUS
    <2>6 CopyHasBytes'
      OBVIOUS
    <2>7 WholeRead'
      OBVIOUS
    <2>8 CurZero'
      OBVIOUS
    <2>9 WaitLockInv'
      OBVIOUS
    <2>10 ParkedInv'
      OBVIOUS
    <2>11 RereadClosed'
      OBVIOUS
    <2>12 Ret0Empty'
      OBVIOUS
    <2>13 DoneEof'
      OBVIOUS
    <2>14 CloserInv'
      OBVIOUS
    <2>15 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15 DEF SafeInv
  <1>5 CASE \E r \in Readers : ReaderStep(r)
    <2> PICK r \in Readers : ReaderStep(r)
      BY <1>5
    <2>1 CASE ReaderStart(r)
      <3> USE <2>1 DEF ReaderStart, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>2 CASE ReaderReread(r)
      <3> USE <2>2 DEF ReaderReread, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>3 CASE ReaderWaitLock(r)
      <3> USE <2>3 DEF ReaderWaitLock, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>4 CASE ReaderInc(r)
      <3> USE <2>4 DEF ReaderInc, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>5 CASE ReaderTest(r)
      <3> USE <2>5 DEF ReaderTest, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>6 CASE ReaderLock(r)
      <3> USE <2>6 DEF ReaderLock, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>7 CASE ReaderDecide(r)
      <3> USE <2>7 DEF ReaderDecide, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>8 CASE ReaderCopy(r)
      <3> USE <2>8 DEF ReaderCopy, Go
      \* the re-check: a byte is buffered, so the copy takes k of them
      <3>0 Buffered >= 1
        BY DEF CopyHasBytes, HoldLeft
      <3> PICK k \in 1..left[r] : /\ k <= Buffered
                     /\ hold' = [hold EXCEPT ![r] = @ + k]
                     /\ left' = [left EXCEPT ![r] = @ - k]
                     /\ Go(r, IF left[r] = k THEN "finish" ELSE "copy")
        BY <3>0
      <3>1 TypeOK'
        <4>1 k \in Nat /\ k >= 1 /\ k <= left[r]
          OBVIOUS
        <4>2 hold' \in [Readers -> Nat]
          BY <4>1
        <4>3 left' \in [Readers -> Nat]
          BY <4>1
        <4>4 rpc' \in [Readers -> States]
          OBVIOUS
        <4> QED
          BY <4>2, <4>3, <4>4
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>9 CASE ReaderFinish(r)
      <3> USE <2>9 DEF ReaderFinish, Go
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2>10 CASE ReaderRet0(r)
      <3> USE <2>10 DEF ReaderRet0, Go
      \* the end of the stream: nothing is in flight, the buffer is empty
      <3>0 InFlight = 0
        <4>1 avail = 0 /\ closed
          BY DEF Ret0Empty
        <4>2 InFlight \in Nat /\ (bl # None => InFlight = hold[bl])
          BY DEF InFlight
        <4> QED
          BY <4>1, <4>2 DEF BufNonNeg, AvailLinearizable, Buffered
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        BY <3>0
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 CurZero'
        OBVIOUS
      <3>9 WaitLockInv'
        OBVIOUS
      <3>10 ParkedInv'
        OBVIOUS
      <3>11 RereadClosed'
        OBVIOUS
      <3>12 Ret0Empty'
        OBVIOUS
      <3>13 DoneEof'
        OBVIOUS
      <3>14 CloserInv'
        OBVIOUS
      <3>15 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15 DEF SafeInv
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10 DEF ReaderStep
  <1>6 CASE UNCHANGED vars
    BY <1>6 DEF vars
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6 DEF Next

THEOREM SafeInvariant == CSpec => []SafeInv
  BY InitSafe, StepSafe, PTL DEF CSpec

THEOREM SafetyHolds == CSpec => []Safety
  <1>1 SafeInv => Safety
    BY DEF SafeInv
  <1> QED
    BY SafeInvariant, <1>1, PTL
=============================================================================
