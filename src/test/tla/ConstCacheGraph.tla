\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE ConstCacheGraph ----------------------------
(***************************************************************************)
(* A regression check of check.sh, not a model: the tables of an automaton *)
(* of TraceGraph.tla come from the cfg (GEdge <- TEdge), and TLC 1.7.4     *)
(* evaluates such a constant anew at every use (tlaplus issue 648). Read  *)
(* at each step, the 5.7 MB table of S3A held TLC at ~1,000 states a       *)
(* minute; through a definition of its own (Edges, Out) it is evaluated    *)
(* once. Each evaluation of the tables here prints a line, and check.sh   *)
(* requires a few of them over hundreds of states.                        *)
(* Two edges of the S1A automaton out of its initial state.               *)
(***************************************************************************)
EXTENDS TraceGraph

TReaders == {"r1"}
TByteReaders == {"r1"}
TWaitCallers == {}
TBytes == 1
TChunkLen == 1
TReadLen == 1
TWriterName == <<"w">>
TCloserName == <<"c">>
TEmpty == <<>>
TInit == 0
TEdge == Print("ConstCache: TEdge evaluated", <<
    [i |-> 1, f |-> 0, d |-> 1, e |-> [t |-> "r1", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>]],
    [i |-> 2, f |-> 0, d |-> 2, e |-> [t |-> "w", m |-> "writeFromArray", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>]]
  >>)
TOut == Print("ConstCache: TOut evaluated", [s \in 0..2 |-> IF s = 0 THEN {1, 2} ELSE {}])
=============================================================================
