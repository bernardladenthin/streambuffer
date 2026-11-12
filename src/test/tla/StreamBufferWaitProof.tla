\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------- MODULE StreamBufferWaitProof -----------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): SafeInv of StreamBufferWait is an        *)
(* inductive invariant for ANY set of threads, each making any number of   *)
(* calls, each a read(b, 0, K[r]) or a waitForAtLeast(M[r]), and any       *)
(* numbers of writers and closers, any read size and request per thread,   *)
(* number of bytes and chunking of the writes: waitForAtLeast(M[r])        *)
(* returns fewer than M[r] only for a closed buffer, every read takes      *)
(* K[r] bytes (fewer only once closed), with one read size whole aligned   *)
(* records, and the other safety properties.                               *)
(***************************************************************************)
EXTENDS StreamBufferWait, TLAPS

ASSUME ConstAssump == /\ None \notin Threads /\ NW \in Nat /\ NC \in Nat
                      /\ Bytes \in Nat /\ Bytes >= 1
                      /\ K \in [Threads -> Nat] /\ \A r \in Threads : K[r] >= 1
                      /\ M \in [Threads -> Nat] /\ \A r \in Threads : M[r] >= 1
                      /\ RecLen \in Nat /\ RecLen >= 1 /\ Calls0 \in Nat
                      /\ CheckedReturn = TRUE

LEMMA InitSafe == Init => SafeInv
  BY ConstAssump DEF Init, SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WaitEnoughOrClosed, WholeRead, RecordsAligned, Uniform, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Writers, Closers, Ops, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv

