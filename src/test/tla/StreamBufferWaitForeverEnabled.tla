\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------- MODULE StreamBufferWaitForeverEnabled -------------------
(***************************************************************************)
(* TLAPS proof (TODO, A13 follow-up): the actions of the fairness by role  *)
(* (StreamBufferWaitForeverLive.tla) are enabled where the liveness proof  *)
(* needs them: a thread r that waits for no lock, the holder of a lock, a  *)
(* signaler while a thread is parked and waitLock is free, a closer while  *)
(* bufferLock is free. The witnesses and guards are those of               *)
(* StreamBufferWaitEnabled.tla (lemmas En1 to En25), with the target       *)
(* action changed (generated: T, B, W, S and C before the En name). Kept   *)
(* apart from the proof that uses it, since expanding ENABLED in a context *)
(* that extends StreamBufferWaitLive.tla crashes tlapm 1.6.0-pre.          *)
(***************************************************************************)
EXTENDS StreamBufferWaitEnabled, StreamBufferWaitForeverRoles, TLAPS

\* the increment under waitLock, with the holder named (DInc has no lock in its guard)
DIncW(x) == wl = x /\ DInc(x)

LEMMA WEn16 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "inc" /\ wl = x PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DIncW(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DIncW, DInc, TypeOK, Go, vars
  <1>2 <<DIncW(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DIncW(x)>>_vars => <<WLHolder>>_vars
    BY DIncImpl DEF DIncW, WLHolder, ThreadStep
  <1>5 (ENABLED <<DIncW(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn1 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "start" /\ avail >= Want(x) /\ op[x] = "wait" PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DStartRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DStartRet, TypeOK, RetStop, Want, EndStop, Go, vars
  <1>2 <<DStartRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DStartRet(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DStartRetImpl DEF ThreadStep
  <1>5 (ENABLED <<DStartRet(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn2 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "start" /\ ~(avail >= Want(x) /\ op[x] = "wait") PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DStartGo(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DStartGo, TypeOK, Go, Want, vars
  <1>2 <<DStartGo(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DStartGo(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DStartGoImpl DEF ThreadStep
  <1>5 (ENABLED <<DStartGo(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn3 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "reread" /\ op[x] = "wait" PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DRereadRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRereadRet, TypeOK, RetStop, EndStop, Go, vars
  <1>2 <<DRereadRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRereadRet(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DRereadRetImpl DEF ThreadStep
  <1>5 (ENABLED <<DRereadRet(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn4 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "reread" /\ op[x] # "wait" PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DRereadGo(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRereadGo, TypeOK, Go, vars
  <1>2 <<DRereadGo(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRereadGo(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DRereadGoImpl DEF ThreadStep
  <1>5 (ENABLED <<DRereadGo(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn5 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ avail >= Want(x) /\ CheckedReturn PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DTestRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRet, TypeOK, RetStop, Want, EndStop, Go, vars
  <1>2 <<DTestRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRet(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DTestRetImpl DEF ThreadStep
  <1>5 (ENABLED <<DTestRet(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn6 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ ~(avail >= Want(x)) /\ closed PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DTestWret(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestWret, TypeOK, Go, Want, vars
  <1>2 <<DTestWret(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestWret(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DTestWretImpl DEF ThreadStep
  <1>5 (ENABLED <<DTestWret(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn7 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] # "wait" /\ (avail >= Want(x) \/ closed) PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DTestRead(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRead, TypeOK, Go, Want, vars
  <1>2 <<DTestRead(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRead(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DTestReadImpl DEF ThreadStep
  <1>5 (ENABLED <<DTestRead(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn8 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ ~(avail >= Want(x) \/ closed) PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DTestPark(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestPark, TypeOK, Go, Want, vars
  <1>2 <<DTestPark(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestPark(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DTestParkImpl DEF ThreadStep
  <1>5 (ENABLED <<DTestPark(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn9 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "wret" /\ wl = x PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DWaitReturn(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWaitReturn, TypeOK, RetStop, EndStop, Go, vars
  <1>2 <<DWaitReturn(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWaitReturn(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DWaitReturnImpl DEF ThreadStep
  <1>5 (ENABLED <<DWaitReturn(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn10 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ (avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DDecideCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideCopy, TypeOK, Go, Min, vars
  <1>2 <<DDecideCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideCopy(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DDecideCopyImpl DEF ThreadStep
  <1>5 (ENABLED <<DDecideCopy(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn11 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ ~(avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DDecideBack(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideBack, TypeOK, Go, vars
  <1>2 <<DDecideBack(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideBack(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DDecideBackImpl DEF ThreadStep
  <1>5 (ENABLED <<DDecideBack(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn12 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "copy" /\ bl = x /\ Buffered >= 1 /\ left[x] >= 1 PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCopy, TypeOK, Go, Buffered, InFlight, vars
  <1>2 <<DCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCopy(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DCopyImpl DEF ThreadStep
  <1>5 (ENABLED <<DCopy(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn13 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "finish" /\ bl = x PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DFinish(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DFinish, TypeOK, EndStop, Go, vars
  <1>2 <<DFinish(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DFinish(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DFinishImpl DEF ThreadStep
  <1>5 (ENABLED <<DFinish(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn14 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "ret0" PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DRet0(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DRet0, TypeOK, EndStop, Go, vars
  <1>2 <<DRet0(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DRet0(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DRet0Impl DEF ThreadStep
  <1>5 (ENABLED <<DRet0(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn15 == ASSUME NEW x \in Threads, TypeOK, rpc[x] \in {"lockwait", "woken"} /\ wl = None PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DWaitLock(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWaitLock, TypeOK, Go, vars
  <1>2 <<DWaitLock(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWaitLock(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DWaitLockImpl DEF ThreadStep
  <1>5 (ENABLED <<DWaitLock(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn16 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "inc" PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DInc(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DInc, TypeOK, Go, vars
  <1>2 <<DInc(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DInc(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DIncImpl DEF ThreadStep
  <1>5 (ENABLED <<DInc(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA TEn17 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "lock" /\ bl = None PROVE ENABLED <<ThreadStep(x)>>_vars
  <1>1 ENABLED <<DLock(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DLock, TypeOK, Go, vars
  <1>2 <<DLock(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<ThreadStep(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DLock(x)>>_vars => <<ThreadStep(x)>>_vars
    BY DLockImpl DEF ThreadStep
  <1>5 (ENABLED <<DLock(x)>>_vars) => ENABLED <<ThreadStep(x)>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA BEn10 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ (avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<BLHolder>>_vars
  <1>1 ENABLED <<DDecideCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideCopy, TypeOK, Go, Min, vars
  <1>2 <<DDecideCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<BLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideCopy(x)>>_vars => <<BLHolder>>_vars
    BY DDecideCopyImpl DEF BLHolder, ThreadStep, DDecideCopy
  <1>5 (ENABLED <<DDecideCopy(x)>>_vars) => ENABLED <<BLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA BEn11 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "decide" /\ bl = x /\ ~(avail >= K[x] \/ (closed /\ avail > 0)) PROVE ENABLED <<BLHolder>>_vars
  <1>1 ENABLED <<DDecideBack(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DDecideBack, TypeOK, Go, vars
  <1>2 <<DDecideBack(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<BLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DDecideBack(x)>>_vars => <<BLHolder>>_vars
    BY DDecideBackImpl DEF BLHolder, ThreadStep, DDecideBack
  <1>5 (ENABLED <<DDecideBack(x)>>_vars) => ENABLED <<BLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA BEn12 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "copy" /\ bl = x /\ Buffered >= 1 /\ left[x] >= 1 PROVE ENABLED <<BLHolder>>_vars
  <1>1 ENABLED <<DCopy(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCopy, TypeOK, Go, Buffered, InFlight, vars
  <1>2 <<DCopy(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<BLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCopy(x)>>_vars => <<BLHolder>>_vars
    BY DCopyImpl DEF BLHolder, ThreadStep, DCopy
  <1>5 (ENABLED <<DCopy(x)>>_vars) => ENABLED <<BLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA BEn13 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "finish" /\ bl = x PROVE ENABLED <<BLHolder>>_vars
  <1>1 ENABLED <<DFinish(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DFinish, TypeOK, EndStop, Go, vars
  <1>2 <<DFinish(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<BLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DFinish(x)>>_vars => <<BLHolder>>_vars
    BY DFinishImpl DEF BLHolder, ThreadStep, DFinish
  <1>5 (ENABLED <<DFinish(x)>>_vars) => ENABLED <<BLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA WEn5 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ avail >= Want(x) /\ CheckedReturn PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DTestRet(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRet, TypeOK, RetStop, Want, EndStop, Go, vars
  <1>2 <<DTestRet(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRet(x)>>_vars => <<WLHolder>>_vars
    BY DTestRetImpl DEF WLHolder, ThreadStep, DTestRet
  <1>5 (ENABLED <<DTestRet(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA WEn6 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] = "wait" /\ ~(avail >= Want(x)) /\ closed PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DTestWret(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestWret, TypeOK, Go, Want, vars
  <1>2 <<DTestWret(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestWret(x)>>_vars => <<WLHolder>>_vars
    BY DTestWretImpl DEF WLHolder, ThreadStep, DTestWret
  <1>5 (ENABLED <<DTestWret(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA WEn7 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ op[x] # "wait" /\ (avail >= Want(x) \/ closed) PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DTestRead(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestRead, TypeOK, Go, Want, vars
  <1>2 <<DTestRead(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestRead(x)>>_vars => <<WLHolder>>_vars
    BY DTestReadImpl DEF WLHolder, ThreadStep, DTestRead
  <1>5 (ENABLED <<DTestRead(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA WEn8 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "test" /\ wl = x /\ ~(avail >= Want(x) \/ closed) PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DTestPark(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DTestPark, TypeOK, Go, Want, vars
  <1>2 <<DTestPark(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DTestPark(x)>>_vars => <<WLHolder>>_vars
    BY DTestParkImpl DEF WLHolder, ThreadStep, DTestPark
  <1>5 (ENABLED <<DTestPark(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA WEn9 == ASSUME NEW x \in Threads, TypeOK, rpc[x] = "wret" /\ wl = x PROVE ENABLED <<WLHolder>>_vars
  <1>1 ENABLED <<DWaitReturn(x)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DWaitReturn, TypeOK, RetStop, EndStop, Go, vars
  <1>2 <<DWaitReturn(x)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<WLHolder>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DWaitReturn(x)>>_vars => <<WLHolder>>_vars
    BY DWaitReturnImpl DEF WLHolder, ThreadStep, DWaitReturn
  <1>5 (ENABLED <<DWaitReturn(x)>>_vars) => ENABLED <<WLHolder>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA SEn22 == ASSUME NEW i \in Writers, TypeOK, wpc[i] = "siglock" /\ parked # {} /\ wl = None PROVE ENABLED <<Signal>>_vars
  <1>1 ENABLED <<DSigWake(i)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DSigWake, TypeOK, Go, WGo, WriterNext, vars
  <1>2 <<DSigWake(i)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Signal>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DSigWake(i)>>_vars => <<Signal>>_vars
    BY DSigWakeImpl DEF Signal
  <1>5 (ENABLED <<DSigWake(i)>>_vars) => ENABLED <<Signal>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA SEn25 == ASSUME NEW c \in Closers, TypeOK, cpc[c] = "siglock" /\ parked # {} /\ wl = None PROVE ENABLED <<Signal>>_vars
  <1>1 ENABLED <<DCSigWake(c)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DCSigWake, TypeOK, Go, CGo, vars
  <1>2 <<DCSigWake(c)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Signal>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DCSigWake(c)>>_vars => <<Signal>>_vars
    BY DCSigWakeImpl DEF Signal
  <1>5 (ENABLED <<DCSigWake(c)>>_vars) => ENABLED <<Signal>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

LEMMA CEn23 == ASSUME NEW c \in Closers, TypeOK, cpc[c] = "close" /\ bl = None PROVE ENABLED <<Closing>>_vars
  <1>1 ENABLED <<DClose(c)>>_vars
    BY ConstAssump, ExpandENABLED, AutoUSE DEF DClose, TypeOK, Go, CGo, vars
  <1>2 <<DClose(c)>>_vars \in BOOLEAN
    OBVIOUS
  <1>3 <<Closing>>_vars \in BOOLEAN
    OBVIOUS
  <1>4 <<DClose(c)>>_vars => <<Closing>>_vars
    BY DCloseImpl DEF Closing
  <1>5 (ENABLED <<DClose(c)>>_vars) => ENABLED <<Closing>>_vars
    BY <1>2, <1>3, <1>4, ENABLEDaxioms
  <1> QED
    BY <1>1, <1>5

\* the stages in which r waits for no lock
RFree(x) ==
    \/ rpc[x] \in {"start", "reread", "ret0", "inc", "test", "wret", "decide", "copy", "finish"}
    \/ rpc[x] = "lock" /\ bl = None
    \/ rpc[x] \in {"lockwait", "woken"} /\ wl = None

THEOREM EnThread ==
  ASSUME SafeInv, NEW x \in Threads, RFree(x)
  PROVE ENABLED <<ThreadStep(x)>>_vars
  <1> USE DEF SafeInv
  <1>0 TypeOK /\ CheckedReturn
    BY ConstAssump
  <1>1 CASE rpc[x] = "start"
    BY <1>1, <1>0, TEn1, TEn2
  <1>2 CASE rpc[x] = "reread"
    BY <1>2, <1>0, TEn3, TEn4
  <1>3 CASE rpc[x] = "ret0"
    BY <1>3, <1>0, TEn14
  <1>4 CASE rpc[x] = "inc"
    BY <1>4, <1>0, TEn16
  <1>5 CASE rpc[x] = "test"
    <2>1 wl = x
      BY <1>5 DEF WaitLockInv
    <2> QED
      BY <1>5, <2>1, <1>0, TEn5, TEn6, TEn7, TEn8
  <1>6 CASE rpc[x] = "wret"
    <2>1 wl = x
      BY <1>6 DEF WaitLockInv
    <2> QED
      BY <1>6, <2>1, <1>0, TEn9
  <1>7 CASE rpc[x] = "decide"
    <2>1 bl = x
      BY <1>7 DEF BufLock
    <2> QED
      BY <1>7, <2>1, <1>0, TEn10, TEn11
  <1>8 CASE rpc[x] = "copy"
    <2>1 bl = x /\ left[x] >= 1 /\ Buffered >= left[x] /\ left[x] \in Nat
      BY <1>8 DEF BufLock, HoldLeft, CopyHasBytes, TypeOK
    <2>2 Buffered >= 1
      BY <2>1, <1>0 DEF Buffered, InFlight, TypeOK
    <2> QED
      BY <1>8, <2>1, <2>2, <1>0, TEn12
  <1>9 CASE rpc[x] = "finish"
    <2>1 bl = x
      BY <1>9 DEF BufLock
    <2> QED
      BY <1>9, <2>1, <1>0, TEn13
  <1>10 CASE rpc[x] = "lock" /\ bl = None
    BY <1>10, <1>0, TEn17
  <1>11 CASE rpc[x] \in {"lockwait", "woken"} /\ wl = None
    BY <1>11, <1>0, TEn15
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11 DEF RFree

\* the same with the ENABLED term behind an operator: tlapm does not instantiate a lemma at a
\* term inside ENABLED, but it does expand a definition applied to one
EnR(x) == ENABLED <<ThreadStep(x)>>_vars
THEOREM EnThreadR ==
  ASSUME SafeInv, NEW x \in Threads, RFree(x)
  PROVE EnR(x)
  BY EnThread DEF EnR

THEOREM EnBL ==
  ASSUME SafeInv, bl # None
  PROVE ENABLED <<BLHolder>>_vars
  <1> USE DEF SafeInv
  <1>0 TypeOK
    OBVIOUS
  <1>1 bl \in Threads /\ rpc[bl] \in {"decide", "copy", "finish"}
    BY DEF TypeOK, BufLock
  <1>2 CASE rpc[bl] = "decide"
    BY <1>1, <1>2, <1>0, BEn10, BEn11
  <1>3 CASE rpc[bl] = "copy"
    <2>1 left[bl] >= 1 /\ Buffered >= left[bl] /\ left[bl] \in Nat
      BY <1>1, <1>3 DEF HoldLeft, CopyHasBytes, TypeOK
    <2>2 Buffered >= 1
      BY <2>1, <1>0 DEF Buffered, InFlight, TypeOK
    <2> QED
      BY <1>1, <1>3, <2>1, <2>2, <1>0, BEn12
  <1>4 CASE rpc[bl] = "finish"
    BY <1>1, <1>4, <1>0, BEn13
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4

THEOREM EnWL ==
  ASSUME SafeInv, wl # None
  PROVE ENABLED <<WLHolder>>_vars
  <1> USE DEF SafeInv
  <1>0 TypeOK /\ CheckedReturn
    BY ConstAssump
  <1>1 wl \in Threads /\ rpc[wl] \in {"inc", "test", "wret"}
    BY DEF TypeOK, WaitLockInv
  <1>2 CASE rpc[wl] = "inc"
    BY <1>1, <1>2, <1>0, WEn16
  <1>3 CASE rpc[wl] = "test"
    BY <1>1, <1>3, <1>0, WEn5, WEn6, WEn7, WEn8
  <1>4 CASE rpc[wl] = "wret"
    BY <1>1, <1>4, <1>0, WEn9
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4

THEOREM EnSignal ==
  ASSUME SafeInv, parked # {}, wl = None,
         (\E i \in Writers : wpc[i] = "siglock") \/ (\E c \in Closers : cpc[c] = "siglock")
  PROVE ENABLED <<Signal>>_vars
  <1> USE DEF SafeInv
  <1>1 CASE \E i \in Writers : wpc[i] = "siglock"
    BY <1>1, SEn22
  <1>2 CASE \E c \in Closers : cpc[c] = "siglock"
    BY <1>2, SEn25
  <1> QED
    BY <1>1, <1>2

THEOREM EnClosing ==
  ASSUME SafeInv, bl = None, \E c \in Closers : cpc[c] = "close"
  PROVE ENABLED <<Closing>>_vars
  BY CEn23 DEF SafeInv
=============================================================================
