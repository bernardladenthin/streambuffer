\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------------- MODULE TraceGraph -----------------------------
(***************************************************************************)
(* Roadmap A18: every interleaving of the code is a run of the model, for  *)
(* a small scenario. JPF explores the instrumented class of A6 with state   *)
(* matching; its state graph, each transition labelled with the accesses   *)
(* it logged, is reduced to the minimal deterministic automaton over those *)
(* events (src/test/jpf/trace/graphmin.py): GEdges, from GInit. Its words  *)
(* are exactly the traces of all the interleavings JPF explored.           *)
(*                                                                         *)
(* This is the product of that automaton and the acceptance of a trace of  *)
(* TraceStreamBuffer.tla, used as it is: an edge of the automaton is       *)
(* chosen (Choose), the thread of its event takes up to K steps of the     *)
(* model (Silent), and the event must agree with the model's state         *)
(* (Consume, the same Obs). A word is accepted if some run of this product *)
(* consumes it. Whether every word is, is decided on the state graph TLC   *)
(* dumps of this product, by a subset construction over the words          *)
(* (src/test/jpf/trace/graphcheck.py); the model's choices are             *)
(* existential, so a state of the product with an edge it cannot consume   *)
(* is no counterexample by itself.                                         *)
(***************************************************************************)
EXTENDS TraceStreamBuffer

CONSTANTS
    GInit,      \* the automaton's initial state
    GEdge,      \* its edges, by id: [f: from, d: to, e: the event, a line of A6]
    GOut        \* for each of its states, the ids of the edges out of it

VARIABLES
    g,          \* the automaton's state
    pend        \* the id of the edge chosen to be consumed next, or -1

gvars == <<vars, l, k, g, pend>>

(* The tables through definitions of their own: TLC 1.7.4 evaluates a     *)
(* constant substituted in the cfg (GEdge <- TEdge) anew at every use, the *)
(* whole table at each step, but a definition of constant level once       *)
(* (tlaplus issue 648). check.sh counts the evaluations (ConstCacheGraph). *)
Edges == GEdge
Out == GOut

EdgeOf(i) == Edges[i]

GraphInit == Init /\ l = 1 /\ k = 0 /\ g = GInit /\ pend = -1

(* an edge out of the automaton's state *)
Choose ==
    /\ pend = -1
    /\ \E i \in Out[g] : pend' = i
    /\ UNCHANGED <<vars, l, k, g>>

(* a step of the model by the thread of the chosen edge's event *)
GSilent ==
    /\ pend # -1 /\ k < K
    /\ StepOf(EdgeOf(pend).e.t)
    /\ k' = k + 1
    /\ UNCHANGED <<l, g, pend>>

(* the event agrees with the model's state: the automaton moves *)
GConsume ==
    /\ pend # -1
    /\ Obs(EdgeOf(pend).e)
    /\ g' = EdgeOf(pend).d /\ pend' = -1 /\ k' = 0
    /\ UNCHANGED <<vars, l>>

GraphNext == Choose \/ GSilent \/ GConsume

GraphSpec == GraphInit /\ [][GraphNext]_gvars
=============================================================================
