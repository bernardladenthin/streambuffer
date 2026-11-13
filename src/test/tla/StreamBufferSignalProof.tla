\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------------- MODULE StreamBufferSignalProof -------------------------
(***************************************************************************)
(* TLAPS proof (bug-hunt finding F280): with the claim of the code since   *)
(* F280, a registered semaphore never holds more than one permit, for any  *)
(* number of signalers, also with releases that throw and an observer that *)
(* acquires at any time. Inv is an inductive invariant, so Spec => []MaxOne. *)
(***************************************************************************)
EXTENDS StreamBufferSignal, TLAPS

ASSUME ClaimAssump == Claim = TRUE

LEMMA InitInv == Init => Inv
  BY DEF Init, Inv, TypeOK, MaxOne, Busy

LEMMA StepInv == Inv /\ [Next]_vars => Inv'
  <1> SUFFICES ASSUME Inv, [Next]_vars PROVE Inv'
    OBVIOUS
  <1> USE ClaimAssump DEF Inv, TypeOK, MaxOne, Busy, Go
  <1>1 CASE Acquire
    BY <1>1 DEF Acquire
  <1>2 ASSUME NEW s \in Signalers, Check(s) PROVE Inv'
    BY <1>2 DEF Check
  <1>3 ASSUME NEW s \in Signalers, Release(s) PROVE Inv'
    BY <1>3 DEF Release
  <1>4 ASSUME NEW s \in Signalers, Clear(s) PROVE Inv'
    BY <1>4 DEF Clear
  <1>5 CASE UNCHANGED vars
    BY <1>5 DEF vars
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF Next

THEOREM MaxOnePermit == Spec => []MaxOne
  <1>1 Inv => MaxOne
    BY DEF Inv
  <1> QED
    BY InitInv, StepInv, <1>1, PTL DEF Spec
=============================================================================
