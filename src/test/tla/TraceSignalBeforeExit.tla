\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------------- MODULE TraceSignalBeforeExit -------------------------
(***************************************************************************)
(* A regression check of check.sh: a word of A18's S6A automaton (an       *)
(* interleaving JPF explored), as a trace of TraceStreamBuffer.tla. r2's   *)
(* waitForAtLeast(2) finds the bytes in awaitAtLeast (line 10) and leaves   *)
(* the loop, the writer reads waitingReaders = 1 (line 29), only then r2's  *)
(* finally block lowers it (lines 30-31); r1 parks and the writer's        *)
(* signalAll wakes it (lines 37-40). The model lowered the count with the  *)
(* return, a step with the check, so it had either the signal skipped or   *)
(* r2 checking after r1 took the bytes, and accepted the word only with a  *)
(* spurious wake-up. The finally block is a step of its own                *)
(* (ReaderWaitExit), and the word is accepted without one (Spurious = 0 in *)
(* the cfg), with the counts equal (Values).                               *)
(***************************************************************************)
EXTENDS TraceStreamBuffer

TReaders == {"r1", "r2"}
TByteReaders == {"r1"}
TWaitCallers == {"r2"}
TBytes == 2
TChunkLen == 2
TReadLen == 2
TWriterName == <<"w">>
TCloserName == <<"c">>
TTrace == <<
  [t |-> "r2", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r2", m |-> "waitForAtLeast", a |-> "getClosed", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "writeFromArray", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "requireNonClosed", a |-> "getClosed", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "writeFromArray", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "writeFromArray", a |-> "putAvail", n |-> 0, v |-> 2, b |-> <<>>]
, [t |-> "r1", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 2, b |-> <<>>]
, [t |-> "r2", m |-> "awaitAtLeast", a |-> "wlock", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r2", m |-> "awaitAtLeast", a |-> "waitersInc", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r2", m |-> "awaitAtLeast", a |-> "getAvail", n |-> 0, v |-> 2, b |-> <<>>]
, [t |-> "w", m |-> "writeFromArray", a |-> "getAvail", n |-> 2, v |-> 2, b |-> <<>>]
, [t |-> "w", m |-> "shouldTrim", a |-> "getAvail", n |-> 0, v |-> 2, b |-> <<>>]
, [t |-> "w", m |-> "writeFromArray", a |-> "exit", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "getAvail", n |-> 0, v |-> 2, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "getAvail", n |-> 1, v |-> 2, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "putAvail", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "exit", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "", a |-> "ret", n |-> 1, v |-> 1, b |-> <<1>>]
, [t |-> "r1", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "enter", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "getAvail", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "getAvail", n |-> 1, v |-> 1, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "putAvail", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "readSingleByte", a |-> "exit", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "", a |-> "ret", n |-> 2, v |-> 1, b |-> <<2>>]
, [t |-> "r1", m |-> "waitForAtLeast", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "waitForAtLeast", a |-> "getClosed", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "signalModification", a |-> "waitersGet", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r2", m |-> "awaitAtLeast", a |-> "waitersDec", n |-> 1, v |-> 0, b |-> <<>>]
, [t |-> "r2", m |-> "awaitAtLeast", a |-> "wunlock", n |-> 1, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "wlock", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "waitersInc", n |-> 0, v |-> 1, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "getAvail", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "getClosed", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "park", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "signalModification", a |-> "wlock", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "signalModification", a |-> "signalAll", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "w", m |-> "signalModification", a |-> "wunlock", n |-> 0, v |-> 0, b |-> <<>>]
, [t |-> "r1", m |-> "awaitAtLeast", a |-> "unpark", n |-> 0, v |-> 0, b |-> <<>>]
>>
=============================================================================
