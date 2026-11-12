\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------------- MODULE RefineWaitProof ----------------------------
(***************************************************************************)
(* TLAPS proof (TODO roadmap A13): StreamBuffer.tla with the current code   *)
(* refines StreamBufferWait.tla under the mapping of RefineWait.tla, for   *)
(* ANY set of readers (TLC checks it for 2 and 3). Every step of the       *)
(* detailed model is a step of the abstraction or a stuttering step. The   *)
(* detailed invariant DInv needs no sum over the FIFO: the writer writes   *)
(* the bytes 1, 2, ... in order, so each entry is described by its first   *)
(* byte and its length, and the next entry starts where it ends. The       *)
(* abstraction's invariant, proved in StreamBufferWaitProof.tla, holds in  *)
(* the mapped state (WP!StepSafe) and gives the rest.                       *)
(***************************************************************************)
EXTENDS RefineWait, SequenceTheorems, StreamBufferCountLemmas, TLAPS

WP == INSTANCE StreamBufferWaitProof WITH
        Threads <- Readers, None <- None, NW <- 1, NC <- 1, Bytes <- Bytes,
        K <- [r \in Readers |-> LenOf(r)], M <- [r \in Readers |-> ReadLen], RecLen <- ReadLen,
        Calls0 <- Bytes + Cardinality(Readers),
        CheckedReturn <- CheckedReturn,
        w <- Len(written), t <- Len(taken), avail <- avail, closed <- closed,
        wpc <- [i \in 1..1 |-> MapSig(wpc)], cpc <- [c \in 1..1 |-> MapSig(cpc)],
        rpc <- [r \in Readers |-> MapPc(rpc[r])],
        op <- [r \in Readers |-> IF r \in WaitCallers THEN "wait" ELSE "read"],
        calls <- (Bytes - Len(taken)) + Cardinality({r \in Readers : rpc[r] # "done"}),
        hold <- [r \in Readers |-> Len(hold[r])],
        left <- left,
        off <- toff,
        wres <- wres, wclosed <- wclosed,
        eofAt <- eofAt,
        parked <- parked,
        wl <- wl, bl <- bl

\* the configuration of the current code; a finite set of readers, none of them None
ASSUME Current == Protocol = "condition" /\ ReCheck = TRUE /\ AtomicRead = TRUE
                  /\ CountOnce = TRUE /\ CheckedReturn = TRUE
ASSUME Extra == Bytes >= 1 /\ IsFiniteSet(Readers) /\ None \notin Readers

LEMMA CA == WP!ConstAssump
  BY SBAssump, Extra, Current, FS_CardinalityType DEF WP!ConstAssump, LenOf

-----------------------------------------------------------------------------
(* The detailed invariant *)
InLen == IF bl \in Readers THEN Len(hold[bl]) ELSE 0
WSet == {r \in Readers : rpc[r] \in {"test", "parked", "woken", "wret"}}
NotDone == {r \in Readers : rpc[r] # "done"}

\* the types, in parts that the actions change one by one
DTBuf == /\ buf \in Seq(Seq(Int)) /\ \A j \in 1..Len(buf) : buf[j] # <<>>
         /\ pos \in Nat /\ (buf # <<>> => pos < Len(Head(buf))) /\ (buf = <<>> => pos = 0)
DTSeq == written \in Seq(Int) /\ taken \in Seq(Int) /\ toff \in Nat
DTSca == /\ avail \in Nat /\ closed \in BOOLEAN /\ nextByte \in Nat /\ eofAt \in Int /\ waiters \in Nat
         /\ wpc \in {"write", "sigread", "siglock", "done", "failed"}
         /\ cpc \in {"close", "sigread", "siglock", "done"}
DTThr == /\ rpc \in [Readers -> ReaderStates \ {"acquire"}]
         /\ want \in [Readers -> Int] /\ left \in [Readers -> Nat]
         /\ hold \in [Readers -> Seq(Int)] /\ cur = [r \in Readers |-> <<>>]
         /\ wres \in [Readers -> Int] /\ wclosed \in [Readers -> BOOLEAN]
         /\ parked \subseteq Readers /\ wl \in Readers \cup {None} /\ bl \in Readers \cup {None}
DType == DTBuf /\ DTSeq /\ DTSca /\ DTThr
\* the writer has written the bytes 1 .. nextByte - 1
DWriter ==
    /\ Len(written) = nextByte - 1 /\ nextByte >= 1 /\ nextByte <= Bytes + 1
    /\ (wpc = "write" => nextByte <= Bytes)
\* the FIFO: each entry continues the one before, the last ends at nextByte, and the head starts,
\* past pos, with the byte after those committed and in flight
DBuf ==
    /\ \A j \in 1..(Len(buf) - 1) : buf[j + 1][1] = buf[j][1] + Len(buf[j])
    /\ buf # <<>> => buf[Len(buf)][1] + Len(buf[Len(buf)]) = nextByte
    /\ buf # <<>> => Head(buf)[1] + pos = Len(taken) + InLen + 1
    /\ buf = <<>> => Len(taken) + InLen = nextByte - 1
\* waitingReaders counts the threads between the increment and the return of the wait
DWait == waiters = Cardinality(WSet)
\* only the holder of bufferLock holds bytes
DHold == \A r \in Readers : r # bl => hold[r] = <<>>
\* the wait waits for the size of the call (AtomicRead)
DWant == \A r \in Readers : rpc[r] # "start" => want[r] = LenOf(r)

DInv == DType /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
Inv == DInv /\ WP!SafeInv

LEMMA FinReaders == IsFiniteSet(Readers) /\ Cardinality(Readers) \in Nat
  BY Extra, FS_CardinalityType

LEMMA FinSub == ASSUME NEW S, S \subseteq Readers PROVE IsFiniteSet(S) /\ Cardinality(S) \in Nat
                /\ Cardinality(S) <= Cardinality(Readers)
  BY FinReaders, FS_Subset, FS_CardinalityType

-----------------------------------------------------------------------------
LEMMA InitD == Init => DInv
  <1> SUFFICES ASSUME Init PROVE DInv
    OBVIOUS
  <1>1 WSet = {}
    BY DEF Init, WSet
  <1>2 DWait
    BY <1>1, FS_EmptySet DEF Init, DWait
  <1> QED
    BY <1>2, SBAssump, Extra DEF Init, DInv, DType, DTBuf, DTSeq, DTSca, DTThr, DWriter, DBuf, DHold, DWant, InLen, ReaderStates, None

LEMMA InitW == Init => WP!Init
  <1> SUFFICES ASSUME Init PROVE WP!Init
    OBVIOUS
  <1>1 NotDone = Readers
    BY DEF Init, NotDone
  <1>2 Len(taken) = 0 /\ Len(written) = 0
    BY DEF Init
  <1>3 [r \in Readers |-> IF r \in WaitCallers THEN "wait" ELSE "read"] \in [Readers -> WP!Ops]
    BY DEF WP!Ops
  <1> QED
    BY <1>1, <1>2, <1>3, SBAssump, Extra DEF Init, WP!Init, WP!Writers, WP!Closers, MapPc, MapSig, NotDone

-----------------------------------------------------------------------------
(* Helpers *)

\* the mapped variables
MRpc == [x \in Readers |-> MapPc(rpc[x])]
MHold == [x \in Readers |-> Len(hold[x])]
MOp == [x \in Readers |-> IF x \in WaitCallers THEN "wait" ELSE "read"]
MWpc == [i \in 1..1 |-> MapSig(wpc)]
MCpc == [i \in 1..1 |-> MapSig(cpc)]
MCalls == (Bytes - Len(taken)) + Cardinality(NotDone)
MBuffered == Len(written) - Len(taken) - (IF bl = None THEN 0 ELSE MHold[bl])

LEMMA FrDTBuf == ASSUME DTBuf, buf' = buf, pos' = pos PROVE DTBuf'
  BY DEF DTBuf

LEMMA FrDTSeq == ASSUME DTSeq, written' = written, taken' = taken, toff' = toff PROVE DTSeq'
  BY DEF DTSeq

LEMMA FrDTSca == ASSUME DTSca, avail' = avail, closed' = closed, nextByte' = nextByte, eofAt' = eofAt, waiters' = waiters, wpc' = wpc, cpc' = cpc PROVE DTSca'
  BY DEF DTSca

LEMMA FrDTThr == ASSUME DTThr, rpc' = rpc, want' = want, left' = left, hold' = hold, cur' = cur, wres' = wres, wclosed' = wclosed, parked' = parked, wl' = wl, bl' = bl PROVE DTThr'
  BY DEF DTThr

LEMMA FrDWriter == ASSUME DWriter, written' = written, nextByte' = nextByte, wpc' = wpc PROVE DWriter'
  BY DEF DWriter

LEMMA FrDBuf == ASSUME DBuf, buf' = buf, pos' = pos, taken' = taken, nextByte' = nextByte, hold' = hold, bl' = bl PROVE DBuf'
  BY DEF DBuf, InLen

LEMMA FrDWait == ASSUME DWait, waiters' = waiters, rpc' = rpc PROVE DWait'
  BY DEF DWait, WSet

LEMMA FrDHold == ASSUME DHold, hold' = hold, bl' = bl PROVE DHold'
  BY DEF DHold

LEMMA FrDWant == ASSUME DWant, rpc' = rpc, want' = want PROVE DWant'
  BY DEF DWant

LEMMA MOpConst == MOp' = MOp
  BY DEF MOp

LEMMA EmptyLen == ASSUME NEW s \in Seq(Int) PROVE (s = <<>>) <=> (Len(s) = 0)
  BY EmptySeq, LenProperties

LEMMA OneExcept == ASSUME NEW f, NEW x PROVE [[i \in 1..1 |-> f] EXCEPT ![1] = x] = [i \in 1..1 |-> x]
  OBVIOUS

\* the size a thread waits for, in both models
LEMMA WantSame == ASSUME NEW r \in Readers PROVE WP!Want(r) = LenOf(r) /\ WantNow(r) = LenOf(r) /\ LenOf(r) \in Nat
                                             /\ LenOf(r) >= 1 /\ LenOf(r) <= ReadLen
  BY SBAssump, Current DEF WP!Want, WantNow, LenOf, MOp

\* the chunk of a write
LEMMA ChunkFacts ==
  ASSUME nextByte \in Nat, nextByte >= 1, nextByte <= Bytes
  PROVE /\ Min(ChunkLen, Bytes - nextByte + 1) \in 1..Bytes
        /\ Min(ChunkLen, Bytes - nextByte + 1) <= Bytes - nextByte + 1
        /\ Chunk \in Seq(Int) /\ Len(Chunk) = Min(ChunkLen, Bytes - nextByte + 1)
        /\ Chunk # <<>> /\ Chunk[1] = nextByte
  <1> DEFINE m == Min(ChunkLen, Bytes - nextByte + 1)
  <1>1 m \in 1..Bytes /\ m <= Bytes - nextByte + 1
    BY SBAssump DEF Min
  <1>2 Chunk = [i \in 1..m |-> nextByte + i - 1]
    BY DEF Chunk
  <1>3 Chunk \in Seq(Int)
    <2>1 \A i \in 1..m : nextByte + i - 1 \in Int
      BY <1>1
    <2> QED
      BY <1>1, <1>2, <2>1, IsASeq
  <1>4 Len(Chunk) = m
    <2>1 DOMAIN Chunk = 1..m
      BY <1>2
    <2>2 DOMAIN Chunk = 1..Len(Chunk) /\ Len(Chunk) \in Nat
      BY <1>3, LenProperties
    <2> QED
      BY <1>1, <2>1, <2>2
  <1>5 Chunk # <<>> /\ Chunk[1] = nextByte
    BY <1>1, <1>3, <1>4, <1>2, EmptyLen
  <1> QED
    BY <1>1, <1>3, <1>4, <1>5

\* the mapped thread states after one thread changes its state
LEMMA MapGo ==
  ASSUME rpc \in [Readers -> ReaderStates], NEW r \in Readers, NEW s, rpc' = [rpc EXCEPT ![r] = s]
  PROVE MRpc' = [MRpc EXCEPT ![r] = MapPc(s)]
  BY DEF MRpc

\* the waiting set and the threads not done, when only thread r changes its state
LEMMA SetsGo ==
  ASSUME rpc \in [Readers -> ReaderStates], NEW r \in Readers, NEW s, rpc' = [rpc EXCEPT ![r] = s]
  PROVE /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF s \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
        /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF s # "done" THEN 1 ELSE 0)
        /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
  <1>1 WSet \subseteq Readers /\ WSet' \subseteq Readers /\ WSet \ {r} = WSet' \ {r}
       /\ (r \in WSet <=> rpc[r] \in {"test", "parked", "woken", "wret"})
       /\ (r \in WSet' <=> s \in {"test", "parked", "woken", "wret"})
    BY DEF WSet
  <1>2 NotDone \subseteq Readers /\ NotDone' \subseteq Readers /\ NotDone \ {r} = NotDone' \ {r}
       /\ (r \in NotDone <=> rpc[r] # "done") /\ (r \in NotDone' <=> s # "done")
    BY DEF NotDone
  <1>3 Cardinality(WSet') = Cardinality(WSet) - (IF r \in WSet THEN 1 ELSE 0) + (IF r \in WSet' THEN 1 ELSE 0)
    BY <1>1, FinReaders, SetExcept
  <1>4 Cardinality(NotDone') = Cardinality(NotDone) - (IF r \in NotDone THEN 1 ELSE 0) + (IF r \in NotDone' THEN 1 ELSE 0)
    BY <1>2, FinReaders, SetExcept
  <1>5 Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>1, <1>2, FinSub
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5

\* the writer's next state, in both models
LEMMA NextSame == ASSUME DWriter, nextByte \in Nat PROVE MapSig(WriterDone) = WP!WriterNext
  BY SBAssump DEF DWriter, WriterDone, WP!WriterNext, MapSig

\* with waitingReaders 0, nobody is parked
LEMMA NoWaiterNoParked ==
  ASSUME Inv, waiters = 0 PROVE parked = {}
  <1>1 WSet = {}
    BY FinSub, FS_EmptySet DEF Inv, DInv, DWait, WSet
  <1>2 \A x \in parked : rpc[x] = "parked"
    BY DEF Inv, WP!SafeInv, WP!ParkedInv, MapPc
  <1> QED
    BY <1>1, <1>2 DEF WSet, Inv, DInv, DType, DTThr

\* facts of the mapped abstract invariant in a state of Inv
LEMMA AbsFacts ==
  ASSUME Inv
  PROVE /\ Len(taken) \in Nat /\ Len(written) \in Nat /\ Len(taken) <= Len(written)
        /\ Len(written) <= Bytes /\ avail = Len(written) - Len(taken)
        /\ \A x \in Readers : Len(hold[x]) \in Nat /\ left[x] \in Nat
  BY LenProperties DEF Inv, WP!SafeInv, WP!TypeOK, WP!Safety, WP!AvailLinearizable, DInv, DType,
     DTSeq, DTThr

\* a call that ends with "done": the abstract EndCall, the budget down by one
LEMMA EndDone ==
  ASSUME Inv, NEW r \in Readers, rpc[r] # "done", rpc' = [rpc EXCEPT ![r] = "done"], taken' = taken
  PROVE WP!EndCall(r)
  <1>1 Cardinality(NotDone') = Cardinality(NotDone) - 1 /\ Cardinality(NotDone) \in Nat
    BY SetsGo DEF Inv, DInv, DType, DTThr, ReaderStates
  <1>2 Cardinality(NotDone) >= 1
    <2>1 r \in NotDone /\ IsFiniteSet(NotDone)
      BY FinSub DEF NotDone
    <2> QED
      BY <2>1, CardPos
  <1>3 Len(taken) \in Nat /\ Len(taken) <= Bytes
    BY AbsFacts, SBAssump
  <1>4 MCalls' = MCalls - 1 /\ MCalls - 1 \in 0..MCalls
    BY <1>1, <1>2, <1>3, SBAssump DEF MCalls
  <1>5 MOp[r] \in WP!Ops /\ MOp' = [MOp EXCEPT ![r] = MOp[r]]
    BY DEF MOp, WP!Ops
  <1>6 MRpc' = [MRpc EXCEPT ![r] = "done"]
    BY MapGo DEF Inv, DInv, DType, DTThr, MapPc
  <1> QED
    BY <1>4, <1>5, <1>6 DEF WP!EndCall, WP!Go, MCalls, MOp, MRpc, NotDone

\* a call that ends and the next starts: the abstract EndCall, the budget down by the bytes taken
LEMMA EndNext ==
  ASSUME Inv, NEW r \in Readers, rpc[r] # "done", rpc' = [rpc EXCEPT ![r] = "start"],
         NEW h \in Nat, h >= 1, Len(taken') = Len(taken) + h, Len(taken') <= Bytes
  PROVE WP!EndCall(r)
  <1>1 Cardinality(NotDone') = Cardinality(NotDone) /\ Cardinality(NotDone) \in Nat
    BY SetsGo DEF Inv, DInv, DType, DTThr, ReaderStates
  <1>3 Len(taken) \in Nat
    BY AbsFacts
  <1>4 MCalls' = MCalls - h /\ MCalls - h \in 0..MCalls /\ MCalls - h < MCalls
    BY <1>1, <1>3, SBAssump DEF MCalls
  <1>5 MOp[r] \in WP!Ops /\ MOp' = [MOp EXCEPT ![r] = MOp[r]]
    BY DEF MOp, WP!Ops
  <1>6 MRpc' = [MRpc EXCEPT ![r] = "start"]
    BY MapGo DEF Inv, DInv, DType, DTThr, MapPc
  <1> QED
    BY <1>4, <1>5, <1>6 DEF WP!EndCall, WP!Go, MCalls, MOp, MRpc, NotDone

LEMMA SWriterWrite == ASSUME Inv, WriterWrite PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g wpc = "write" /\ bl = None
    BY DEF WriterWrite
  <1>a CASE closed
    <2>1 wpc' = "failed" /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ cpc' = cpc /\ rpc' = rpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>a DEF WriterWrite, ReaderVars, Sync
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1 DEF DTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, FrDTThr
    <2>DWriter DWriter'
      BY <1>0, <2>1 DEF DWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, FrDWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, FrDWant
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>3 WP!WriterWrite(1)
      <3>1 MWpc' = [MWpc EXCEPT ![1] = "failed"] /\ MWpc[1] = "write"
        BY <2>1, <1>g, OneExcept DEF MWpc, MapSig
      <3>2 MRpc' = MRpc /\ MHold' = MHold /\ MCalls' = MCalls /\ MCpc' = MCpc
        BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
      <3> QED
        BY <1>a, <1>g, <2>1, <3>1, <3>2, MOpConst DEF WP!WriterWrite, WP!WGo, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <2>D, <2>3 DEF WP!Next, WP!Writers
  <1>b CASE ~closed
    <2> DEFINE m == Min(ChunkLen, Bytes - nextByte + 1)
    <2>0 nextByte \in Nat /\ nextByte >= 1 /\ nextByte <= Bytes
      BY <1>0, <1>g DEF DTSca, DWriter
    <2>c /\ m \in 1..Bytes /\ m <= Bytes - nextByte + 1
         /\ Chunk \in Seq(Int) /\ Len(Chunk) = m /\ Chunk # <<>> /\ Chunk[1] = nextByte
      BY <2>0, ChunkFacts
    <2>1 /\ buf' = Append(buf, Chunk) /\ written' = written \o Chunk /\ avail' = avail + m
         /\ nextByte' = nextByte + m /\ wpc' = "sigread"
         /\ pos' = pos /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ cpc' = cpc /\ rpc' = rpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>b, <2>c DEF WriterWrite, ReaderVars, Sync
    <2>3 /\ buf' \in Seq(Seq(Int)) /\ Len(buf') = Len(buf) + 1 /\ Len(buf) \in Nat
         /\ \A j \in 1..Len(buf) : buf'[j] = buf[j]
         /\ buf'[Len(buf) + 1] = Chunk
         /\ Head(buf') = (IF buf = <<>> THEN Chunk ELSE Head(buf)) /\ buf' # <<>>
         /\ (buf # <<>> <=> Len(buf) >= 1)
      <3>1 buf \in Seq(Seq(Int)) /\ Chunk \in Seq(Int)
        BY <2>c, <1>0 DEF DTBuf
      <3>2 /\ Append(buf, Chunk) \in Seq(Seq(Int)) /\ Append(buf, Chunk) # <<>>
           /\ Len(Append(buf, Chunk)) = Len(buf) + 1
           /\ \A j \in 1..Len(buf) : Append(buf, Chunk)[j] = buf[j]
           /\ Append(buf, Chunk)[Len(buf) + 1] = Chunk
        BY <3>1, AppendProperties
      <3>3 Head(Append(buf, Chunk)) = IF buf = <<>> THEN Chunk ELSE Head(buf)
        BY <3>1, HeadTailAppend
      <3>4 Len(buf) \in Nat /\ (buf # <<>> <=> Len(buf) >= 1)
        BY <3>1, LenProperties, EmptySeq
      <3>5 buf' \in Seq(Seq(Int)) /\ buf' # <<>>
        BY <3>2, <2>1
      <3>6 Len(buf') = Len(buf) + 1
        BY <3>2, <2>1
      <3>7 \A j \in 1..Len(buf) : buf'[j] = buf[j]
        BY <3>2, <2>1
      <3>8 buf'[Len(buf) + 1] = Chunk
        BY <3>2, <2>1
      <3>9 Head(buf') = IF buf = <<>> THEN Chunk ELSE Head(buf)
        BY <3>3, <2>1
      <3> QED
        BY <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, Zenon
    <2>4 written' \in Seq(Int) /\ Len(written') = Len(written) + m
      BY <2>c, <2>1, <1>0, ConcatProperties DEF DTSeq
    <2>DTBuf DTBuf'
      <3>1 \A j \in 1..Len(buf') : buf'[j] # <<>>
        BY <2>c, <2>3, <1>0 DEF DTBuf
      <3>2 pos' < Len(Head(buf'))
        BY <2>3, <2>c, <2>1, <1>0 DEF DTBuf
      <3> QED
        BY <2>1, <2>3, <3>1, <3>2, <1>0 DEF DTBuf
    <2>DTSeq DTSeq'
      BY <2>1, <2>4, <1>0 DEF DTSeq
    <2>DTSca DTSca'
      BY <2>1, <2>c, <1>0 DEF DTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, FrDTThr
    <2>DWriter DWriter'
      BY <2>1, <2>4, <2>c, <2>0, <1>0, SBAssump DEF DWriter
    <2>DBuf DBuf'
      <3>0 InLen' = InLen /\ taken' = taken /\ pos' = pos
        BY <2>1 DEF InLen
      <3>1 \A j \in 1..(Len(buf') - 1) : buf'[j + 1][1] = buf'[j][1] + Len(buf'[j])
        <4> SUFFICES ASSUME NEW j \in 1..(Len(buf') - 1) PROVE buf'[j + 1][1] = buf'[j][1] + Len(buf'[j])
          OBVIOUS
        <4>1 CASE j < Len(buf)
          BY <4>1, <2>3, <1>0 DEF DBuf
        <4>2 CASE j = Len(buf)
          BY <4>2, <2>3, <2>c, <1>0 DEF DBuf
        <4> QED
          BY <4>1, <4>2, <2>3
      <3>2 buf'[Len(buf')][1] + Len(buf'[Len(buf')]) = nextByte'
        BY <2>3, <2>c, <2>1
      <3>3 Head(buf')[1] + pos' = Len(taken') + InLen' + 1
        <4>1 CASE buf = <<>>
          BY <4>1, <3>0, <2>3, <2>c, <1>0 DEF DBuf, DTBuf
        <4>2 CASE buf # <<>>
          BY <4>2, <3>0, <2>3, <1>0 DEF DBuf
        <4> QED
          BY <4>1, <4>2
      <3> QED
        BY <3>1, <3>2, <3>3, <2>3 DEF DBuf
    <2>DWait DWait'
      BY <1>0, <2>1, FrDWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, FrDWant
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>9 WP!WriterWrite(1)
      <3>1 Len(written) = nextByte - 1 /\ Len(written) \in Nat
        BY <1>0, <2>0 DEF DWriter
      <3>2 \E c \in 1..Bytes : c <= Bytes - Len(written) /\ Len(written') = Len(written) + c
                                  /\ avail' = avail + c
        <4>1 m \in 1..Bytes /\ m <= Bytes - Len(written) /\ Len(written') = Len(written) + m
             /\ avail' = avail + m
          BY <3>1, <2>c, <2>4, <2>1, <2>0, SBAssump
        <4> QED
          BY <4>1
      <3>3 ~(Len(written) >= Bytes)
        BY <3>1, <2>0, SBAssump
      <3>4 MWpc' = [MWpc EXCEPT ![1] = "siglock"] /\ MWpc[1] = "write"
        BY <2>1, <1>g, OneExcept DEF MWpc, MapSig
      <3>5 MRpc' = MRpc /\ MHold' = MHold /\ MCalls' = MCalls /\ MCpc' = MCpc
        BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
      <3> QED
        BY <1>b, <1>g, <2>1, <3>2, <3>3, <3>4, <3>5, MOpConst DEF WP!WriterWrite, WP!WGo, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <2>D, <2>9 DEF WP!Next, WP!Writers
  <1> QED
    BY <1>a, <1>b

LEMMA SWriterSigRead == ASSUME Inv, WriterSigRead PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g wpc = "sigread"
    BY DEF WriterSigRead
  <1>1 wpc' = (IF waiters # 0 THEN "siglock" ELSE WriterDone) /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ cpc' = cpc /\ rpc' = rpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY Current DEF WriterSigRead, ReaderVars, Sync
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca, WriterDone
  <1>DTThr DTThr'
    BY <1>0, <1>1, FrDTThr
  <1>DWriter DWriter'
    BY <1>0, <1>1, SBAssump DEF DWriter, WriterDone, DTSca
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, FrDWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, FrDWant
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>3 CASE waiters # 0
    <2>1 MWpc' = MWpc /\ MRpc' = MRpc /\ MHold' = MHold /\ MCalls' = MCalls /\ MCpc' = MCpc
      BY <1>1, <1>3, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapSig
    <2>2 WP!vars' = WP!vars
      BY <1>1, <2>1, MOpConst DEF WP!vars, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <1>D, <2>2
  <1>4 CASE waiters = 0
    <2>0 wpc' = WriterDone
      BY <1>1, <1>4
    <2>1 parked = {}
      BY <1>4, NoWaiterNoParked
    <2>w UNCHANGED <<MRpc, parked>>
      BY <1>1 DEF MRpc
    <2>a MWpc[1] = "siglock"
      BY <1>g DEF MWpc, MapSig
    <2>b MWpc' = [MWpc EXCEPT ![1] = WP!WriterNext]
      <3>1 MapSig(wpc') = WP!WriterNext
        BY <2>0, NextSame, <1>0 DEF MapSig, DTSca
      <3> QED
        BY <3>1, OneExcept DEF MWpc
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MCpc' = MCpc
      BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>d WP!WriterSigLock(1)
      BY <1>1, <2>1, <2>a, <2>b, <2>c, <2>w, MOpConst DEF WP!WriterSigLock, WP!WGo, WP!WakeAll, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <1>D, <2>d DEF WP!Next, WP!Writers, WP!Closers
  <1> QED
    BY <1>3, <1>4

LEMMA SCloserSigRead == ASSUME Inv, CloserSigRead PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g cpc = "sigread"
    BY DEF CloserSigRead
  <1>1 cpc' = (IF waiters # 0 THEN "siglock" ELSE "done") /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ rpc' = rpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY Current DEF CloserSigRead, ReaderVars, Sync
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1, FrDTThr
  <1>DWriter DWriter'
    BY <1>0, <1>1, SBAssump DEF DWriter, WriterDone, DTSca
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, FrDWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, FrDWant
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>3 CASE waiters # 0
    <2>1 MCpc' = MCpc /\ MRpc' = MRpc /\ MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc
      BY <1>1, <1>3, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapSig
    <2>2 WP!vars' = WP!vars
      BY <1>1, <2>1, MOpConst DEF WP!vars, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <1>D, <2>2
  <1>4 CASE waiters = 0
    <2>0 cpc' = "done"
      BY <1>1, <1>4
    <2>1 parked = {}
      BY <1>4, NoWaiterNoParked
    <2>w UNCHANGED <<MRpc, parked>>
      BY <1>1 DEF MRpc
    <2>a MCpc[1] = "siglock"
      BY <1>g DEF MCpc, MapSig
    <2>b MCpc' = [MCpc EXCEPT ![1] = "done"]
      <3>1 MapSig(cpc') = "done"
        BY <2>0, <1>0 DEF MapSig, DTSca
      <3> QED
        BY <3>1, OneExcept DEF MCpc
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc
      BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>d WP!CloserSigLock(1)
      BY <1>1, <2>1, <2>a, <2>b, <2>c, <2>w, MOpConst DEF WP!CloserSigLock, WP!CGo, WP!WakeAll, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <1>D, <2>d DEF WP!Next, WP!Writers, WP!Closers
  <1> QED
    BY <1>3, <1>4

LEMMA SWriterSigLock == ASSUME Inv, WriterSigLock PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g wpc = "siglock" /\ wl = None
    BY DEF WriterSigLock, WakeAll
  <1>1 /\ rpc' = [x \in Readers |-> IF x \in parked THEN "woken" ELSE rpc[x]] /\ parked' = {}
       /\ wpc' = WriterDone /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ wl' = wl /\ bl' = bl
    BY DEF WriterSigLock, WakeAll
  <1>p \A x \in parked : rpc[x] = "parked"
    BY DEF Inv, WP!SafeInv, WP!ParkedInv, MapPc
  <1>w WSet' = WSet
    BY <1>1, <1>p DEF WSet
  <1>q NotDone' = NotDone
    BY <1>1, <1>p DEF NotDone
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca, WriterDone
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, SBAssump DEF DWriter, WriterDone, DTSca
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>w DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>p DEF DWant
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>2 WP!WakeAll
    <2>1 CASE parked = {}
      <3>1 rpc' = rpc
        BY <1>1, <2>1, <1>0 DEF DTThr
      <3> QED
        BY <2>1, <3>1, <1>1 DEF WP!WakeAll, MRpc
    <2>2 CASE parked # {}
      <3>1 MRpc' = [x \in Readers |-> IF x \in parked THEN "woken" ELSE MRpc[x]]
        BY <1>1 DEF MRpc, MapPc
      <3> QED
        BY <2>2, <3>1, <1>g, <1>1 DEF WP!WakeAll, MRpc
    <2> QED
      BY <2>1, <2>2
  <1>a MWpc[1] = "siglock"
    BY <1>g DEF MWpc, MapSig
  <1>b MWpc' = [MWpc EXCEPT ![1] = WP!WriterNext]
    <2>1 MapSig(wpc') = WP!WriterNext
      BY <1>1, NextSame, <1>0 DEF MapSig, DTSca
    <2> QED
      BY <2>1, OneExcept DEF MWpc
  <1>c MHold' = MHold /\ MCalls' = MCalls /\ MCpc' = MCpc
    BY <1>1, <1>q DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>d WP!WriterSigLock(1)
    BY <1>1, <1>2, <1>a, <1>b, <1>c, MOpConst DEF WP!WriterSigLock, WP!WGo, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1> QED
    BY <1>D, <1>d DEF WP!Next, WP!Writers, WP!Closers

LEMMA SCloserSigLock == ASSUME Inv, CloserSigLock PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g cpc = "siglock" /\ wl = None
    BY DEF CloserSigLock, WakeAll
  <1>1 /\ rpc' = [x \in Readers |-> IF x \in parked THEN "woken" ELSE rpc[x]] /\ parked' = {}
       /\ cpc' = "done" /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ wl' = wl /\ bl' = bl
    BY DEF CloserSigLock, WakeAll
  <1>p \A x \in parked : rpc[x] = "parked"
    BY DEF Inv, WP!SafeInv, WP!ParkedInv, MapPc
  <1>w WSet' = WSet
    BY <1>1, <1>p DEF WSet
  <1>q NotDone' = NotDone
    BY <1>1, <1>p DEF NotDone
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, SBAssump DEF DWriter, WriterDone, DTSca
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>w DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>p DEF DWant
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>2 WP!WakeAll
    <2>1 CASE parked = {}
      <3>1 rpc' = rpc
        BY <1>1, <2>1, <1>0 DEF DTThr
      <3> QED
        BY <2>1, <3>1, <1>1 DEF WP!WakeAll, MRpc
    <2>2 CASE parked # {}
      <3>1 MRpc' = [x \in Readers |-> IF x \in parked THEN "woken" ELSE MRpc[x]]
        BY <1>1 DEF MRpc, MapPc
      <3> QED
        BY <2>2, <3>1, <1>g, <1>1 DEF WP!WakeAll, MRpc
    <2> QED
      BY <2>1, <2>2
  <1>a MCpc[1] = "siglock"
    BY <1>g DEF MCpc, MapSig
  <1>b MCpc' = [MCpc EXCEPT ![1] = "done"]
    <2>1 MapSig(cpc') = "done"
      BY <1>1, <1>0 DEF MapSig, DTSca
    <2> QED
      BY <2>1, OneExcept DEF MCpc
  <1>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc
    BY <1>1, <1>q DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>d WP!CloserSigLock(1)
    BY <1>1, <1>2, <1>a, <1>b, <1>c, MOpConst DEF WP!CloserSigLock, WP!CGo, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1> QED
    BY <1>D, <1>d DEF WP!Next, WP!Writers, WP!Closers

LEMMA SCloserClose == ASSUME Inv, CloserClose PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g cpc = "close" /\ bl = None
    BY DEF CloserClose
  <1>1 closed' = TRUE /\ cpc' = "sigread" /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ nextByte' = nextByte /\ wpc' = wpc /\ rpc' = rpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY DEF CloserClose, ReaderVars, Sync
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1, FrDTThr
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, FrDWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, FrDWant
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>2 MCpc' = [MCpc EXCEPT ![1] = "siglock"] /\ MCpc[1] = "close"
    BY <1>1, <1>g, OneExcept DEF MCpc, MapSig
  <1>3 MRpc' = MRpc /\ MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>4 WP!CloserClose(1)
    BY <1>g, <1>1, <1>2, <1>3, MOpConst DEF WP!CloserClose, WP!CGo, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1> QED
    BY <1>D, <1>4 DEF WP!Next, WP!Closers

LEMMA SReaderLock == ASSUME Inv, NEW r \in Readers, ReaderLock(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "lock" /\ bl = None
    BY DEF ReaderLock
  <1>1 rpc' = [rpc EXCEPT ![r] = "decide"] /\ bl' = r /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl
    BY Current DEF ReaderLock, Goto, Shared, ReaderVars, Sync
  <1>m MRpc' = [MRpc EXCEPT ![r] = "decide"]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF "decide" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF "decide" # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, FrDTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    <2>1 hold[r] = <<>>
      BY <1>0, <1>g, Extra DEF DHold
    <2>2 InLen' = InLen
      BY <2>1, <1>1, <1>g, Extra DEF InLen
    <2> QED
      BY <1>0, <1>1, <2>2 DEF DBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, <1>g, Extra DEF DHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>cn Cardinality(NotDone') = Cardinality(NotDone)
    BY <1>n, <1>g
  <1>cc MCalls' = MCalls
    BY <1>1, <1>cn DEF MCalls

  <1>s WP!ThreadLock(r)
    BY <1>g, <1>1, <1>m, <1>c, <1>cc, MOpConst, WantSame DEF WP!ThreadLock, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderInc == ASSUME Inv, NEW r \in Readers, ReaderInc(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "inc"
    BY DEF ReaderInc
  <1>1 rpc' = [rpc EXCEPT ![r] = "test"] /\ waiters' = waiters + 1 /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY Current DEF ReaderInc, Goto, Shared, ReaderVars, Sync
  <1>m MRpc' = [MRpc EXCEPT ![r] = "test"]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF "test" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF "test" # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1 DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>cn Cardinality(NotDone') = Cardinality(NotDone)
    BY <1>n, <1>g
  <1>cc MCalls' = MCalls
    BY <1>1, <1>cn DEF MCalls

  <1>s WP!ThreadInc(r)
    BY <1>g, <1>1, <1>m, <1>c, <1>cc, MOpConst, WantSame DEF WP!ThreadInc, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderWaitLock == ASSUME Inv, NEW r \in Readers, ReaderWaitLock(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] \in {"lockwait", "woken"} /\ wl = None
    BY DEF ReaderWaitLock
  <1>1 rpc' = [rpc EXCEPT ![r] = (IF rpc[r] = "lockwait" THEN "inc" ELSE "test")] /\ wl' = r /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ bl' = bl
    BY Current DEF ReaderWaitLock, Goto, Shared, ReaderVars, Sync
  <1>m MRpc' = [MRpc EXCEPT ![r] = (IF MRpc[r] = "lockwait" THEN "inc" ELSE "test")]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF (IF rpc[r] = "lockwait" THEN "inc" ELSE "test") \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF (IF rpc[r] = "lockwait" THEN "inc" ELSE "test") # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, FrDTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1, <1>g DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>cn Cardinality(NotDone') = Cardinality(NotDone)
    BY <1>n, <1>g
  <1>cc MCalls' = MCalls
    BY <1>1, <1>cn DEF MCalls

  <1>s WP!ThreadWaitLock(r)
    BY <1>g, <1>1, <1>m, <1>c, <1>cc, MOpConst, WantSame DEF WP!ThreadWaitLock, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderRet0 == ASSUME Inv, NEW r \in Readers, ReaderRet0(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "ret0" /\ cur[r] = <<>>
    BY <1>0 DEF ReaderRet0, DTThr
  <1>1 rpc' = [rpc EXCEPT ![r] = "eof"] /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY <1>g DEF ReaderRet0, Goto, Shared, Sync
  <1>m MRpc' = [MRpc EXCEPT ![r] = "ret0"]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF "eof" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF "eof" # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, FrDTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>s WP!vars' = WP!vars
    <2>1 MRpc' = MRpc
      BY <1>m, <1>g, <1>0 DEF MRpc, MapPc, DTThr
    <2>2 MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <1>1, <1>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2> QED
      BY <1>1, <2>1, <2>2, MOpConst DEF WP!vars, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1> QED
    BY <1>D, <1>s

LEMMA SReaderEof == ASSUME Inv, NEW r \in Readers, ReaderEof(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "eof"
    BY DEF ReaderEof
  <1>1 rpc' = [rpc EXCEPT ![r] = "done"] /\ eofAt' = (IF eofAt = -1 THEN Len(written) ELSE eofAt)
       /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY DEF ReaderEof, Goto, Shared, ReaderVars, Sync
  <1>m MRpc' = [MRpc EXCEPT ![r] = "done"]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF "done" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF "done" # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, LenProperties DEF DTSca, DTSeq
  <1>DTThr DTThr'
    BY <1>0, <1>1 DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>e WP!EndCall(r)
    BY <1>1, <1>g, EndDone
  <1>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>s WP!ThreadRet0(r)
    BY <1>g, <1>1, <1>c, <1>e, MOpConst DEF WP!ThreadRet0, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderWaitReturn == ASSUME Inv, NEW r \in Readers, ReaderWaitReturn(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "wret" /\ wl = r
    BY DEF ReaderWaitReturn
  <1>1 /\ rpc' = [rpc EXCEPT ![r] = "done"] /\ wres' = [wres EXCEPT ![r] = avail]
       /\ wclosed' = [wclosed EXCEPT ![r] = closed] /\ waiters' = waiters - 1 /\ wl' = None
       /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ eofAt' = eofAt /\ permits' = permits /\ parked' = parked /\ bl' = bl
    BY DEF ReaderWaitReturn, Return, Goto, Shared
  <1>m MRpc' = [MRpc EXCEPT ![r] = "done"]
    BY <1>0, <1>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                + (IF "done" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
       /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                   + (IF "done" # "done" THEN 1 ELSE 0)
       /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
    BY <1>0, <1>1, SetsGo DEF DTThr, ReaderStates
  <1>w waiters >= 1
    <2>1 r \in WSet /\ IsFiniteSet(WSet)
      BY <1>g, FinSub DEF WSet
    <2> QED
      BY <2>1, CardPos, <1>0 DEF DWait
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, <1>w DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1, Extra DEF DTThr, DTSca, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    BY <1>0, <1>1, FrDBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n, <1>g DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, FrDHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>e WP!EndCall(r)
    BY <1>1, <1>g, EndDone
  <1>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>s WP!ThreadWaitReturn(r)
    BY <1>g, <1>1, <1>c, <1>e, MOpConst DEF WP!ThreadWaitReturn, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderStart == ASSUME Inv, NEW r \in Readers, ReaderStart(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "start"
    BY DEF ReaderStart
  <1>a CASE avail >= LenOf(r) /\ r \in WaitCallers
    <2>1 /\ rpc' = [rpc EXCEPT ![r] = "done"] /\ wres' = [wres EXCEPT ![r] = avail]
         /\ wclosed' = [wclosed EXCEPT ![r] = closed] /\ want' = [want EXCEPT ![r] = WantNow(r)]
         /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>a, WantSame, Current DEF ReaderStart, Return, Goto, Shared, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "done"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "done" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "done" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, WantSame, Extra DEF DTThr, DTSca, ReaderStates, WantNow
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g, WantSame DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>e WP!EndCall(r)
      BY <2>1, <1>g, EndDone
    <2>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadStart(r)
      BY <1>g, <1>a, <2>1, <2>c, <2>e, MOpConst, WantSame DEF WP!ThreadStart, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>b CASE ~(avail >= LenOf(r) /\ r \in WaitCallers)
    <2>1 /\ rpc' = [rpc EXCEPT ![r] = (IF avail >= LenOf(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")] /\ want' = [want EXCEPT ![r] = WantNow(r)]
         /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>b, WantSame, Current DEF ReaderStart, Goto, Shared, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = (IF avail >= LenOf(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait")]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF (IF avail >= LenOf(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait") \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF (IF avail >= LenOf(r) THEN "lock" ELSE IF closed THEN "reread" ELSE "lockwait") # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, WantSame, Extra DEF DTThr, DTSca, ReaderStates, WantNow
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g, WantSame DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>cn Cardinality(NotDone') = Cardinality(NotDone)
      BY <2>n, <1>g, <1>b
    <2>cc MCalls' = MCalls
      BY <2>1, <2>cn DEF MCalls
    <2>s WP!ThreadStart(r)
      BY <1>g, <1>b, <2>1, <2>m, <2>c, <2>cc, MOpConst, WantSame, Current DEF WP!ThreadStart, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1> QED
    BY <1>a, <1>b

LEMMA SReaderReread == ASSUME Inv, NEW r \in Readers, ReaderReread(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "reread"
    BY DEF ReaderReread
  <1>a CASE r \in WaitCallers
    <2>1 /\ rpc' = [rpc EXCEPT ![r] = "done"] /\ wres' = [wres EXCEPT ![r] = avail]
         /\ wclosed' = [wclosed EXCEPT ![r] = closed] 
         /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>a, WantSame, Current DEF ReaderReread, Return, Goto, Shared, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "done"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "done" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "done" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, WantSame, Extra DEF DTThr, DTSca, ReaderStates, WantNow
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g, WantSame DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>e WP!EndCall(r)
      BY <2>1, <1>g, EndDone
    <2>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadReread(r)
      BY <1>g, <1>a, <2>1, <2>c, <2>e, MOpConst, WantSame DEF WP!ThreadReread, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>b CASE ~(r \in WaitCallers)
    <2>1 /\ rpc' = [rpc EXCEPT ![r] = (IF avail >= 1 THEN "lock" ELSE "ret0")] 
         /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>b, WantSame, Current DEF ReaderReread, Goto, Shared, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = (IF avail >= 1 THEN "lock" ELSE "ret0")]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF (IF avail >= 1 THEN "lock" ELSE "ret0") \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF (IF avail >= 1 THEN "lock" ELSE "ret0") # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, WantSame, Extra DEF DTThr, DTSca, ReaderStates, WantNow
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g, WantSame DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>cn Cardinality(NotDone') = Cardinality(NotDone)
      BY <2>n, <1>g, <1>b
    <2>cc MCalls' = MCalls
      BY <2>1, <2>cn DEF MCalls
    <2>s WP!ThreadReread(r)
      BY <1>g, <1>b, <2>1, <2>m, <2>c, <2>cc, MOpConst, WantSame, Current DEF WP!ThreadReread, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1> QED
    BY <1>a, <1>b

\* the abstract invariant, per thread, in the detailed state
LEMMA HoldLeftR ==
  ASSUME Inv, NEW x \in Readers
  PROVE /\ rpc[x] \notin {"copy", "finish"} => Len(hold[x]) = 0 /\ left[x] = 0
        /\ rpc[x] = "copy" => left[x] >= 1
        /\ rpc[x] = "finish" => left[x] = 0 /\ Len(hold[x]) >= 1
        /\ rpc[x] \in {"copy", "finish"} => Len(hold[x]) + left[x] <= LenOf(x)
  BY DEF Inv, WP!SafeInv, WP!HoldLeft, MapPc

LEMMA CopyHasR ==
  ASSUME Inv, NEW x \in Readers, rpc[x] = "copy"
  PROVE MBuffered >= left[x]
  BY DEF Inv, WP!SafeInv, WP!CopyHasBytes, WP!Buffered, WP!InFlight, MBuffered, MHold, MapPc

LEMMA BufNonNegR == ASSUME Inv PROVE MBuffered >= 0
  BY DEF Inv, WP!SafeInv, WP!BufNonNeg, WP!Buffered, WP!InFlight, MBuffered, MHold

LEMMA BufferedSame == WP!Buffered = MBuffered
  BY DEF WP!Buffered, WP!InFlight, MBuffered, MHold

LEMMA SReaderTest == ASSUME Inv, NEW r \in Readers, ReaderTest(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "test" /\ wl = r /\ want[r] = LenOf(r)
    BY <1>0 DEF ReaderTest, DWant, DTThr
  <1>w waiters >= 1
    <2>1 r \in WSet /\ IsFiniteSet(WSet)
      BY <1>g, FinSub DEF WSet
    <2> QED
      BY <2>1, CardPos, <1>0 DEF DWait
  <1>T1 CASE (avail >= LenOf(r) \/ closed) /\ r \in WaitCallers /\ avail >= LenOf(r)
    <2>1 rpc' = [rpc EXCEPT ![r] = "done"] /\ wres' = [wres EXCEPT ![r] = avail] /\ wclosed' = [wclosed EXCEPT ![r] = closed] /\ waiters' = waiters - 1 /\ wl' = None /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ eofAt' = eofAt /\ permits' = permits /\ parked' = parked /\ bl' = bl
      BY <1>T1, <1>g, Current DEF ReaderTest, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "done"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "done" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "done" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, <1>w DEF DTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, Extra DEF DTThr, DTSca, ReaderStates
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>e WP!EndCall(r)
      BY <2>1, <1>g, EndDone
    <2>c MHold' = MHold /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadTest(r)
      BY <1>g, <1>T1, <2>1, <2>m, <2>c, <2>e, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadTest, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>T2 CASE (avail >= LenOf(r) \/ closed) /\ r \in WaitCallers /\ ~(avail >= LenOf(r))
    <2>1 rpc' = [rpc EXCEPT ![r] = "wret"]  /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>T2, <1>g, Current DEF ReaderTest, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "wret"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "wret" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "wret" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1 DEF DTThr, ReaderStates
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadTest(r)
      BY <1>g, <1>T2, <2>1, <2>m, <2>c, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadTest, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>T3 CASE (avail >= LenOf(r) \/ closed) /\ r \notin WaitCallers
    <2>1 rpc' = [rpc EXCEPT ![r] = (IF avail >= 1 THEN "lock" ELSE "ret0")] /\ waiters' = waiters - 1 /\ wl' = None /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ parked' = parked /\ bl' = bl
      BY <1>T3, <1>g, Current DEF ReaderTest, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = (IF avail >= 1 THEN "lock" ELSE "ret0")]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF (IF avail >= 1 THEN "lock" ELSE "ret0") \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF (IF avail >= 1 THEN "lock" ELSE "ret0") # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, <1>w DEF DTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, Extra DEF DTThr, ReaderStates
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadTest(r)
      BY <1>g, <1>T3, <2>1, <2>m, <2>c, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadTest, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>T4 CASE ~(avail >= LenOf(r) \/ closed)
    <2>1 rpc' = [rpc EXCEPT ![r] = "parked"] /\ parked' = parked \cup {r} /\ wl' = None /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ bl' = bl
      BY <1>T4, <1>g, Current DEF ReaderTest, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "parked"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "parked" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "parked" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, Extra DEF DTThr, ReaderStates
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadTest(r)
      BY <1>g, <1>T4, <2>1, <2>m, <2>c, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadTest, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1> QED
    BY <1>T1, <1>T2, <1>T3, <1>T4

LEMMA SReaderDecide == ASSUME Inv, NEW r \in Readers, ReaderDecide(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "decide" /\ bl = r
    BY DEF ReaderDecide
  <1>z Len(hold[r]) = 0 /\ hold[r] = <<>> /\ left[r] = 0
    <2>1 Len(hold[r]) = 0 /\ left[r] = 0
      BY <1>g, HoldLeftR
    <2> QED
      BY <2>1, EmptyLen, <1>0 DEF DTThr
  <1>D1 CASE avail >= LenOf(r) \/ (closed /\ avail > 0)
    <2>1 rpc' = [rpc EXCEPT ![r] = "copy"] /\ left' = [left EXCEPT ![r] = Min(avail, LenOf(r))] /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
      BY <1>D1, <1>g, Current DEF ReaderDecide, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "copy"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "copy" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "copy" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1, WantSame DEF DTThr, DTSca, ReaderStates, Min
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      BY <1>0, <2>1, FrDBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, FrDHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadDecide(r)
      BY <1>g, <1>D1, <2>1, <2>m, <2>c, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadDecide, WP!Min, Min, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1>D2 CASE ~(avail >= LenOf(r) \/ (closed /\ avail > 0))
    <2>1 rpc' = [rpc EXCEPT ![r] = "start"] /\ bl' = None /\ buf' = buf /\ pos' = pos /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ hold' = hold /\ left' = left /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl
      BY <1>D2, <1>g, Current DEF ReaderDecide, Return, Goto, Shared, ReaderVars, Sync
    <2>m MRpc' = [MRpc EXCEPT ![r] = "start"]
      BY <1>0, <2>1, <1>g, MapGo DEF DTThr, ReaderStates, MapPc, MRpc
    <2>n /\ Cardinality(WSet') = Cardinality(WSet) - (IF rpc[r] \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
                                  + (IF "start" \in {"test", "parked", "woken", "wret"} THEN 1 ELSE 0)
         /\ Cardinality(NotDone') = Cardinality(NotDone) - (IF rpc[r] # "done" THEN 1 ELSE 0)
                                     + (IF "start" # "done" THEN 1 ELSE 0)
         /\ Cardinality(WSet) \in Nat /\ Cardinality(NotDone) \in Nat
      BY <1>0, <2>1, SetsGo DEF DTThr, ReaderStates
    <2>DTBuf DTBuf'
      BY <1>0, <2>1, FrDTBuf
    <2>DTSeq DTSeq'
      BY <1>0, <2>1, FrDTSeq
    <2>DTSca DTSca'
      BY <1>0, <2>1, FrDTSca
    <2>DTThr DTThr'
      BY <1>0, <2>1 DEF DTThr, ReaderStates
    <2>DWriter DWriter'
      BY <1>0, <2>1, FrDWriter
    <2>DBuf DBuf'
      <3>1 InLen' = 0 /\ InLen = 0
        BY <2>1, <1>g, <1>z, Extra DEF InLen
      <3> QED
        BY <1>0, <2>1, <3>1 DEF DBuf
    <2>DWait DWait'
      BY <1>0, <2>1, <2>n, <1>g DEF DWait
    <2>DHold DHold'
      BY <1>0, <2>1, <1>z, <1>g DEF DHold
    <2>DWant DWant'
      BY <1>0, <2>1, <1>g DEF DWant, DTThr
    <2>D DInv'
      BY <2>DTBuf, <2>DTSeq, <2>DTSca, <2>DTThr, <2>DWriter, <2>DBuf, <2>DWait, <2>DHold, <2>DWant DEF DInv, DType
    <2>c MHold' = MHold /\ MCalls' = MCalls /\ MWpc' = MWpc /\ MCpc' = MCpc
      BY <2>1, <2>n, <1>g DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
    <2>s WP!ThreadDecide(r)
      BY <1>g, <1>D2, <2>1, <2>m, <2>c, MOpConst, WantSame, Current, BufferedSame DEF WP!ThreadDecide, WP!Min, Min, WP!Go, WP!Return, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
    <2> QED
      BY <2>D, <2>s DEF WP!Next, WP!ThreadStep
  <1> QED
    BY <1>D1, <1>D2

LEMMA SReaderCopy == ASSUME Inv, NEW r \in Readers, ReaderCopy(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "copy" /\ bl = r /\ left[r] > 0
    BY DEF ReaderCopy
  <1> DEFINE e == Head(buf)
             k == Min(left[r], Len(e) - pos)
             piece == SubSeq(e, pos + 1, pos + k)
  <1>h /\ Len(hold[r]) \in Nat /\ left[r] \in Nat /\ left[r] >= 1 /\ MBuffered >= left[r]
       /\ InLen = Len(hold[r]) /\ MBuffered = Len(written) - Len(taken) - Len(hold[r])
       /\ Len(taken) \in Nat /\ Len(written) \in Nat /\ nextByte \in Nat /\ MBuffered \in Int
    BY <1>g, <1>0, HoldLeftR, CopyHasR, Extra, AbsFacts DEF InLen, MBuffered, MHold, DTThr, DTSca
  <1>b buf # <<>>
    <2> SUFFICES ASSUME buf = <<>> PROVE FALSE
      OBVIOUS
    <2>1 Len(taken) + InLen = nextByte - 1
      BY <1>0 DEF DBuf
    <2>2 Len(written) = nextByte - 1
      BY <1>0 DEF DWriter
    <2>3 MBuffered = 0
      BY <2>1, <2>2, <1>h
    <2> QED
      BY <2>3, <1>h
  <1>e /\ e \in Seq(Int) /\ e # <<>> /\ Len(e) \in Nat /\ pos < Len(e) /\ pos \in Nat
       /\ Len(buf) \in Nat /\ Len(buf) >= 1 /\ e = buf[1]
    <2>1 buf \in Seq(Seq(Int))
      BY <1>0 DEF DTBuf
    <2>2 e \in Seq(Int) /\ Len(buf) \in Nat /\ Len(buf) >= 1 /\ e = buf[1]
      BY <2>1, <1>b, HeadTailProperties, LenProperties, EmptySeq
    <2>3 e # <<>> /\ pos < Len(e) /\ pos \in Nat
      BY <2>2, <1>b, <1>0 DEF DTBuf
    <2> QED
      BY <2>2, <2>3, LenProperties
  <1>k k \in Nat /\ k >= 1 /\ k <= left[r] /\ k <= Len(e) - pos
    BY <1>h, <1>e DEF Min
  <1>p piece \in Seq(Int) /\ Len(piece) = k
    <2>1 \A i \in (pos + 1)..(pos + k) : e[i] \in Int
      BY <1>e, <1>k, ElementOfSeq
    <2> QED
      BY <2>1, <1>e, <1>k, SubSeqProperties
  <1>q hold[r] \o piece \in Seq(Int) /\ Len(hold[r] \o piece) = Len(hold[r]) + k
    BY <1>p, <1>0, ConcatProperties DEF DTThr
  <1>f /\ hold' = [hold EXCEPT ![r] = hold[r] \o piece] /\ left' = [left EXCEPT ![r] = left[r] - k]
       /\ rpc' = [rpc EXCEPT ![r] = IF left[r] = k THEN "finish" ELSE "copy"]
       /\ (IF pos + k = Len(e) THEN buf' = Tail(buf) /\ pos' = 0 ELSE pos' = pos + k /\ buf' = buf)
       /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY <1>g, Current DEF ReaderCopy, Goto, Sync
  <1>1 rpc' = [rpc EXCEPT ![r] = IF left[r] = k THEN "finish" ELSE "copy"] /\ avail' = avail /\ written' = written /\ taken' = taken /\ toff' = toff /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ cur' = cur /\ reads' = reads /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl /\ bl' = bl
    BY <1>f
  <1>m MRpc' = [MRpc EXCEPT ![r] = IF left[r] = k THEN "finish" ELSE "copy"]
    BY <1>0, <1>1, MapGo DEF DTThr, ReaderStates, MapPc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet) /\ Cardinality(NotDone') = Cardinality(NotDone)
    BY <1>0, <1>1, <1>g, SetsGo DEF DTThr, ReaderStates
  <1>hr hold'[r] = hold[r] \o piece /\ bl' = r /\ (\A x \in Readers \ {r} : hold'[x] = hold[x])
    BY <1>f, <1>g, <1>0 DEF DTThr
  <1>L1 InLen' = InLen + k
    <2>1 InLen' = Len(hold'[r]) /\ InLen = Len(hold[r])
      BY <1>hr, <1>g, Extra DEF InLen
    <2> QED
      BY <2>1, <1>hr, <1>q
  <1>L2 MHold' = [MHold EXCEPT ![r] = MHold[r] + k]
    BY <1>hr, <1>q DEF MHold
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, FrDTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, FrDTSca
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DTThr DTThr'
    <2>1 hold' \in [Readers -> Seq(Int)]
      BY <1>hr, <1>q, <1>f, <1>0 DEF DTThr
    <2>2 left' \in [Readers -> Nat]
      BY <1>f, <1>k, <1>h, <1>0 DEF DTThr
    <2>3 rpc' \in [Readers -> ReaderStates \ {"acquire"}]
      BY <1>1, <1>0 DEF DTThr, ReaderStates
    <2> QED
      BY <2>1, <2>2, <2>3, <1>1, <1>0 DEF DTThr
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>hr, <1>g DEF DHold
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    <2>A CASE pos + k = Len(e)
      <3>1 buf' = Tail(buf) /\ pos' = 0
        BY <2>A, <1>f
      <3>2 /\ Tail(buf) \in Seq(Seq(Int)) /\ Len(Tail(buf)) = Len(buf) - 1
           /\ \A j \in 1..Len(Tail(buf)) : Tail(buf)[j] = buf[j + 1]
        BY <1>b, <1>0, HeadTailProperties DEF DTBuf
      <3>DTBuf DTBuf'
        <4>1 \A j \in 1..Len(buf') : buf'[j] # <<>>
          BY <3>1, <3>2, <1>0, <1>e DEF DTBuf
        <4>2 buf' # <<>> => 0 < Len(Head(buf'))
          <5> SUFFICES ASSUME buf' # <<>> PROVE 0 < Len(Head(buf'))
            OBVIOUS
          <5>1 Len(buf') >= 1 /\ Head(buf') = buf'[1]
            BY <3>1, <3>2, LenProperties, EmptySeq
          <5>2 buf'[1] # <<>> /\ buf'[1] \in Seq(Int)
            BY <5>1, <4>1, <3>1, <3>2, ElementOfSeq
          <5> QED
            BY <5>1, <5>2, EmptySeq
        <4> QED
          BY <3>1, <3>2, <4>1, <4>2 DEF DTBuf
      <3>DBuf DBuf'
        <4>0 /\ e[1] + pos = Len(taken) + InLen + 1
             /\ buf[Len(buf)][1] + Len(buf[Len(buf)]) = nextByte
             /\ \A j \in 1..(Len(buf) - 1) : buf[j + 1][1] = buf[j][1] + Len(buf[j])
          BY <1>0, <1>b DEF DBuf
        <4>t Len(taken') = Len(taken) /\ nextByte' = nextByte /\ InLen \in Nat /\ e[1] \in Int
          BY <1>1, <1>h, <1>e, ElementOfSeq
        <4>1 CASE Len(buf) = 1
          <5>0 buf[Len(buf)] = e
            BY <4>1, <1>e
          <5>1 buf' = <<>>
            BY <4>1, <3>1, <3>2, <1>b, <1>0, EmptySeq DEF DTBuf
          <5>2 Len(taken') + InLen' = nextByte' - 1
            BY <5>0, <4>0, <4>t, <1>L1, <2>A, <1>e, <1>k, <1>h
          <5> QED
            BY <5>1, <5>2 DEF DBuf
        <4>2 CASE Len(buf) >= 2
          <5>0 Len(buf') = Len(buf) - 1 /\ Len(buf') >= 1 /\ buf' \in Seq(Seq(Int))
            BY <4>2, <3>1, <3>2, <1>e
          <5>1 \A j \in 1..(Len(buf') - 1) : buf'[j + 1][1] = buf'[j][1] + Len(buf'[j])
            <6> SUFFICES ASSUME NEW j \in 1..(Len(buf') - 1) PROVE buf'[j + 1][1] = buf'[j][1] + Len(buf'[j])
              OBVIOUS
            <6>1 buf'[j] = buf[j + 1] /\ buf'[j + 1] = buf[j + 2] /\ j + 1 \in 1..(Len(buf) - 1)
              BY <5>0, <3>1, <3>2, <1>e
            <6> QED
              BY <6>1, <4>0
          <5>2 buf' # <<>>
            BY <5>0, EmptySeq
          <5>3 buf'[Len(buf')][1] + Len(buf'[Len(buf')]) = nextByte'
            <6>1 buf'[Len(buf')] = buf[Len(buf)]
              BY <5>0, <3>1, <3>2, <1>e
            <6> QED
              BY <6>1, <4>0, <4>t
          <5>4 Head(buf')[1] + pos' = Len(taken') + InLen' + 1
            <6>1 Head(buf') = buf[2]
              BY <5>0, <5>2, <3>1, <3>2, LenProperties
            <6>2 1 \in 1..(Len(buf) - 1)
              BY <4>2, <1>e
            <6>3 buf[2][1] = e[1] + Len(e)
              BY <6>2, <4>0, <1>e
            <6> QED
              BY <6>1, <6>3, <4>0, <4>t, <3>1, <1>L1, <2>A, <1>e, <1>k, <1>h
          <5> QED
            BY <5>1, <5>2, <5>3, <5>4 DEF DBuf
        <4> QED
          BY <4>1, <4>2, <1>e
      <3> QED
        BY <1>DTSeq, <1>DTSca, <1>DWriter, <1>DTThr, <1>DWait, <1>DHold, <1>DWant, <3>DTBuf, <3>DBuf DEF DInv, DType
    <2>B CASE pos + k # Len(e)
      <3>1 buf' = buf /\ pos' = pos + k
        BY <2>B, <1>f
      <3>DTBuf DTBuf'
        BY <3>1, <1>0, <1>e, <1>k, <2>B DEF DTBuf
      <3>DBuf DBuf'
        <4>1 e[1] + pos = Len(taken) + InLen + 1 /\ Len(taken') = Len(taken) /\ InLen \in Nat
          BY <1>0, <1>b, <1>1, <1>h DEF DBuf
        <4> QED
          <5>1 Head(buf')[1] + pos' = Len(taken') + InLen' + 1
            BY <4>1, <3>1, <1>L1, <1>e, <1>k, <1>h
          <5>2 /\ \A j \in 1..(Len(buf') - 1) : buf'[j + 1][1] = buf'[j][1] + Len(buf'[j])
               /\ buf'[Len(buf')][1] + Len(buf'[Len(buf')]) = nextByte'
            BY <3>1, <1>0, <1>1, <1>b DEF DBuf
          <5>3 buf' # <<>>
            BY <3>1, <1>b
          <5> QED
            BY <5>1, <5>2, <5>3 DEF DBuf
      <3> QED
        BY <1>DTSeq, <1>DTSca, <1>DWriter, <1>DTThr, <1>DWait, <1>DHold, <1>DWant, <3>DTBuf, <3>DBuf DEF DInv, DType
    <2> QED
      BY <2>A, <2>B
  <1>c MWpc' = MWpc /\ MCpc' = MCpc
    BY <1>1 DEF MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone
  <1>cc MCalls' = MCalls
    BY <1>1, <1>n DEF MCalls
  <1>s WP!ThreadCopy(r)
    <2>1 ~(WP!Buffered = 0)
      BY <1>h, BufferedSame
    <2>2 \E kk \in 0..left[r] : /\ kk >= 1 /\ kk <= WP!Buffered
                               /\ MHold' = [MHold EXCEPT ![r] = @ + kk]
                               /\ left' = [left EXCEPT ![r] = @ - kk]
                               /\ MRpc' = [MRpc EXCEPT ![r] = IF left[r] = kk THEN "finish" ELSE "copy"]
      <3>1 k \in 0..left[r] /\ k >= 1
        BY <1>k, <1>h
      <3>2 k <= WP!Buffered
        BY <1>k, <1>h, BufferedSame
      <3>3 MHold' = [MHold EXCEPT ![r] = @ + k]
        BY <1>L2
      <3>4 left' = [left EXCEPT ![r] = @ - k]
        BY <1>f
      <3> QED
        BY <3>1, <3>2, <3>3, <3>4, <1>m
    <2> QED
      BY <1>g, <2>1, <2>2, <1>1, <1>c, <1>cc, MOpConst DEF WP!ThreadCopy, WP!Go, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderFinish == ASSUME Inv, NEW r \in Readers, ReaderFinish(r) PROVE DInv' /\ [WP!Next]_WP!vars
  <1>0 DTBuf /\ DTSeq /\ DTSca /\ DTThr /\ DWriter /\ DBuf /\ DWait /\ DHold /\ DWant
    BY DEF Inv, DInv, DType
  <1>g rpc[r] = "finish" /\ bl = r
    BY DEF ReaderFinish
  <1>h /\ Len(hold[r]) \in Nat /\ Len(hold[r]) >= 1 /\ hold[r] \in Seq(Int)
       /\ MBuffered >= 0 /\ MBuffered = Len(written) - Len(taken) - Len(hold[r])
       /\ Len(taken) \in Nat /\ Len(written) <= Bytes /\ avail = Len(written) - Len(taken)
    BY <1>g, <1>0, HoldLeftR, BufNonNegR, AbsFacts, Extra DEF MBuffered, MHold, DTThr
  <1>1 /\ taken' = taken \o hold[r] /\ avail' = avail - Len(hold[r])
       /\ toff' = (IF toff + Len(hold[r]) >= ReadLen THEN toff + Len(hold[r]) - ReadLen ELSE toff + Len(hold[r]))
       /\ hold' = [hold EXCEPT ![r] = <<>>] /\ bl' = None /\ rpc' = [rpc EXCEPT ![r] = "start"]
       /\ cur' = cur
       /\ buf' = buf /\ pos' = pos /\ written' = written /\ closed' = closed /\ nextByte' = nextByte /\ wpc' = wpc /\ cpc' = cpc /\ want' = want /\ left' = left /\ wres' = wres /\ wclosed' = wclosed /\ eofAt' = eofAt /\ permits' = permits /\ waiters' = waiters /\ parked' = parked /\ wl' = wl
    <2>1 cur[r] = <<>> /\ [cur EXCEPT ![r] = <<>>] = cur
      BY <1>0 DEF DTThr
    <2> QED
      BY <2>1, Current DEF ReaderFinish, Goto
  <1>t taken' \in Seq(Int) /\ Len(taken') = Len(taken) + Len(hold[r])
    BY <1>1, <1>h, <1>0, ConcatProperties DEF DTSeq
  <1>m MRpc' = [MRpc EXCEPT ![r] = "start"]
    BY <1>0, <1>1, MapGo DEF DTThr, ReaderStates, MapPc
  <1>n /\ Cardinality(WSet') = Cardinality(WSet)
    BY <1>0, <1>1, <1>g, SetsGo DEF DTThr, ReaderStates
  <1>DTBuf DTBuf'
    BY <1>0, <1>1, FrDTBuf
  <1>DTSeq DTSeq'
    BY <1>0, <1>1, <1>t, <1>h, SBAssump DEF DTSeq
  <1>DTSca DTSca'
    BY <1>0, <1>1, <1>h DEF DTSca
  <1>DTThr DTThr'
    BY <1>0, <1>1, EmptySeq DEF DTThr, ReaderStates
  <1>DWriter DWriter'
    BY <1>0, <1>1, FrDWriter
  <1>DBuf DBuf'
    <2>1 InLen' = 0 /\ InLen = Len(hold[r])
      BY <1>1, <1>g, Extra DEF InLen
    <2> QED
      BY <1>0, <1>1, <1>t, <2>1 DEF DBuf
  <1>DWait DWait'
    BY <1>0, <1>1, <1>n DEF DWait
  <1>DHold DHold'
    BY <1>0, <1>1, <1>g DEF DHold, DTThr
  <1>DWant DWant'
    BY <1>0, <1>1, <1>g DEF DWant, DTThr
  <1>D DInv'
    BY <1>DTBuf, <1>DTSeq, <1>DTSca, <1>DTThr, <1>DWriter, <1>DBuf, <1>DWait, <1>DHold, <1>DWant DEF DInv, DType
  <1>e WP!EndCall(r)
    <2>0 Len(written) \in Nat /\ Len(taken) \in Nat
      BY AbsFacts
    <2>1a Len(taken') = Len(taken) + Len(hold[r])
      BY <1>t
    <2>1 Len(taken') <= Bytes
      BY <2>0, <2>1a, <1>h, SBAssump
    <2>2 rpc[r] # "done" /\ rpc' = [rpc EXCEPT ![r] = "start"]
      BY <1>g, <1>1
    <2>3 Len(hold[r]) \in Nat /\ Len(hold[r]) >= 1
      BY <1>h
    <2> QED
      BY <2>1, <2>1a, <2>2, <2>3, EndNext
  <1>c /\ MHold' = [MHold EXCEPT ![r] = 0] /\ MWpc' = MWpc /\ MCpc' = MCpc
       /\ Len(taken') = Len(taken) + MHold[r]
    BY <1>1, <1>t, <1>0, EmptySeq DEF MHold, MWpc, MCpc, DTThr
  <1>s WP!ThreadFinish(r)
    BY <1>g, <1>1, <1>c, <1>e, <1>m, <1>h, MOpConst DEF WP!ThreadFinish, MRpc, MHold, MOp, MWpc, MCpc, MCalls, NotDone, MapPc
  <1> QED
    BY <1>D, <1>s DEF WP!Next, WP!ThreadStep

LEMMA SReaderAcquire == ASSUME Inv, NEW r \in Readers, ReaderAcquire(r) PROVE DInv' /\ [WP!Next]_WP!vars
  \* not possible with Protocol = "condition": no thread is in "acquire"
  BY DEF ReaderAcquire, Inv, DInv, DType, DTThr

\* every step of StreamBuffer.tla keeps DInv and is a step of the abstraction or stutters
LEMMA Step == Inv /\ [Next]_vars => DInv' /\ [WP!Next]_WP!vars
  <1> SUFFICES ASSUME Inv, [Next]_vars PROVE DInv' /\ [WP!Next]_WP!vars
    OBVIOUS
  <1>1 CASE WriterStep
    BY <1>1, SWriterWrite, SWriterSigRead, SWriterSigLock DEF WriterStep
  <1>2 CASE CloserStep
    BY <1>2, SCloserClose, SCloserSigRead, SCloserSigLock DEF CloserStep
  <1>3 CASE \E r \in Readers : ReaderStep(r)
    <2> PICK r \in Readers : ReaderStep(r)
      BY <1>3
    <2> QED
      BY SReaderLock, SReaderInc, SReaderWaitLock, SReaderRet0, SReaderEof, SReaderWaitReturn, SReaderStart, SReaderReread, SReaderTest, SReaderDecide, SReaderCopy, SReaderFinish, SReaderAcquire DEF ReaderStep
  <1>4 CASE UNCHANGED vars
    <2>1 DInv'
      BY <1>4 DEF vars, DInv, DType, DTBuf, DTSeq, DTSca, DTThr, DWriter, DBuf, DWait, DHold, DWant, InLen, WSet, NotDone, DTBuf, DTSeq, DTSca, DTThr, Inv
    <2>2 WP!vars' = WP!vars
      BY <1>4 DEF vars, WP!vars, MapPc, MapSig, NotDone
    <2> QED
      BY <2>1, <2>2
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4 DEF Next, Terminated

LEMMA InvInit == Init => Inv
  BY InitD, InitW, CA, WP!InitSafe DEF Inv

LEMMA InvStep == Inv /\ [Next]_vars => Inv'
  BY Step, CA, WP!StepSafe DEF Inv

\* the refinement, for any set of readers
THEOREM Refinement == Spec => WP!CSpec
  <1>1 Spec => []Inv
    BY InvInit, InvStep, PTL DEF Spec
  <1>2 Inv /\ [Next]_vars => [WP!Next]_WP!vars
    BY Step
  <1> QED
    BY <1>1, <1>2, InitW, PTL DEF Spec, WP!CSpec
=============================================================================
