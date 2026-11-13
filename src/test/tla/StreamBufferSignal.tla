\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------------- MODULE StreamBufferSignal ---------------------------
(***************************************************************************)
(* The "max 1 permit" release of one registered semaphore (addSignal,      *)
(* addTrimStartSignal, addTrimEndSignal; bug-hunt finding F280). Any       *)
(* number of signalers: every write, close or trim of the buffer, each on  *)
(* its own thread or nested in another one's release(), signals; the       *)
(* observer acquires at any time. A release() may throw. The semaphores    *)
(* are independent, so one models them all.                                *)
(*                                                                         *)
(* Claim = TRUE is the code since F280 (releaseMaxOnePermit): under        *)
(* signalLock a signaler checks for no permit and claims the semaphore     *)
(* (releasingSignals) in one step, releases outside the lock, and drops    *)
(* the claim afterwards, also when release() throws. Claim = FALSE is the  *)
(* code before: the check, then the release.                               *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    \* @type: Set(Str);
    Signalers,
    \* @type: Bool;
    Claim

VARIABLES
    \* @type: Int;
    permits,
    \* @type: Bool;
    releasing,
    \* @type: Str -> Str;
    pc

vars == <<permits, releasing, pc>>

Init == permits = 0 /\ releasing = FALSE /\ pc = [s \in Signalers |-> "idle"]

Go(s, l) == pc' = [pc EXCEPT ![s] = l]

\* a write, close or trim signals: since F280 the check and the claim in one step under
\* signalLock (a signaler that finds a permit or a claim leaves the semaphore alone); before, the
\* check alone
Check(s) ==
    /\ pc[s] = "idle"
    /\ IF Claim
          THEN /\ permits = 0 /\ ~releasing
               /\ releasing' = TRUE /\ Go(s, "release")
          ELSE /\ permits = 0
               /\ Go(s, "release") /\ UNCHANGED releasing
    /\ UNCHANGED permits

\* release() adds the permit, or throws; then the claim is dropped (since F280)
Release(s) ==
    /\ pc[s] = "release"
    /\ \/ permits' = permits + 1
       \/ UNCHANGED permits
    /\ Go(s, IF Claim THEN "clear" ELSE "idle")
    /\ UNCHANGED releasing

Clear(s) ==
    /\ pc[s] = "clear"
    /\ releasing' = FALSE /\ Go(s, "idle")
    /\ UNCHANGED permits

\* the observer takes a permit
Acquire ==
    /\ permits > 0 /\ permits' = permits - 1
    /\ UNCHANGED <<releasing, pc>>

Next == Acquire \/ \E s \in Signalers : Check(s) \/ Release(s) \/ Clear(s)

Spec == Init /\ [][Next]_vars

\* the documented contract: never more than one permit
MaxOne == permits <= 1

TypeOK ==
    /\ permits \in Nat /\ releasing \in BOOLEAN
    /\ pc \in [Signalers -> {"idle", "release", "clear"}]

\* the inductive invariant of the code since F280: at most one signaler between its claim and
\* the end of its release, the claim set exactly then, and no permit while it releases
Busy(s) == pc[s] \in {"release", "clear"}
Inv ==
    /\ TypeOK /\ MaxOne
    /\ releasing <=> \E s \in Signalers : Busy(s)
    /\ \A s, t \in Signalers : Busy(s) /\ Busy(t) => s = t
    /\ \A s \in Signalers : pc[s] = "release" => permits = 0
=============================================================================