LEMMA StepSafe == SafeInv /\ [Next]_vars => SafeInv'
  <1> SUFFICES ASSUME SafeInv, [Next]_vars PROVE SafeInv'
    OBVIOUS
  <1> USE ConstAssump DEF SafeInv, TypeOK, Safety, NoEmptyTake, AvailLinearizable, WaitEnoughOrClosed, WholeRead, RecordsAligned, Uniform, NoWriteAfterEof, EofOnlyWhenClosedAndEmpty, Buffered, InFlight, Writers, Closers, Ops, States, Min, Want, BufLock, HoldLeft, BufNonNeg, CopyHasBytes, OpStates, WaitLockInv, ParkedInv, RereadClosed, Ret0Empty, CloserInv, WriterInv
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2> QED
      BY <2>1, <2>2
  <1>2 CASE \E c \in Closers : CloserClose(c) \/ CloserSigLock(c)
    <2> PICK c \in Closers : CloserClose(c) \/ CloserSigLock(c)
      BY <1>2
    <2>1 CASE CloserClose(c)
      <3> USE <2>1 DEF CloserClose, CGo
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>2 CASE CloserSigLock(c)
      <3> USE <2>2 DEF CloserSigLock, WakeAll, CGo
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2> QED
      BY <2>1, <2>2
  <1>3 CASE \E r \in Threads : ThreadStep(r)
    <2> PICK r \in Threads : ThreadStep(r)
      BY <1>3
    <2>1 CASE ThreadStart(r)
      <3> USE <2>1 DEF ThreadStart, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>2 CASE ThreadReread(r)
      <3> USE <2>2 DEF ThreadReread, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>3 CASE ThreadWaitLock(r)
      <3> USE <2>3 DEF ThreadWaitLock, Go, Return, EndCall
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>4 CASE ThreadInc(r)
      <3> USE <2>4 DEF ThreadInc, Go, Return, EndCall
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>5 CASE ThreadTest(r)
      <3> USE <2>5 DEF ThreadTest, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>6 CASE ThreadWaitReturn(r)
      <3> USE <2>6 DEF ThreadWaitReturn, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>7 CASE ThreadLock(r)
      <3> USE <2>7 DEF ThreadLock, Go, Return, EndCall
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>8 CASE ThreadDecide(r)
      <3> USE <2>8 DEF ThreadDecide, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 Min(avail, K[r]) \in Nat
          OBVIOUS
        <4>2 left' \in [Threads -> Nat]
          BY <4>1
        <4>3 rpc' \in [Threads -> States] /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4> QED
          BY <4>2, <4>3
      <3>2 Safety'
        <4>1 NoEmptyTake'
          OBVIOUS
        <4>2 AvailLinearizable'
          OBVIOUS
        <4>3 WaitEnoughOrClosed'
          OBVIOUS
        <4>4 WholeRead'
          <5>1 CASE avail >= K[r] \/ (closed /\ avail > 0)
            BY <5>1
          <5>2 CASE ~(avail >= K[r] \/ (closed /\ avail > 0))
            BY <5>2
          <5> QED
            BY <5>1, <5>2
        <4>5 RecordsAligned'
          OBVIOUS
        <4>6 NoWriteAfterEof'
          OBVIOUS
        <4>7 EofOnlyWhenClosedAndEmpty'
          OBVIOUS
        <4> QED
          BY <4>1, <4>2, <4>3, <4>4, <4>5, <4>6, <4>7
      <3>3 BufLock'
        OBVIOUS
      <3>4 HoldLeft'
        OBVIOUS
      <3>5 BufNonNeg'
        OBVIOUS
      <3>6 CopyHasBytes'
        OBVIOUS
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>9 CASE ThreadCopy(r)
      <3> USE <2>9 DEF ThreadCopy, Go, Return, EndCall
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>10 CASE ThreadFinish(r)
      <3> USE <2>10 DEF ThreadFinish, Go, Return, EndCall
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2>11 CASE ThreadRet0(r)
      <3> USE <2>11 DEF ThreadRet0, Go, Return, EndCall
      \* the end of the stream: nothing is in flight, the buffer is empty
      <3>0 InFlight = 0
        <4>1 avail = 0 /\ closed
          BY DEF Ret0Empty
        <4>2 InFlight \in Nat /\ (bl # None => InFlight = hold[bl])
          <5>1 CASE bl = None
            BY <5>1 DEF InFlight
          <5>2 CASE bl # None
            <6>1 bl \in Threads
              BY <5>2 DEF TypeOK
            <6> QED
              BY <5>2, <6>1 DEF InFlight, TypeOK
          <5> QED
            BY <5>1, <5>2
        <4> QED
          BY <4>1, <4>2 DEF BufNonNeg, AvailLinearizable, Buffered
      <3>1 TypeOK'
        <4>1 rpc' \in [Threads -> States] /\ op' \in [Threads -> Ops] /\ calls' \in Nat
          OBVIOUS
        <4>2 wres' \in [Threads -> Int] /\ wclosed' \in [Threads -> BOOLEAN]
          OBVIOUS
        <4>3 parked' \subseteq Threads /\ wl' \in Threads \cup {None} /\ bl' \in Threads \cup {None}
          OBVIOUS
        <4>4 /\ w' \in Nat /\ w' <= Bytes /\ t' \in Nat /\ t' <= w'
             /\ avail' \in Nat /\ closed' \in BOOLEAN
             /\ wpc' \in [Writers -> {"write", "siglock", "done", "failed"}]
             /\ cpc' \in [Closers -> {"close", "siglock", "done"}]
             /\ hold' \in [Threads -> Nat] /\ left' \in [Threads -> Nat]
             /\ off' \in Nat
             /\ eofAt' \in Int /\ eofAt' >= -1 /\ eofAt' <= Bytes
          OBVIOUS
        <4> QED
          BY <4>1, <4>2, <4>3, <4>4
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
      <3>7 OpStates'
        OBVIOUS
      <3>8 WaitLockInv'
        OBVIOUS
      <3>9 ParkedInv'
        OBVIOUS
      <3>10 RereadClosed'
        OBVIOUS
      <3>11 Ret0Empty'
        OBVIOUS
      <3>12 CloserInv'
        OBVIOUS
      <3>13 WriterInv'
        OBVIOUS
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13 DEF SafeInv
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11 DEF ThreadStep
  <1>4 CASE UNCHANGED vars
    BY <1>4 DEF vars
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4 DEF Next

THEOREM SafeInvariant == CSpec => []SafeInv
  BY InitSafe, StepSafe, PTL DEF CSpec

THEOREM SafetyHolds == CSpec => []Safety
  <1>1 SafeInv => Safety
    BY DEF SafeInv
  <1> QED
    BY SafeInvariant, <1>1, PTL
=============================================================================
