\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE ConstCacheTrace ----------------------------
(***************************************************************************)
(* A regression check of check.sh, not a model: the trace of               *)
(* TraceStreamBuffer.tla comes from the cfg (TraceLog <- TTrace), and TLC  *)
(* 1.7.4 evaluates such a constant anew at every use (tlaplus issue 648);  *)
(* through a definition of its own (Log) it is evaluated once. Each        *)
(* evaluation of the trace here prints a line, and check.sh requires a few *)
(* of them over hundreds of states. The lines of a writer's first steps.   *)
(***************************************************************************)
EXTENDS TraceStreamBuffer

TReaders == {"r1"}
TByteReaders == {"r1"}
TWaitCallers == {}
TBytes == 1
TChunkLen == 1
TReadLen == 1
TWriterName == <<"w">>
TCloserName == <<"c">>
TTrace == Print("ConstCache: TTrace evaluated", <<
    [t |-> "r1", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>],
    [t |-> "w", m |-> "writeFromArray", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>],
    [t |-> "w", m |-> "requireNonClosed", a |-> "getClosed", n |-> 0, v |-> 0, b |-> <<>>]
  >>)
=============================================================================
