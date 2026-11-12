\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

------------------------- MODULE StreamBufferCounters -------------------------
(***************************************************************************)
(* A counter abstraction of the read() configuration of StreamBuffer.tla   *)
(* (TODO roadmap A13): one writer of Bytes single-byte writes, a closer,   *)
(* readers 1..N calling read() until -1, the code since F278 (Condition,   *)
(* waitingReaders, re-check under bufferLock). The writer writes the bytes  *)
(* 1, 2, ... in order and the FIFO hands them out in order, so the byte     *)
(* sequences of StreamBuffer.tla reduce to counts: w written, t committed,  *)
(* hold[r] the byte reader r copied in its current hold of bufferLock.      *)
(* Bytes stays symbolic for Apalache, so the inductive invariant IndInv     *)
(* holds for every number of written bytes, with N readers fixed (inductive.sh). *)
(* RefineCounters.tla checks with TLC that StreamBuffer.tla refines it.     *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
    \* @type: Int;
    N,
    \* @type: Int;
    Bytes,
    \* @type: Bool;
    ReCheck

VARIABLES
    \* @type: Int;
    w,
    \* @type: Int;
    t,
    \* @type: Int;
    avail,
    \* @type: Bool;
    closed,
    \* @type: Str;
    wpc,
    \* @type: Str;
    cpc,
    \* @type: Int -> Str;
    rpc,
    \* @type: Int -> Int;
    hold,
    \* @type: Int;
    eofAt,
    \* @type: Int;
    waiters,
    \* @type: Set(Int);
    parked,
    \* @type: Int;
    wl,
    \* @type: Int;
    bl

vars == <<w, t, avail, closed, wpc, cpc, rpc, hold, eofAt, waiters, parked, wl, bl>>

Readers == 1..N
None == 0

\* Apalache: the constants of a check -- N readers, any number of bytes (Bytes symbolic)
ConstInit == N = 2 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = TRUE
ConstInit3 == N = 3 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = TRUE
ConstInit4 == N = 4 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = TRUE
ConstInit8 == N = 8 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = TRUE
ConstInit12 == N = 12 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = TRUE
\* the code before F278 (no re-check under bufferLock): IndInv is not inductive
ConstInitNoReCheck == N = 2 /\ Bytes \in Nat /\ Bytes >= 1 /\ ReCheck = FALSE

States == {"start", "reread", "lockwait", "inc", "test", "parked", "woken", "lock",
           "decide", "copy", "finish", "ret0", "done", "nsee"}

InFlight == IF bl = None THEN 0 ELSE hold[bl]
Buffered == w - t - InFlight

Init ==
    /\ w = 0 /\ t = 0 /\ avail = 0 /\ closed = FALSE
    /\ wpc = "write" /\ cpc = "close"
    /\ rpc = [r \in Readers |-> "start"] /\ hold = [r \in Readers |-> 0]
    /\ eofAt = -1 /\ waiters = 0 /\ parked = {} /\ wl = None /\ bl = None

WriterNext == IF w >= Bytes THEN "done" ELSE "write"

WakeAll ==
    /\ wl = None
    /\ rpc' = [r \in Readers |-> IF r \in parked THEN "woken" ELSE rpc[r]]
    /\ parked' = {}

WriterWrite ==
    /\ wpc = "write" /\ bl = None
    /\ IF closed
          THEN /\ wpc' = "failed" /\ UNCHANGED <<w, avail>>
          ELSE /\ w' = w + 1 /\ avail' = avail + 1 /\ wpc' = "sigread"
    /\ UNCHANGED <<t, closed, cpc, rpc, hold, eofAt, waiters, parked, wl, bl>>

WriterSigRead ==
    /\ wpc = "sigread"
    /\ wpc' = IF waiters # 0 THEN "siglock" ELSE WriterNext
    /\ UNCHANGED <<w, t, avail, closed, cpc, rpc, hold, eofAt, waiters, parked, wl, bl>>

WriterSigLock ==
    /\ wpc = "siglock" /\ WakeAll /\ wpc' = WriterNext
    /\ UNCHANGED <<w, t, avail, closed, cpc, hold, eofAt, waiters, wl, bl>>

CloserClose ==
    /\ cpc = "close" /\ bl = None /\ closed' = TRUE /\ cpc' = "sigread"
    /\ UNCHANGED <<w, t, avail, wpc, rpc, hold, eofAt, waiters, parked, wl, bl>>

CloserSigRead ==
    /\ cpc = "sigread" /\ cpc' = IF waiters # 0 THEN "siglock" ELSE "done"
    /\ UNCHANGED <<w, t, avail, closed, wpc, rpc, hold, eofAt, waiters, parked, wl, bl>>

CloserSigLock ==
    /\ cpc = "siglock" /\ WakeAll /\ cpc' = "done"
    /\ UNCHANGED <<w, t, avail, closed, wpc, hold, eofAt, waiters, wl, bl>>

Go(r, s) == rpc' = [rpc EXCEPT ![r] = s]

ReaderStart(r) ==
    /\ rpc[r] = "start"
    /\ Go(r, IF avail >= 1 THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, waiters, parked, wl, bl>>

ReaderReread(r) ==
    /\ rpc[r] = "reread" /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, waiters, parked, wl, bl>>

ReaderWaitLock(r) ==
    /\ rpc[r] \in {"lockwait", "woken"} /\ wl = None /\ wl' = r
    /\ Go(r, IF rpc[r] = "lockwait" THEN "inc" ELSE "test")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, waiters, parked, bl>>

ReaderInc(r) ==
    /\ rpc[r] = "inc" /\ waiters' = waiters + 1 /\ Go(r, "test")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, parked, wl, bl>>

ReaderTest(r) ==
    /\ rpc[r] = "test" /\ wl = r
    /\ IF avail >= 1 \/ closed
          THEN /\ waiters' = waiters - 1 /\ Go(r, IF avail >= 1 THEN "lock" ELSE "ret0")
               /\ UNCHANGED parked
          ELSE /\ parked' = parked \cup {r} /\ Go(r, "parked") /\ UNCHANGED waiters
    /\ wl' = None
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, bl>>

ReaderLock(r) ==
    /\ rpc[r] = "lock" /\ bl = None /\ bl' = r /\ Go(r, "decide")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, waiters, parked, wl>>

ReaderDecide(r) ==
    /\ rpc[r] = "decide" /\ bl = r
    /\ IF ~ReCheck
          THEN /\ Go(r, IF Buffered = 0 THEN "nsee" ELSE "copy") /\ UNCHANGED bl
          ELSE IF avail >= 1
                  THEN /\ Go(r, "copy") /\ UNCHANGED bl
                  ELSE /\ Go(r, "start") /\ bl' = None
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, eofAt, waiters, parked, wl>>

ReaderCopy(r) ==
    /\ rpc[r] = "copy" /\ bl = r /\ hold' = [hold EXCEPT ![r] = 1] /\ Go(r, "finish")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, eofAt, waiters, parked, wl, bl>>

ReaderFinish(r) ==
    /\ rpc[r] = "finish" /\ bl = r
    /\ t' = t + 1 /\ avail' = avail - 1 /\ hold' = [hold EXCEPT ![r] = 0]
    /\ bl' = None /\ Go(r, "start")
    /\ UNCHANGED <<w, closed, wpc, cpc, eofAt, waiters, parked, wl>>

ReaderRet0(r) ==
    /\ rpc[r] = "ret0" /\ eofAt' = (IF eofAt = -1 THEN w ELSE eofAt) /\ Go(r, "done")
    /\ UNCHANGED <<w, t, avail, closed, wpc, cpc, hold, waiters, parked, wl, bl>>

ReaderStep(r) ==
    \/ ReaderStart(r) \/ ReaderReread(r) \/ ReaderWaitLock(r) \/ ReaderInc(r)
    \/ ReaderTest(r) \/ ReaderLock(r) \/ ReaderDecide(r) \/ ReaderCopy(r)
    \/ ReaderFinish(r) \/ ReaderRet0(r)

Next ==
    \/ WriterWrite \/ WriterSigRead \/ WriterSigLock
    \/ CloserClose \/ CloserSigRead \/ CloserSigLock
    \/ \E r \in Readers : ReaderStep(r)

(* The behaviours, for the refinement check from StreamBuffer.tla *)
CSpec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Safety, as in StreamBuffer.tla *)
NoEmptyTake == \A r \in Readers : rpc[r] # "nsee"
AvailLinearizable == avail = w - t
NoWriteAfterEof == eofAt # -1 => w = eofAt
EofOnlyWhenClosedAndEmpty == eofAt # -1 => closed /\ Buffered = 0 /\ avail = 0
Safety == NoEmptyTake /\ AvailLinearizable /\ NoWriteAfterEof /\ EofOnlyWhenClosedAndEmpty

(* The inductive invariant *)
TypeOK ==
    /\ w \in Nat /\ w <= Bytes /\ t \in Nat /\ t <= w /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
    /\ cpc \in {"close", "sigread", "siglock", "done"}
    /\ rpc \in [Readers -> States] /\ hold \in [Readers -> {0, 1}]
    /\ eofAt \in Int /\ eofAt >= -1 /\ eofAt <= Bytes
    /\ waiters \in Nat /\ parked \subseteq Readers
    /\ wl \in 0..N /\ bl \in 0..N

IndInv ==
    /\ TypeOK
    /\ Safety
    \* bufferLock: held exactly by the reader deciding, copying or finishing
    /\ \A r \in Readers : (rpc[r] \in {"decide", "copy", "finish"}) <=> bl = r
    /\ \A r \in Readers : hold[r] = (IF rpc[r] = "finish" THEN 1 ELSE 0)
    /\ Buffered >= 0
    \* a reader copying has a byte to copy (the re-check under the lock)
    /\ \A r \in Readers : rpc[r] = "copy" => Buffered >= 1
    \* waitLock and the waiting machinery
    /\ \A r \in Readers : (rpc[r] \in {"inc", "test"}) <=> wl = r
    /\ parked = {r \in Readers : rpc[r] = "parked"}
    /\ waiters = Cardinality({r \in Readers : rpc[r] \in {"test", "parked", "woken"}})
    \* the end of the stream: only seen closed and empty, and no write follows a close
    /\ \A r \in Readers : rpc[r] = "reread" => closed
    /\ \A r \in Readers : rpc[r] = "ret0" => closed /\ avail = 0
    /\ \A r \in Readers : rpc[r] = "done" => eofAt # -1
    /\ (cpc = "close") <=> ~closed
    /\ (wpc = "write" => w < Bytes)
    /\ (wpc = "done" => w = Bytes)
    /\ (wpc = "sigread" => w >= 1)

(* Apalache: the initial predicate of the inductive step -- every variable assigned over its  *)
(* domain first, then IndInv as the constraint                                              *)
IndInit ==
    /\ w \in Nat /\ t \in Nat /\ avail \in Nat /\ closed \in BOOLEAN
    /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
    /\ cpc \in {"close", "sigread", "siglock", "done"}
    /\ rpc \in [Readers -> States] /\ hold \in [Readers -> {0, 1}]
    /\ eofAt \in Int /\ waiters \in Nat /\ parked \in SUBSET Readers
    /\ wl \in 0..N /\ bl \in 0..N
    /\ IndInv
=============================================================================
