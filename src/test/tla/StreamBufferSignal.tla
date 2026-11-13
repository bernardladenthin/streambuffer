\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------------- MODULE StreamBufferSignal ---------------------------
(***************************************************************************)
(* The "max 1 permit" release of one registered semaphore (addSignal,      *)
(* addTrimStartSignal, addTrimEndSignal; bug-hunt finding F280). Any       *)
(* number of signalers: every write, close or trim of the buffer, each on  *)
(* its own thread or nested in another one's release(), signals after its  *)
(* change; the observer acquires at any time and then looks at the buffer. *)
(* A release() may throw. The semaphores are independent, so one models    *)
(* them all.                                                               *)
(*                                                                         *)
(* Mode "none" is the code before F280: check for no permit, then release. *)
(* Mode "skip" was the first fix: check and claim in one step under        *)
(* signalLock, release outside it, drop the claim; a signaler that finds   *)
(* the claim leaves the release to the claimant. Mode "replay" is the      *)
(* code since: a signaler that finds the claim notes its signal, and the   *)
(* claimant, after its release, releases again if the note is there and    *)
(* the permit is gone (releaseMaxOnePermit).                               *)
(*                                                                         *)
(* Two properties: MaxOne (never more than one permit, the documented      *)
(* contract) and NoLostSignal (once no signaler is busy, a change the      *)
(* observer has not seen since its last acquire has a permit waiting for   *)
(* it; after a release that threw, a signal may be lost, as before F280).  *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    \* @type: Set(Str);
    Signalers,
    \* @type: Str;
    Mode

VARIABLES
    \* @type: Int;
    permits,
    \* @type: Bool;
    releasing,
    \* @type: Bool;
    noted,
    \* @type: Str -> Str;
    pc,
    \* ghost: a change the observer has not seen (set by a signal, cleared by an acquire)
    \* @type: Bool;
    fresh,
    \* ghost: a release threw
    \* @type: Bool;
    threw

vars == <<permits, releasing, noted, pc, fresh, threw>>

Init ==
    /\ permits = 0 /\ releasing = FALSE /\ noted = FALSE
    /\ pc = [s \in Signalers |-> "idle"] /\ fresh = FALSE /\ threw = FALSE

Go(s, l) == pc' = [pc EXCEPT ![s] = l]

\* a write, close or trim signals after its change
Check(s) ==
    /\ pc[s] = "idle"
    /\ fresh' = TRUE
    /\ IF Mode = "none"
          THEN /\ IF permits = 0 THEN Go(s, "release") ELSE UNCHANGED pc
               /\ UNCHANGED <<releasing, noted>>
          ELSE IF releasing
                  THEN /\ noted' = (Mode = "replay" \/ noted)
                       /\ UNCHANGED <<pc, releasing>>
                  ELSE IF permits = 0
                          THEN /\ releasing' = TRUE /\ Go(s, "release")
                               /\ UNCHANGED noted
                          ELSE UNCHANGED <<pc, releasing, noted>>
    /\ UNCHANGED <<permits, threw>>

\* release() adds the permit, or throws
Release(s) ==
    /\ pc[s] = "release"
    /\ \/ permits' = permits + 1 /\ Go(s, IF Mode = "none" THEN "idle" ELSE "clear")
          /\ UNCHANGED threw
       \/ threw' = TRUE /\ Go(s, IF Mode = "none" THEN "idle" ELSE "drop")
          /\ UNCHANGED permits
    /\ UNCHANGED <<releasing, noted, fresh>>

\* after a release: again if a signal was noted and the permit is gone, else drop the claim
Clear(s) ==
    /\ pc[s] = "clear"
    /\ noted' = FALSE
    /\ IF Mode = "replay" /\ noted /\ permits = 0
          THEN Go(s, "release") /\ UNCHANGED releasing
          ELSE releasing' = FALSE /\ Go(s, "idle")
    /\ UNCHANGED <<permits, fresh, threw>>

\* after a release that threw: drop the claim and the note
Drop(s) ==
    /\ pc[s] = "drop"
    /\ releasing' = FALSE /\ noted' = FALSE /\ Go(s, "idle")
    /\ UNCHANGED <<permits, fresh, threw>>

\* the observer takes a permit and looks at the buffer
Acquire ==
    /\ permits > 0 /\ permits' = permits - 1 /\ fresh' = FALSE
    /\ UNCHANGED <<releasing, noted, pc, threw>>

Next == Acquire \/ \E s \in Signalers : Check(s) \/ Release(s) \/ Clear(s) \/ Drop(s)

Spec == Init /\ [][Next]_vars

MaxOne == permits <= 1
Quiet == \A s \in Signalers : pc[s] = "idle"
NoLostSignal == ~threw /\ Quiet /\ fresh => permits >= 1

TypeOK ==
    /\ permits \in Nat /\ releasing \in BOOLEAN /\ noted \in BOOLEAN
    /\ pc \in [Signalers -> {"idle", "release", "clear", "drop"}]
    /\ fresh \in BOOLEAN /\ threw \in BOOLEAN

\* the inductive invariant of Mode "replay": at most one signaler between its claim and dropping
\* it, the claim set exactly then; no permit while it releases; a drop only after a throw; a note
\* only with a claim; and a
\* change the observer has not seen has a permit, or (during a release) the note or the release
\* still to come
Busy(s) == pc[s] \in {"release", "clear", "drop"}
Inv ==
    /\ TypeOK /\ MaxOne
    /\ releasing <=> \E s \in Signalers : Busy(s)
    /\ \A s, t \in Signalers : Busy(s) /\ Busy(t) => s = t
    /\ \A s \in Signalers : pc[s] = "release" => permits = 0
    /\ \A s \in Signalers : pc[s] = "drop" => threw
    /\ noted => releasing
    /\ ~threw /\ ~releasing /\ fresh => permits >= 1
    /\ \A s \in Signalers : ~threw /\ pc[s] = "clear" /\ fresh => permits >= 1 \/ noted
=============================================================================
