\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

--------------------------- MODULE RefineCounters ---------------------------
(* StreamBuffer.tla in its read() configuration refines StreamBufferCounters: *)
(* every step of the detailed model is a step of the counter abstraction or   *)
(* a stuttering step, under the mapping below. TLC checks C!CSpec as a        *)
(* property of the detailed model.                                            *)
EXTENDS StreamBuffer

N0 == Cardinality(Readers)
\* a fixed numbering of the reader model values
Idx == CHOOSE f \in [Readers -> 1..N0] : \A a, b \in Readers : a # b => f[a] # f[b]
Rd(i) == CHOOSE r \in Readers : Idx[r] = i
MapPc(s) == IF s = "eof" THEN "ret0" ELSE s
MapLock(x) == IF x = None THEN 0 ELSE Idx[x]

C == INSTANCE StreamBufferCounters WITH
        N <- N0, Bytes <- Bytes, ReCheck <- ReCheck,
        w <- Len(written), t <- Len(taken), avail <- avail, closed <- closed,
        wpc <- wpc, cpc <- cpc,
        rpc <- [i \in 1..N0 |-> MapPc(rpc[Rd(i)])],
        hold <- [i \in 1..N0 |-> Len(hold[Rd(i)])],
        eofAt <- eofAt, waiters <- waiters,
        parked <- {Idx[r] : r \in parked},
        wl <- MapLock(wl), bl <- MapLock(bl)

Refines == C!CSpec
=============================================================================
