\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------- MODULE StreamBufferWaitProof -----------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): SafeInv of StreamBufferWait is an        *)
(* inductive invariant for ANY number of read(b, 0, K) readers and         *)
(* waitForAtLeast callers and writers, any K, M, number of bytes and       *)
(* chunking of the writes, so waitForAtLeast(M) returns fewer than M only  *)
(* for a closed buffer, and every read takes a whole record.               *)
(***************************************************************************)
EXTENDS StreamBufferWait, TLAPS

ASSUME ConstAssump == /\ N \in Nat /\ N >= 1 /\ NR \in Nat /\ NR <= N /\ NW \in Nat /\ NW >= 1
                      /\ Bytes \in Nat /\ Bytes >= 1
                      /\ M \in Nat /\ M >= 1 /\ K \in Nat /\ K >= 1
                      /\ CheckedReturn = TRUE

LEMMA InitSafe == Init => SafeInv
  BY ConstAssump DEF Init, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WaitEnoughOrClosed, RecordsAligned, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Threads, Writers, IsWaiter, None, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, WholeRead, WaiterStates, ReaderStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv

LEMMA StepSafe == SafeInv /\ [Next]_vars => SafeInv'
  <1> SUFFICES ASSUME SafeInv, [Next]_vars PROVE SafeInv'
    OBVIOUS
  <1> USE ConstAssump DEF SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WaitEnoughOrClosed, RecordsAligned, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Threads, Writers, IsWaiter, None, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, WholeRead, WaiterStates, ReaderStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, DoneEof, CloserInv, WriterInv
  <1>1 CASE \E i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
    <2> PICK i \in Writers : WriterWrite(i) \/ WriterSigLock(i)
      BY <1>1
    <2>1 CASE WriterWrite(i)
      <3> USE <2>1 DEF WriterWrite, WGo
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>2 CASE WriterSigLock(i)
      <3> USE <2>2 DEF WriterSigLock, WakeAll, WriterNext, WGo
      <3>1 TypeOK'
        OBVIOUS
      <3>2 Safety'
        OBVIOUS
      <3>3 BufLock'
        \* the signal wakes only parked threads, none of which holds bufferLock
        <4>1 CASE parked = {}
          BY <4>1
        <4>2 CASE parked # {}
          BY <4>2
        <4> QED
          BY <4>1, <4>2
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 WholeRead'
        OBVIOUS
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2> QED
      BY <2>1, <2>2
  <1>2 CASE CloserClose
    <2> USE <1>2 DEF CloserClose
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
    <2>8 WaiterStates'
      OBVIOUS
    <2>9 ReaderStates'
      OBVIOUS
    <2>10 WaitLockInv'
      OBVIOUS
    <2>11 ParkedInv'
      OBVIOUS
    <2>12 RereadClosed'
      OBVIOUS
    <2>13 Ret0Empty'
      OBVIOUS
    <2>14 DoneEof'
      OBVIOUS
    <2>15 CloserInv'
      OBVIOUS
    <2>16 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15, <2>16 DEF SafeInv
  <1>3 CASE CloserSigLock
    <2> USE <1>3 DEF CloserSigLock, WakeAll
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
    <2>8 WaiterStates'
      OBVIOUS
    <2>9 ReaderStates'
      OBVIOUS
    <2>10 WaitLockInv'
      OBVIOUS
    <2>11 ParkedInv'
      OBVIOUS
    <2>12 RereadClosed'
      OBVIOUS
    <2>13 Ret0Empty'
      OBVIOUS
    <2>14 DoneEof'
      OBVIOUS
    <2>15 CloserInv'
      OBVIOUS
    <2>16 WriterInv'
      OBVIOUS
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15, <2>16 DEF SafeInv
  <1>4 CASE \E r \in Threads : ThreadStep(r)
    <2> PICK r \in Threads : ThreadStep(r)
      BY <1>4
    <2>1 CASE ThreadStart(r)
      <3> USE <2>1 DEF ThreadStart, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>2 CASE ThreadReread(r)
      <3> USE <2>2 DEF ThreadReread, Go, Return
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States]
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in 0..N /\ bl' \in 0..N
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in {"close", "siglock", "done"}
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat /\ off' < K
             /\ eofAt' \in Int /\ eofAt' >= -1 /\ eofAt' <= Bytes
          OBVIOUS
        <4> QED
          BY <4>1, <4>2, <4>3, <4>4
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>3 CASE ThreadWaitLock(r)
      <3> USE <2>3 DEF ThreadWaitLock, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>4 CASE ThreadInc(r)
      <3> USE <2>4 DEF ThreadInc, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>5 CASE ThreadTest(r)
      <3> USE <2>5 DEF ThreadTest, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>6 CASE ThreadWaitReturn(r)
      <3> USE <2>6 DEF ThreadWaitReturn, Go, Return
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States]
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in 0..N /\ bl' \in 0..N
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in {"close", "siglock", "done"}
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat /\ off' < K
             /\ eofAt' \in Int /\ eofAt' >= -1 /\ eofAt' <= Bytes
          OBVIOUS
        <4> QED
          BY <4>1, <4>2, <4>3, <4>4
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>7 CASE ThreadLock(r)
      <3> USE <2>7 DEF ThreadLock, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>8 CASE ThreadDecide(r)
      <3> USE <2>8 DEF ThreadDecide, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>9 CASE ThreadCopy(r)
      <3> USE <2>9 DEF ThreadCopy, Go, Return
      \* the re-check: a byte is buffered, so the copy takes k of them
      <3>0 Buffered >= 1
        BY DEF CopyHasBytes, HoldLeft
      <3> PICK k \in 0..left[r] : /\ k >= 1 /\ k <= Buffered
                     /\ hold' = [hold EXCEPT ![r] = @ + k]
                     /\ left' = [left EXCEPT ![r] = @ - k]
                     /\ Go(r, IF left[r] = k THEN "finish" ELSE "copy")
        BY <3>0
      <3>1 TypeOK'
        <4>1 k \in Nat /\ k >= 1 /\ k <= left[r]
          OBVIOUS
        <4>2 hold' \in [Threads -> Nat]
          BY <4>1
        <4>3 left' \in [Threads -> Nat]
          BY <4>1
        <4>4 rpc' \in [Threads -> States]
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>10 CASE ThreadFinish(r)
      <3> USE <2>10 DEF ThreadFinish, Go, Return
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2>11 CASE ThreadRet0(r)
      <3> USE <2>11 DEF ThreadRet0, Go, Return
      \* the end of the stream: nothing is in flight, the buffer is empty
      <3>0 InFlight = 0
        <4>1 avail = 0 /\ closed
          BY DEF Ret0Empty
        <4>2 InFlight \in Nat /\ (bl # None => InFlight = hold[bl])
          <5>1 CASE bl = None
            BY <5>1 DEF InFlight
          <5>2 CASE bl # None
            <6>1 bl \in Threads
              BY <5>2 DEF TypeOK, Threads, None
            <6> QED
              BY <5>2, <6>1 DEF InFlight, TypeOK
          <5> QED
            BY <5>1, <5>2
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
      <3>8 WaiterStates'
        OBVIOUS
      <3>9 ReaderStates'
        OBVIOUS
      <3>10 WaitLockInv'
        OBVIOUS
      <3>11 ParkedInv'
        OBVIOUS
      <3>12 RereadClosed'
        OBVIOUS
      <3>13 Ret0Empty'
        OBVIOUS
      <3>14 DoneEof'
        OBVIOUS
      <3>15 CloserInv'
        OBVIOUS
      <3>16 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15, <3>16 DEF SafeInv
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11 DEF ThreadStep
  <1>5 CASE UNCHANGED vars
    BY <1>5 DEF vars
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF Next

THEOREM SafeInvariant == CSpec => []SafeInv
  BY InitSafe, StepSafe, PTL DEF CSpec

THEOREM SafetyHolds == CSpec => []Safety
  <1>1 SafeInv => Safety
    BY DEF SafeInv
  <1> QED
    BY SafeInvariant, <1>1, PTL
=============================================================================
