\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------- MODULE StreamBufferWaitEnabled ----------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): in a state of SafeInv in which no thread *)
(* is parked once a closer is done, a step of StreamBufferWait is possible *)
(* until every thread, writer and closer is done (ENABLED <<Next>>_vars),  *)
(* with at least one closer. For each kind of possible step a              *)
(* deterministic witness action D: ENABLED <<D>>_vars and D => Next, so    *)
(* ENABLED <<Next>>_vars (ENABLEDaxioms). Used by                          *)
(* StreamBufferWaitLiveProof.tla; kept apart from StreamBufferWaitLive.tla,*)
(* since expanding ENABLED in a context that extends that module crashes   *)
(* tlapm 1.6.0-pre.                                                        *)
(***************************************************************************)
EXTENDS StreamBufferWaitProof, TLAPS

\* a call ends and the thread stops (one of the ways EndCall allows)
EndStop(x) == calls' = calls /\ op' = op /\ Go(x, "done")
RetStop(x) ==
    /\ wres' = [wres EXCEPT ![x] = avail]
    /\ wclosed' = [wclosed EXCEPT ![x] = closed]
    /\ EndStop(x)

LEMMA EndStopCall ==
  ASSUME NEW x \in Threads, op \in [Threads -> Ops], calls \in Nat, EndStop(x)
  PROVE EndCall(x)
  <1>1 [op EXCEPT ![x] = op[x]] = op
    OBVIOUS
  <1>2 SUFFICES \E n \in 0..calls : \E o \in Ops : \E s \in {"start", "done"} :
                  /\ s = "start" => n < calls
                  /\ calls' = n /\ op' = [op EXCEPT ![x] = o] /\ Go(x, s)
    BY DEF EndCall
  <1>3 calls \in 0..calls /\ op[x] \in Ops
    OBVIOUS
  <1> QED
    BY <1>1, <1>3 DEF EndStop

LEMMA RetStopReturn ==
  ASSUME NEW x \in Threads, op \in [Threads -> Ops], calls \in Nat, RetStop(x)
  PROVE Return(x)
  BY EndStopCall DEF RetStop, Return

