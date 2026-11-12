\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE RefineRecords ----------------------------
(* StreamBuffer.tla in its record configurations (read(b, 0, ReadLen) by every *)
(* reader, any write chunking) refines StreamBufferRecords: every step of the  *)
(* detailed model is a step of the abstraction or a stuttering step. TLC       *)
(* checks R!CSpec as a property of the detailed model.                         *)
EXTENDS StreamBuffer

N0 == Cardinality(Readers)
Idx == CHOOSE f \in [Readers -> 1..N0] : \A a, b \in Readers : a # b => f[a] # f[b]
Rd(i) == CHOOSE r \in Readers : Idx[r] = i
MapPc(s) == IF s = "eof" THEN "ret0" ELSE s
\* the abstraction has no waitingReaders: its writer and closer go straight to the signal
MapSig(s) == IF s = "sigread" THEN "siglock" ELSE s
MapLock(x) == IF x = None THEN 0 ELSE Idx[x]

R == INSTANCE StreamBufferRecords WITH
        N <- N0, Bytes <- Bytes, K <- ReadLen, AtomicRead <- AtomicRead,
        w <- Len(written), t <- Len(taken), avail <- avail, closed <- closed,
        wpc <- MapSig(wpc), cpc <- MapSig(cpc),
        rpc <- [i \in 1..N0 |-> MapPc(rpc[Rd(i)])],
        hold <- [i \in 1..N0 |-> Len(hold[Rd(i)])],
        left <- [i \in 1..N0 |-> left[Rd(i)]],
        cur <- [i \in 1..N0 |-> Len(cur[Rd(i)])],
        off <- Len(taken) % ReadLen,
        eofAt <- eofAt,
        parked <- {Idx[r] : r \in parked},
        wl <- MapLock(wl), bl <- MapLock(bl)

Refines == R!CSpec
=============================================================================
