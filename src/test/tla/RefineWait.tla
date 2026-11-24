\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------------- MODULE RefineWait -----------------------------
(* StreamBuffer.tla in its configurations with the current code (read() and  *)
(* read(b, 0, ReadLen) readers, waitForAtLeast callers, any write chunking)  *)
(* refines StreamBufferWait: every step of the detailed model is a step of   *)
(* the abstraction or a stuttering step. A reader of the detailed model     *)
(* makes read calls until -1, a waitForAtLeast caller one wait; the budget  *)
(* of further calls is the bytes not yet taken (each read before -1 takes   *)
(* at least one) plus one per thread not done (its -1 or its wait). TLC     *)
(* checks W!CSpec as a property of the detailed model.                      *)
EXTENDS StreamBuffer

\* A18: the finally block of the wait (ReaderWaitExit) is a step of the detailed model only: a
\* thread in it is where it goes next, and waitLock is free for the abstraction
MapPc(s) == IF s = "eof" THEN "ret0"
            ELSE IF s = "wexit" THEN "done"
            ELSE IF s = "wexitlock" THEN "lock"
            ELSE IF s = "wexitret0" THEN "ret0"
            ELSE s
MapWl == IF wl # None /\ rpc[wl] \in WaitExits THEN None ELSE wl
\* the abstraction has no waitingReaders: its writer and closer go straight to the signal
MapSig(s) == IF s = "sigread" THEN "siglock" ELSE s

W == INSTANCE StreamBufferWait WITH
        Threads <- Readers, None <- None, NW <- NW, NC <- NC, Bytes <- Bytes,
        K <- [r \in Readers |-> LenOf(r)], M <- [r \in Readers |-> ReadLen], RecLen <- ReadLen,
        Calls0 <- Bytes + Cardinality(Readers),
        CheckedReturn <- CheckedReturn, Spurious <- Spurious,
        w <- Len(written), t <- Len(taken), avail <- avail, closed <- closed,
        wpc <- [i \in Writers |-> MapSig(wpc[i])], cpc <- [c \in Closers |-> MapSig(cpc[c])],
        rpc <- [r \in Readers |-> MapPc(rpc[r])],
        op <- [r \in Readers |-> IF r \in WaitCallers THEN "wait" ELSE "read"],
        calls <- (Bytes - Len(taken)) + Cardinality({r \in Readers : MapPc(rpc[r]) # "done"}),
        hold <- [r \in Readers |-> Len(hold[r])],
        left <- left,
        off <- toff,
        wres <- wres, wclosed <- wclosed,
        eofAt <- eofAt,
        parked <- parked,
        wl <- MapWl, bl <- bl,
        spurious <- spurious

Refines == W!CSpec
=============================================================================