DStartRet(x) ==
    /\ TypeOK /\ rpc[x] = "start" /\ avail >= Want(x) /\ op[x] = "wait"
    /\ RetStop(x) /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DStartGo(x) ==
    /\ TypeOK /\ rpc[x] = "start" /\ ~(avail >= Want(x) /\ op[x] = "wait")
    /\ Go(x, IF avail >= Want(x) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")
    /\ UNCHANGED <<wres, wclosed, op, calls>> /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DRereadRet(x) ==
    /\ TypeOK /\ rpc[x] = "reread" /\ op[x] = "wait"
    /\ RetStop(x) /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DRereadGo(x) ==
    /\ TypeOK /\ rpc[x] = "reread" /\ op[x] # "wait"
    /\ Go(x, IF avail >= 1 THEN "lock" ELSE "ret0")
    /\ UNCHANGED <<wres, wclosed, op, calls>> /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DTestRet(x) ==
    /\ TypeOK /\ rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ avail >= Want(x) /\ CheckedReturn
    /\ RetStop(x) /\ wl' = None /\ UNCHANGED parked /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>
    /\ UNCHANGED spurious

DTestWret(x) ==
    /\ TypeOK /\ rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ ~(avail >= Want(x)) /\ closed
    /\ Go(x, "wret") /\ UNCHANGED <<wl, parked, wres, wclosed, op, calls>> /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>
    /\ UNCHANGED spurious

DTestRead(x) ==
    /\ TypeOK /\ rpc[x] = "test" /\ wl = x /\ op[x] # "wait" /\ (avail >= Want(x) \/ closed)
    /\ Go(x, IF avail >= 1 THEN "lock" ELSE "ret0") /\ wl' = None
    /\ UNCHANGED <<parked, wres, wclosed, op, calls>> /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>
    /\ UNCHANGED spurious

DTestPark(x) ==
    /\ TypeOK /\ rpc[x] = "test" /\ wl = x /\ ~(avail >= Want(x) \/ closed)
    /\ parked' = parked \cup {x} /\ Go(x, "parked") /\ wl' = None
    /\ UNCHANGED <<wres, wclosed, op, calls>> /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>
    /\ UNCHANGED spurious

DWaitReturn(x) ==
    /\ TypeOK /\ rpc[x] = "wret" /\ wl = x
    /\ RetStop(x) /\ wl' = None
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, eofAt, parked, bl>>
    /\ UNCHANGED spurious

DDecideCopy(x) ==
    /\ TypeOK /\ rpc[x] = "decide" /\ bl = x /\ (avail >= K[x] \/ (closed /\ avail > 0))
    /\ left' = [left EXCEPT ![x] = Min(avail, K[x])] /\ Go(x, "copy") /\ UNCHANGED bl
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt, parked, wl>>
    /\ UNCHANGED spurious

DDecideBack(x) ==
    /\ TypeOK /\ rpc[x] = "decide" /\ bl = x /\ ~(avail >= K[x] \/ (closed /\ avail > 0))
    /\ Go(x, "start") /\ bl' = None /\ UNCHANGED left /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt, parked, wl>>
    /\ UNCHANGED spurious

DCopy(x) ==
    /\ TypeOK /\ rpc[x] = "copy" /\ bl = x /\ Buffered >= 1 /\ left[x] >= 1
    /\ hold' = [hold EXCEPT ![x] = @ + 1] /\ left' = [left EXCEPT ![x] = @ - 1]
    /\ Go(x, IF left[x] = 1 THEN "finish" ELSE "copy")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, cpc, op, calls, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DFinish(x) ==
    /\ TypeOK /\ rpc[x] = "finish" /\ bl = x
    /\ t' = t + hold[x] /\ avail' = avail - hold[x] /\ hold' = [hold EXCEPT ![x] = 0]
    /\ off' = IF off + hold[x] >= RecLen THEN off + hold[x] - RecLen ELSE off + hold[x]
    /\ bl' = None /\ EndStop(x)
    /\ UNCHANGED <<left, w, closed, wpc, cpc, wres, wclosed, eofAt, parked, wl>>
    /\ UNCHANGED spurious

DRet0(x) ==
    /\ TypeOK /\ rpc[x] = "ret0"
    /\ eofAt' = (IF eofAt = -1 THEN w ELSE eofAt) /\ EndStop(x)
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, hold, wres, wclosed, parked, wl, bl>>
    /\ UNCHANGED spurious

DWaitLock(x) ==
    /\ TypeOK /\ rpc[x] \in {"lockwait", "woken"} /\ wl = None
    /\ wl' = x /\ Go(x, IF rpc[x] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt, parked, bl>>
    /\ UNCHANGED spurious

DInc(x) ==
    /\ TypeOK /\ rpc[x] = "inc"
    /\ Go(x, "test")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DLock(x) ==
    /\ TypeOK /\ rpc[x] = "lock" /\ bl = None
    /\ bl' = x /\ Go(x, "decide")
    /\ UNCHANGED <<left, off, w, t, avail, closed, wpc, cpc, op, calls, hold, wres, wclosed, eofAt, parked, wl>>
    /\ UNCHANGED spurious

DWriteFail(i) ==
    /\ TypeOK /\ wpc[i] = "write" /\ bl = None /\ closed
    /\ WGo(i, "failed") /\ UNCHANGED <<w, avail>> /\ UNCHANGED <<off, t, closed, cpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DWriteDone(i) ==
    /\ TypeOK /\ wpc[i] = "write" /\ bl = None /\ ~closed /\ w >= Bytes
    /\ WGo(i, "done") /\ UNCHANGED <<w, avail>> /\ UNCHANGED <<off, t, closed, cpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DWriteAll(i) ==
    /\ TypeOK /\ wpc[i] = "write" /\ bl = None /\ ~closed /\ ~(w >= Bytes)
    /\ w' = Bytes /\ avail' = avail + (Bytes - w) /\ WGo(i, "siglock") /\ UNCHANGED <<off, t, closed, cpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DSigNone(i) ==
    /\ TypeOK /\ wpc[i] = "siglock" /\ parked = {}
    /\ UNCHANGED <<rpc, parked>> /\ WGo(i, WriterNext) /\ UNCHANGED <<off, w, t, avail, closed, cpc, op, calls, hold, left, wres, wclosed, eofAt, wl, bl>>
    /\ UNCHANGED spurious

DSigWake(i) ==
    /\ TypeOK /\ wpc[i] = "siglock" /\ parked # {} /\ wl = None
    /\ rpc' = [r \in Threads |-> IF r \in parked THEN "woken" ELSE rpc[r]] /\ parked' = {} /\ WGo(i, WriterNext)
    /\ UNCHANGED <<off, w, t, avail, closed, cpc, op, calls, hold, left, wres, wclosed, eofAt, wl, bl>>
    /\ UNCHANGED spurious

DClose(c) ==
    /\ TypeOK /\ cpc[c] = "close" /\ bl = None
    /\ closed' = TRUE /\ CGo(c, "siglock")
    /\ UNCHANGED <<off, w, t, avail, wpc, rpc, op, calls, hold, left, wres, wclosed, eofAt, parked, wl, bl>>
    /\ UNCHANGED spurious

DCSigNone(c) ==
    /\ TypeOK /\ cpc[c] = "siglock" /\ parked = {}
    /\ UNCHANGED <<rpc, parked>> /\ CGo(c, "done") /\ UNCHANGED <<off, w, t, avail, closed, wpc, op, calls, hold, left, wres, wclosed, eofAt, wl, bl>>
    /\ UNCHANGED spurious

DCSigWake(c) ==
    /\ TypeOK /\ cpc[c] = "siglock" /\ parked # {} /\ wl = None
    /\ rpc' = [r \in Threads |-> IF r \in parked THEN "woken" ELSE rpc[r]] /\ parked' = {} /\ CGo(c, "done")
    /\ UNCHANGED <<off, w, t, avail, closed, wpc, op, calls, hold, left, wres, wclosed, eofAt, wl, bl>>
    /\ UNCHANGED spurious

LEMMA DStartRetImpl == ASSUME NEW x \in Threads, DStartRet(x) PROVE ThreadStart(x)
  BY RetStopReturn, ConstAssump DEF DStartRet, ThreadStart, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DStartGoImpl == ASSUME NEW x \in Threads, DStartGo(x) PROVE ThreadStart(x)
  BY ConstAssump DEF DStartGo, ThreadStart, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DRereadRetImpl == ASSUME NEW x \in Threads, DRereadRet(x) PROVE ThreadReread(x)
  BY RetStopReturn, ConstAssump DEF DRereadRet, ThreadReread, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DRereadGoImpl == ASSUME NEW x \in Threads, DRereadGo(x) PROVE ThreadReread(x)
  BY ConstAssump DEF DRereadGo, ThreadReread, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DTestRetImpl == ASSUME NEW x \in Threads, DTestRet(x) PROVE ThreadTest(x)
  BY RetStopReturn, ConstAssump DEF DTestRet, ThreadTest, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DTestWretImpl == ASSUME NEW x \in Threads, DTestWret(x) PROVE ThreadTest(x)
  BY ConstAssump DEF DTestWret, ThreadTest, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DTestReadImpl == ASSUME NEW x \in Threads, DTestRead(x) PROVE ThreadTest(x)
  BY ConstAssump DEF DTestRead, ThreadTest, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DTestParkImpl == ASSUME NEW x \in Threads, DTestPark(x) PROVE ThreadTest(x)
  BY ConstAssump DEF DTestPark, ThreadTest, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DWaitReturnImpl == ASSUME NEW x \in Threads, DWaitReturn(x) PROVE ThreadWaitReturn(x)
  BY RetStopReturn, ConstAssump DEF DWaitReturn, ThreadWaitReturn, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DDecideCopyImpl == ASSUME NEW x \in Threads, DDecideCopy(x) PROVE ThreadDecide(x)
  BY ConstAssump DEF DDecideCopy, ThreadDecide, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DDecideBackImpl == ASSUME NEW x \in Threads, DDecideBack(x) PROVE ThreadDecide(x)
  BY ConstAssump DEF DDecideBack, ThreadDecide, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DCopyImpl == ASSUME NEW x \in Threads, DCopy(x) PROVE ThreadCopy(x)
  BY ConstAssump DEF DCopy, ThreadCopy, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DFinishImpl == ASSUME NEW x \in Threads, DFinish(x) PROVE ThreadFinish(x)
  BY EndStopCall, ConstAssump DEF DFinish, ThreadFinish, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DRet0Impl == ASSUME NEW x \in Threads, DRet0(x) PROVE ThreadRet0(x)
  BY EndStopCall, ConstAssump DEF DRet0, ThreadRet0, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DWaitLockImpl == ASSUME NEW x \in Threads, DWaitLock(x) PROVE ThreadWaitLock(x)
  BY ConstAssump DEF DWaitLock, ThreadWaitLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DIncImpl == ASSUME NEW x \in Threads, DInc(x) PROVE ThreadInc(x)
  BY ConstAssump DEF DInc, ThreadInc, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DLockImpl == ASSUME NEW x \in Threads, DLock(x) PROVE ThreadLock(x)
  BY ConstAssump DEF DLock, ThreadLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DWriteFailImpl == ASSUME NEW i \in Writers, DWriteFail(i) PROVE WriterWrite(i)
  BY ConstAssump DEF DWriteFail, WriterWrite, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DWriteDoneImpl == ASSUME NEW i \in Writers, DWriteDone(i) PROVE WriterWrite(i)
  BY ConstAssump DEF DWriteDone, WriterWrite, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DWriteAllImpl == ASSUME NEW i \in Writers, DWriteAll(i) PROVE WriterWrite(i)
  BY ConstAssump DEF DWriteAll, WriterWrite, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DSigNoneImpl == ASSUME NEW i \in Writers, DSigNone(i) PROVE WriterSigLock(i)
  BY ConstAssump DEF DSigNone, WriterSigLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DSigWakeImpl == ASSUME NEW i \in Writers, DSigWake(i) PROVE WriterSigLock(i)
  BY ConstAssump DEF DSigWake, WriterSigLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DCloseImpl == ASSUME NEW c \in Closers, DClose(c) PROVE CloserClose(c)
  BY ConstAssump DEF DClose, CloserClose, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DCSigNoneImpl == ASSUME NEW c \in Closers, DCSigNone(c) PROVE CloserSigLock(c)
  BY ConstAssump DEF DCSigNone, CloserSigLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

LEMMA DCSigWakeImpl == ASSUME NEW c \in Closers, DCSigWake(c) PROVE CloserSigLock(c)
  BY ConstAssump DEF DCSigWake, CloserSigLock, TypeOK, Go, WGo, CGo, WakeAll, WriterNext, Return, RetStop, EndStop, Want, Buffered, InFlight, Ops

\* ThreadStart: from the guard of DStartRet, a step of Next
LEMMA En1 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "start" /\ avail >= Want(x) /\ op[x] = "wait" PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DStartRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DStartRet, TypeOK, RetStop, Want, EndStop, Go, vars
  <1>2 <<DStartRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DStartRet(x)>>_vars => <<Next>>_vars
    BY DStartRetImpl DEF Next, ThreadStep, DStartRet
  <1>5 (ENABLED <<DStartRet(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadStart: from the guard of DStartGo, a step of Next
LEMMA En2 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "start" /\ ~(avail >= Want(x) /\ op[x] = "wait") PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DStartGo(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DStartGo, TypeOK, Go, Want, vars
  <1>2 <<DStartGo(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DStartGo(x)>>_vars => <<Next>>_vars
    BY DStartGoImpl DEF Next, ThreadStep, DStartGo
  <1>5 (ENABLED <<DStartGo(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadReread: from the guard of DRereadRet, a step of Next
LEMMA En3 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "reread" /\ op[x] = "wait" PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DRereadRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRereadRet, TypeOK, RetStop, EndStop, Go, vars
  <1>2 <<DRereadRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRereadRet(x)>>_vars => <<Next>>_vars
    BY DRereadRetImpl DEF Next, ThreadStep, DRereadRet
  <1>5 (ENABLED <<DRereadRet(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadReread: from the guard of DRereadGo, a step of Next
LEMMA En4 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "reread" /\ op[x] # "wait" PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DRereadGo(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRereadGo, TypeOK, Go, vars
  <1>2 <<DRereadGo(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRereadGo(x)>>_vars => <<Next>>_vars
    BY DRereadGoImpl DEF Next, ThreadStep, DRereadGo
  <1>5 (ENABLED <<DRereadGo(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadTest: from the guard of DTestRet, a step of Next
LEMMA En5 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ avail >= Want(x) /\ CheckedReturn PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DTestRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRet, TypeOK, RetStop, Want, EndStop, Go, vars
  <1>2 <<DTestRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRet(x)>>_vars => <<Next>>_vars
    BY DTestRetImpl DEF Next, ThreadStep, DTestRet
  <1>5 (ENABLED <<DTestRet(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadTest: from the guard of DTestWret, a step of Next
LEMMA En6 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ ~(avail >= Want(x)) /\ closed PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DTestWret(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestWret, TypeOK, Go, Want, vars
  <1>2 <<DTestWret(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestWret(x)>>_vars => <<Next>>_vars
    BY DTestWretImpl DEF Next, ThreadStep, DTestWret
  <1>5 (ENABLED <<DTestWret(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadTest: from the guard of DTestRead, a step of Next
LEMMA En7 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] # "wait" /\ (avail >= Want(x) \/ closed) PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DTestRead(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRead, TypeOK, Go, Want, vars
  <1>2 <<DTestRead(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRead(x)>>_vars => <<Next>>_vars
    BY DTestReadImpl DEF Next, ThreadStep, DTestRead
  <1>5 (ENABLED <<DTestRead(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadTest: from the guard of DTestPark, a step of Next
LEMMA En8 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ ~(avail >= Want(x) \/ closed) PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DTestPark(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestPark, TypeOK, Go, Want, vars
  <1>2 <<DTestPark(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestPark(x)>>_vars => <<Next>>_vars
    BY DTestParkImpl DEF Next, ThreadStep, DTestPark
  <1>5 (ENABLED <<DTestPark(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadWaitReturn: from the guard of DWaitReturn, a step of Next
LEMMA En9 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "wret" /\ wl = x PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DWaitReturn(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWaitReturn, TypeOK, RetStop, EndStop, Go, vars
  <1>2 <<DWaitReturn(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWaitReturn(x)>>_vars => <<Next>>_vars
    BY DWaitReturnImpl DEF Next, ThreadStep, DWaitReturn
  <1>5 (ENABLED <<DWaitReturn(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadDecide: from the guard of DDecideCopy, a step of Next
LEMMA En10 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ (avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DDecideCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideCopy, TypeOK, Go, Min, vars
  <1>2 <<DDecideCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideCopy(x)>>_vars => <<Next>>_vars
    BY DDecideCopyImpl DEF Next, ThreadStep, DDecideCopy
  <1>5 (ENABLED <<DDecideCopy(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadDecide: from the guard of DDecideBack, a step of Next
LEMMA En11 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ ~(avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DDecideBack(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideBack, TypeOK, Go, vars
  <1>2 <<DDecideBack(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideBack(x)>>_vars => <<Next>>_vars
    BY DDecideBackImpl DEF Next, ThreadStep, DDecideBack
  <1>5 (ENABLED <<DDecideBack(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadCopy: from the guard of DCopy, a step of Next
LEMMA En12 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "copy" /\ bl = x /\ Buffered >= 1 /\ left[x] >= 1 PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCopy, TypeOK, Go, Buffered, InFlight, vars
  <1>2 <<DCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCopy(x)>>_vars => <<Next>>_vars
    BY DCopyImpl DEF Next, ThreadStep, DCopy
  <1>5 (ENABLED <<DCopy(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadFinish: from the guard of DFinish, a step of Next
LEMMA En13 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "finish" /\ bl = x PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DFinish(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DFinish, TypeOK, EndStop, Go, vars
  <1>2 <<DFinish(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DFinish(x)>>_vars => <<Next>>_vars
    BY DFinishImpl DEF Next, ThreadStep, DFinish
  <1>5 (ENABLED <<DFinish(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadRet0: from the guard of DRet0, a step of Next
LEMMA En14 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "ret0" PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DRet0(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRet0, TypeOK, EndStop, Go, vars
  <1>2 <<DRet0(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRet0(x)>>_vars => <<Next>>_vars
    BY DRet0Impl DEF Next, ThreadStep, DRet0
  <1>5 (ENABLED <<DRet0(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadWaitLock: from the guard of DWaitLock, a step of Next
LEMMA En15 == ASSUME NEW x \in Threads, TypeOK, rpc[x] \in {"lockwait", "woken"} /\ wl = None PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DWaitLock(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWaitLock, TypeOK, Go, vars
  <1>2 <<DWaitLock(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWaitLock(x)>>_vars => <<Next>>_vars
    BY DWaitLockImpl DEF Next, ThreadStep, DWaitLock
  <1>5 (ENABLED <<DWaitLock(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadInc: from the guard of DInc, a step of Next
LEMMA En16 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "inc" PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DInc(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DInc, TypeOK, Go, vars
  <1>2 <<DInc(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DInc(x)>>_vars => <<Next>>_vars
    BY DIncImpl DEF Next, ThreadStep, DInc
  <1>5 (ENABLED <<DInc(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* ThreadLock: from the guard of DLock, a step of Next
LEMMA En17 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "lock" /\ bl = None PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DLock(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DLock, TypeOK, Go, vars
  <1>2 <<DLock(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DLock(x)>>_vars => <<Next>>_vars
    BY DLockImpl DEF Next, ThreadStep, DLock
  <1>5 (ENABLED <<DLock(x)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* WriterWrite: from the guard of DWriteFail, a step of Next
LEMMA En18 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "write" /\ bl = None /\ closed PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DWriteFail(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWriteFail, TypeOK, Go, WGo, vars
  <1>2 <<DWriteFail(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWriteFail(i)>>_vars => <<Next>>_vars
    BY DWriteFailImpl DEF Next, DWriteFail
  <1>5 (ENABLED <<DWriteFail(i)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* WriterWrite: from the guard of DWriteDone, a step of Next
LEMMA En19 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "write" /\ bl = None /\ ~closed /\ w >= Bytes PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DWriteDone(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWriteDone, TypeOK, Go, WGo, vars
  <1>2 <<DWriteDone(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWriteDone(i)>>_vars => <<Next>>_vars
    BY DWriteDoneImpl DEF Next, DWriteDone
  <1>5 (ENABLED <<DWriteDone(i)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* WriterWrite: from the guard of DWriteAll, a step of Next
LEMMA En20 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "write" /\ bl = None /\ ~closed /\ ~(w >= Bytes) PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DWriteAll(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWriteAll, TypeOK, Go, WGo, vars
  <1>2 <<DWriteAll(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWriteAll(i)>>_vars => <<Next>>_vars
    BY DWriteAllImpl DEF Next, DWriteAll
  <1>5 (ENABLED <<DWriteAll(i)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* WriterSigLock: from the guard of DSigNone, a step of Next
LEMMA En21 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "siglock" /\ parked = {} PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DSigNone(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DSigNone, TypeOK, Go, WGo, WriterNext, vars
  <1>2 <<DSigNone(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DSigNone(i)>>_vars => <<Next>>_vars
    BY DSigNoneImpl DEF Next, DSigNone
  <1>5 (ENABLED <<DSigNone(i)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* WriterSigLock: from the guard of DSigWake, a step of Next
LEMMA En22 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "siglock" /\ parked # {} /\ wl = None PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DSigWake(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DSigWake, TypeOK, Go, WGo, WriterNext, vars
  <1>2 <<DSigWake(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DSigWake(i)>>_vars => <<Next>>_vars
    BY DSigWakeImpl DEF Next, DSigWake
  <1>5 (ENABLED <<DSigWake(i)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* CloserClose: from the guard of DClose, a step of Next
LEMMA En23 == ASSUME NEW c \in Closers, TypeOK, cpc[c] = "close" /\ bl = None PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DClose(c)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DClose, TypeOK, Go, CGo, vars
  <1>2 <<DClose(c)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DClose(c)>>_vars => <<Next>>_vars
    BY DCloseImpl DEF Next, DClose
  <1>5 (ENABLED <<DClose(c)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* CloserSigLock: from the guard of DCSigNone, a step of Next
LEMMA En24 == ASSUME NEW c \in Closers, TypeOK, cpc[c] = "siglock" /\ parked = {} PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DCSigNone(c)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCSigNone, TypeOK, Go, CGo, vars
  <1>2 <<DCSigNone(c)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCSigNone(c)>>_vars => <<Next>>_vars
    BY DCSigNoneImpl DEF Next, DCSigNone
  <1>5 (ENABLED <<DCSigNone(c)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* CloserSigLock: from the guard of DCSigWake, a step of Next
LEMMA En25 == ASSUME NEW c \in Closers, TypeOK, cpc[c] = "siglock" /\ parked # {} /\ wl = None PROVE ENABLED <<Next>>_vars
  <1>1 ENABLED <<DCSigWake(c)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCSigWake, TypeOK, Go, CGo, vars
  <1>2 <<DCSigWake(c)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Next>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCSigWake(c)>>_vars => <<Next>>_vars
    BY DCSigWakeImpl DEF Next, DCSigWake
  <1>5 (ENABLED <<DCSigWake(c)>>_vars) => ENABLED <<Next>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* one of the guards holds until all are done
THEOREM Progress ==
  ASSUME SafeInv, (\E c \in Closers : cpc[c] = "done") => parked = {}, NC >= 1,
         ~(/\ \A i \in Writers : wpc[i] \in {"done", "failed"}
           /\ \A c \in Closers : cpc[c] = "done"
           /\ \A r \in Threads : rpc[r] = "done")
  PROVE ENABLED <<Next>>_vars
  <1> USE DEF SafeInv
  <1>0 TypeOK
    OBVIOUS
  \* a holder of bufferLock or waitLock can always go on
  <1>1 CASE bl # None
    <2>1 bl \in Threads /\ rpc[bl] \in {"decide", "copy", "finish"}
      BY <1>1 DEF TypeOK, BufLock
    <2>2 CASE rpc[bl] = "decide"
      BY <2>1, <2>2, <1>0, En10, En11
    <2>3 CASE rpc[bl] = "copy"
      <3>1 left[bl] >= 1
        BY <2>1, <2>3 DEF HoldLeft
      <3>2 Buffered >= left[bl]
        BY <2>1, <2>3 DEF CopyHasBytes
      <3>3 left[bl] \in Nat
        BY <2>1 DEF TypeOK
      <3>4 Buffered >= 1
        BY <3>1, <3>2, <3>3, <2>1, <1>0 DEF Buffered, InFlight, TypeOK
      <3> QED
        BY <2>1, <2>3, <3>4, <3>1, <1>0, En12
    <2>4 CASE rpc[bl] = "finish"
      BY <2>1, <2>4, <1>0, En13
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4
  <1>2 CASE bl = None /\ wl # None
    <2>1 wl \in Threads /\ rpc[wl] \in {"inc", "test", "wret"}
      BY <1>2 DEF TypeOK, WaitLockInv
    <2>2 CASE rpc[wl] = "inc"
      BY <2>1, <2>2, <1>0, En16
    <2>3 CASE rpc[wl] = "test"
      BY <2>1, <2>3, <1>0, ConstAssump, En5, En6, En7, En8
    <2>4 CASE rpc[wl] = "wret"
      BY <2>1, <2>4, <1>0, En9
    <2> QED
      BY <2>1, <2>2, <2>3, <2>4
  <1>3 CASE bl = None /\ wl = None
    <2>1 CASE \E i \in Writers : wpc[i] \notin {"done", "failed"}
      <3> PICK i \in Writers : wpc[i] \notin {"done", "failed"}
        BY <2>1
      <3>1 wpc[i] \in {"write", "siglock"}
        BY DEF TypeOK
      <3>2 CASE wpc[i] = "write"
        BY <3>2, <1>3, <1>0, En18, En19, En20
      <3>3 CASE wpc[i] = "siglock"
        BY <3>3, <1>3, <1>0, En21, En22
      <3> QED
        BY <3>1, <3>2, <3>3
    <2>2 CASE \E c \in Closers : cpc[c] # "done"
      <3> PICK c \in Closers : cpc[c] # "done"
        BY <2>2
      <3>1 cpc[c] \in {"close", "siglock"}
        BY DEF TypeOK
      <3>2 CASE cpc[c] = "close"
        BY <3>2, <1>3, <1>0, En23
      <3>3 CASE cpc[c] = "siglock"
        BY <3>3, <1>3, <1>0, En24, En25
      <3> QED
        BY <3>1, <3>2, <3>3
    <2>3 CASE /\ \A i \in Writers : wpc[i] \in {"done", "failed"}
              /\ \A c \in Closers : cpc[c] = "done"
      \* every closer is done, so nobody is parked, and some thread is not done
      <3>0 parked = {}
        <4>1 1 \in Closers
          BY DEF Closers
        <4> QED
          BY <2>3, <4>1
      <3> PICK x \in Threads : rpc[x] # "done"
        BY <2>3
      <3>a rpc[x] \in States \ {"done", "parked", "nsee"}
        BY <3>0 DEF TypeOK, ParkedInv, Safety, NoEmptyTake
      <3>1 CASE rpc[x] = "start"
        BY <3>1, <1>3, <1>0, En1, En2
      <3>2 CASE rpc[x] = "reread"
        BY <3>2, <1>3, <1>0, En3, En4
      <3>3 CASE rpc[x] = "ret0"
        BY <3>3, <1>3, <1>0, En14
      <3>4 CASE rpc[x] = "lockwait"
        BY <3>4, <1>3, <1>0, En15
      <3>5 CASE rpc[x] = "woken"
        BY <3>5, <1>3, <1>0, En15
      <3>6 CASE rpc[x] = "lock"
        BY <3>6, <1>3, <1>0, En17
      \* the states that hold a lock cannot occur with both locks free
      <3>7 CASE rpc[x] \in {"inc", "test", "wret", "decide", "copy", "finish"}
        BY <3>7, <1>3 DEF WaitLockInv, BufLock
      <3> QED
        BY <3>a, <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7 DEF States
    <2> QED
      BY <2>1, <2>2, <2>3
  <1> QED
    BY <1>1, <1>2, <1>3
=============================================================================
