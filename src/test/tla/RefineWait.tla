\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------------- MODULE RefineWait -----------------------------
(* StreamBuffer.tla in its waitForAtLeast configurations (read() readers next *)
(* to waitForAtLeast callers, any write chunking) refines StreamBufferWait:    *)
(* every step of the detailed model is a step of the abstraction or a          *)
(* stuttering step. TLC checks W!CSpec as a property of the detailed model.    *)
EXTENDS StreamBuffer

N0 == Cardinality(Readers)
NR0 == Cardinality(Readers \ WaitCallers)
\* a fixed numbering: the read() readers first (1..NR0), the waitForAtLeast callers after them
Idx == CHOOSE f \in [Readers -> 1..N0] :
          /\ \A a, b \in Readers : a # b => f[a] # f[b]
          /\ \A r \in Readers : f[r] <= NR0 <=> r \notin WaitCallers
Rd(i) == CHOOSE r \in Readers : Idx[r] = i
MapPc(s) == IF s = "eof" THEN "ret0" ELSE s
MapSig(s) == IF s = "sigread" THEN "siglock" ELSE s
MapLock(x) == IF x = None THEN 0 ELSE Idx[x]

W == INSTANCE StreamBufferWait WITH
        N <- N0, NR <- NR0, Bytes <- Bytes, M <- ReadLen, CheckedReturn <- CheckedReturn,
        w <- Len(written), t <- Len(taken), avail <- avail, closed <- closed,
        wpc <- MapSig(wpc), cpc <- MapSig(cpc),
        rpc <- [i \in 1..N0 |-> MapPc(rpc[Rd(i)])],
        hold <- [i \in 1..N0 |-> Len(hold[Rd(i)])],
        wres <- [i \in 1..N0 |-> wres[Rd(i)]],
        wclosed <- [i \in 1..N0 |-> wclosed[Rd(i)]],
        eofAt <- eofAt,
        parked <- {Idx[r] : r \in parked},
        wl <- MapLock(wl), bl <- MapLock(bl)

Refines == W!CSpec
=============================================================================
