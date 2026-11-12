\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

----------------------- MODULE StreamBufferCountLemmas -----------------------
(***************************************************************************)
(* Counting lemmas for the liveness proof of StreamBufferWait (A13): a sum  *)
(* of values 0..10 over a finite set, as 10 layers of cardinalities (layer *)
(* k counts the elements of value at least k), and counts of the elements  *)
(* at which a function has a given value. The sums are split in two        *)
(* halves of 5 layers, each small enough for the SMT backend.              *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, FiniteSetTheorems, TLAPS

\* the elements of S at which f is at least k, and at which f is a
Lay(S, f, k) == {x \in S : f[x] >= k}
At(S, f, a) == {x \in S : f[x] = a}
\* 1 if v reaches layer k
B(v, k) == IF v >= k THEN 1 ELSE 0
LLo(S, f) == Cardinality(Lay(S, f, 1)) + Cardinality(Lay(S, f, 2)) + Cardinality(Lay(S, f, 3)) + Cardinality(Lay(S, f, 4)) + Cardinality(Lay(S, f, 5))
LHi(S, f) == Cardinality(Lay(S, f, 6)) + Cardinality(Lay(S, f, 7)) + Cardinality(Lay(S, f, 8)) + Cardinality(Lay(S, f, 9)) + Cardinality(Lay(S, f, 10))
LSum(S, f) == LLo(S, f) + LHi(S, f)

LEMMA SubCard == ASSUME NEW S, IsFiniteSet(S), NEW A, A \subseteq S
                 PROVE IsFiniteSet(A) /\ Cardinality(A) \in Nat /\ Cardinality(A) <= Cardinality(S)
  BY FS_Subset, FS_CardinalityType

\* A and B agree but at r: the counts differ by r's membership
LEMMA SetExcept ==
  ASSUME NEW S, IsFiniteSet(S), NEW r \in S, NEW A, NEW Bs, A \subseteq S, Bs \subseteq S,
         A \ {r} = Bs \ {r}
  PROVE Cardinality(Bs) = Cardinality(A) - (IF r \in A THEN 1 ELSE 0) + (IF r \in Bs THEN 1 ELSE 0)
  <1> DEFINE C == A \ {r}
  <1>1 IsFiniteSet(C) /\ r \notin C /\ Cardinality(C) \in Nat
    BY FS_Subset, FS_CardinalityType
  <1>2 Cardinality(C \cup {r}) = Cardinality(C) + 1
    BY <1>1, FS_AddElement
  <1>3 CASE r \in A /\ r \in Bs
    <2>1 A = C \cup {r} /\ Bs = C \cup {r}
      BY <1>3
    <2> QED
      BY <1>3, <2>1, <1>2, <1>1
  <1>4 CASE r \in A /\ r \notin Bs
    <2>1 A = C \cup {r} /\ Bs = C
      BY <1>4
    <2> QED
      BY <1>4, <2>1, <1>2, <1>1
  <1>5 CASE r \notin A /\ r \in Bs
    <2>1 A = C /\ Bs = C \cup {r}
      BY <1>5
    <2> QED
      BY <1>5, <2>1, <1>2, <1>1
  <1>6 CASE r \notin A /\ r \notin Bs
    <2>1 A = C /\ Bs = C
      BY <1>6
    <2> QED
      BY <1>6, <2>1, <1>1
  <1> QED
    BY <1>3, <1>4, <1>5, <1>6

LEMMA LayExcept ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW g, NEW r \in S, NEW k,
         \A x \in S \ {r} : g[x] = f[x]
  PROVE Cardinality(Lay(S, g, k)) = Cardinality(Lay(S, f, k)) - B(f[r], k) + B(g[r], k)
  <1>1 /\ Lay(S, f, k) \subseteq S /\ Lay(S, g, k) \subseteq S
       /\ Lay(S, f, k) \ {r} = Lay(S, g, k) \ {r}
       /\ (r \in Lay(S, f, k) <=> f[r] >= k) /\ (r \in Lay(S, g, k) <=> g[r] >= k)
    BY DEF Lay
  <1>2 Cardinality(Lay(S, g, k))
         = Cardinality(Lay(S, f, k)) - (IF r \in Lay(S, f, k) THEN 1 ELSE 0)
           + (IF r \in Lay(S, g, k) THEN 1 ELSE 0)
    BY <1>1, SetExcept
  <1> QED
    BY <1>1, <1>2 DEF B

LEMMA AtExcept ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW g, NEW r \in S, NEW a,
         \A x \in S \ {r} : g[x] = f[x]
  PROVE Cardinality(At(S, g, a))
          = Cardinality(At(S, f, a)) - (IF f[r] = a THEN 1 ELSE 0) + (IF g[r] = a THEN 1 ELSE 0)
  <1>1 /\ At(S, f, a) \subseteq S /\ At(S, g, a) \subseteq S
       /\ At(S, f, a) \ {r} = At(S, g, a) \ {r}
       /\ (r \in At(S, f, a) <=> f[r] = a) /\ (r \in At(S, g, a) <=> g[r] = a)
    BY DEF At
  <1>2 Cardinality(At(S, g, a))
         = Cardinality(At(S, f, a)) - (IF r \in At(S, f, a) THEN 1 ELSE 0)
           + (IF r \in At(S, g, a) THEN 1 ELSE 0)
    BY <1>1, SetExcept
  <1> QED
    BY <1>1, <1>2

LEMMA AtType ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW a
  PROVE /\ Cardinality(At(S, f, a)) \in Nat
        /\ Cardinality(At(S, f, a)) <= Cardinality(S)
  <1>1 At(S, f, a) \subseteq S
    BY DEF At
  <1> QED
    BY <1>1, SubCard

LEMMA LayType ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW k
  PROVE /\ Cardinality(Lay(S, f, k)) \in Nat
        /\ Cardinality(Lay(S, f, k)) <= Cardinality(S)
  <1>1 Lay(S, f, k) \subseteq S
    BY DEF Lay
  <1> QED
    BY <1>1, SubCard

LEMMA BType == ASSUME NEW v, NEW k PROVE B(v, k) \in Nat /\ B(v, k) <= 1
  BY DEF B

\* the layers of one value 0..10 add up to it
LEMMA IfSum == ASSUME NEW v \in 0..10 PROVE (B(v, 1) + B(v, 2) + B(v, 3) + B(v, 4) + B(v, 5)) + (B(v, 6) + B(v, 7) + B(v, 8) + B(v, 9) + B(v, 10)) = v
  <1>1 v = 0 \/ v = 1 \/ v = 2 \/ v = 3 \/ v = 4 \/ v = 5 \/ v = 6 \/ v = 7 \/ v = 8 \/ v = 9 \/ v = 10
    OBVIOUS
  <1>2 CASE v = 0
    BY <1>2 DEF B
  <1>3 CASE v = 1
    BY <1>3 DEF B
  <1>4 CASE v = 2
    BY <1>4 DEF B
  <1>5 CASE v = 3
    BY <1>5 DEF B
  <1>6 CASE v = 4
    BY <1>6 DEF B
  <1>7 CASE v = 5
    BY <1>7 DEF B
  <1>8 CASE v = 6
    BY <1>8 DEF B
  <1>9 CASE v = 7
    BY <1>9 DEF B
  <1>10 CASE v = 8
    BY <1>10 DEF B
  <1>11 CASE v = 9
    BY <1>11 DEF B
  <1>12 CASE v = 10
    BY <1>12 DEF B
  <1> QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12

\* the sum is a natural number, at most 10 per element
LEMMA LSumType ==
  ASSUME NEW S, IsFiniteSet(S), NEW f
  PROVE /\ LSum(S, f) \in Nat
        /\ LSum(S, f) <= 10 * Cardinality(S)
  <1>1 Cardinality(Lay(S, f, 1)) \in Nat /\ Cardinality(Lay(S, f, 1)) <= Cardinality(S)
    BY LayType
  <1>2 Cardinality(Lay(S, f, 2)) \in Nat /\ Cardinality(Lay(S, f, 2)) <= Cardinality(S)
    BY LayType
  <1>3 Cardinality(Lay(S, f, 3)) \in Nat /\ Cardinality(Lay(S, f, 3)) <= Cardinality(S)
    BY LayType
  <1>4 Cardinality(Lay(S, f, 4)) \in Nat /\ Cardinality(Lay(S, f, 4)) <= Cardinality(S)
    BY LayType
  <1>5 Cardinality(Lay(S, f, 5)) \in Nat /\ Cardinality(Lay(S, f, 5)) <= Cardinality(S)
    BY LayType
  <1>6 Cardinality(Lay(S, f, 6)) \in Nat /\ Cardinality(Lay(S, f, 6)) <= Cardinality(S)
    BY LayType
  <1>7 Cardinality(Lay(S, f, 7)) \in Nat /\ Cardinality(Lay(S, f, 7)) <= Cardinality(S)
    BY LayType
  <1>8 Cardinality(Lay(S, f, 8)) \in Nat /\ Cardinality(Lay(S, f, 8)) <= Cardinality(S)
    BY LayType
  <1>9 Cardinality(Lay(S, f, 9)) \in Nat /\ Cardinality(Lay(S, f, 9)) <= Cardinality(S)
    BY LayType
  <1>10 Cardinality(Lay(S, f, 10)) \in Nat /\ Cardinality(Lay(S, f, 10)) <= Cardinality(S)
    BY LayType
  <1>11 Cardinality(S) \in Nat
    BY FS_CardinalityType
  <1>12 LLo(S, f) \in Nat /\ LLo(S, f) <= 5 * Cardinality(S)
    BY ONLY <1>1, <1>2, <1>3, <1>4, <1>5, <1>11 DEF LLo
  <1>13 LHi(S, f) \in Nat /\ LHi(S, f) <= 5 * Cardinality(S)
    BY ONLY <1>6, <1>7, <1>8, <1>9, <1>10, <1>11 DEF LHi
  <1> QED
    BY ONLY <1>11, <1>12, <1>13 DEF LSum

\* a change at one element changes the sum by the difference there (values 0..10)
LEMMA LSumExcept ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW g, NEW r \in S, f[r] \in 0..10, g[r] \in 0..10,
         \A x \in S \ {r} : g[x] = f[x]
  PROVE LSum(S, g) = LSum(S, f) - f[r] + g[r]
  <1>1 Cardinality(Lay(S, g, 1)) = Cardinality(Lay(S, f, 1)) - B(f[r], 1) + B(g[r], 1)
    BY LayExcept
  <1>2 Cardinality(Lay(S, g, 2)) = Cardinality(Lay(S, f, 2)) - B(f[r], 2) + B(g[r], 2)
    BY LayExcept
  <1>3 Cardinality(Lay(S, g, 3)) = Cardinality(Lay(S, f, 3)) - B(f[r], 3) + B(g[r], 3)
    BY LayExcept
  <1>4 Cardinality(Lay(S, g, 4)) = Cardinality(Lay(S, f, 4)) - B(f[r], 4) + B(g[r], 4)
    BY LayExcept
  <1>5 Cardinality(Lay(S, g, 5)) = Cardinality(Lay(S, f, 5)) - B(f[r], 5) + B(g[r], 5)
    BY LayExcept
  <1>6 Cardinality(Lay(S, g, 6)) = Cardinality(Lay(S, f, 6)) - B(f[r], 6) + B(g[r], 6)
    BY LayExcept
  <1>7 Cardinality(Lay(S, g, 7)) = Cardinality(Lay(S, f, 7)) - B(f[r], 7) + B(g[r], 7)
    BY LayExcept
  <1>8 Cardinality(Lay(S, g, 8)) = Cardinality(Lay(S, f, 8)) - B(f[r], 8) + B(g[r], 8)
    BY LayExcept
  <1>9 Cardinality(Lay(S, g, 9)) = Cardinality(Lay(S, f, 9)) - B(f[r], 9) + B(g[r], 9)
    BY LayExcept
  <1>10 Cardinality(Lay(S, g, 10)) = Cardinality(Lay(S, f, 10)) - B(f[r], 10) + B(g[r], 10)
    BY LayExcept
  <1>11 Cardinality(Lay(S, f, 1)) \in Nat /\ Cardinality(Lay(S, g, 1)) \in Nat
    BY LayType
  <1>12 Cardinality(Lay(S, f, 2)) \in Nat /\ Cardinality(Lay(S, g, 2)) \in Nat
    BY LayType
  <1>13 Cardinality(Lay(S, f, 3)) \in Nat /\ Cardinality(Lay(S, g, 3)) \in Nat
    BY LayType
  <1>14 Cardinality(Lay(S, f, 4)) \in Nat /\ Cardinality(Lay(S, g, 4)) \in Nat
    BY LayType
  <1>15 Cardinality(Lay(S, f, 5)) \in Nat /\ Cardinality(Lay(S, g, 5)) \in Nat
    BY LayType
  <1>16 Cardinality(Lay(S, f, 6)) \in Nat /\ Cardinality(Lay(S, g, 6)) \in Nat
    BY LayType
  <1>17 Cardinality(Lay(S, f, 7)) \in Nat /\ Cardinality(Lay(S, g, 7)) \in Nat
    BY LayType
  <1>18 Cardinality(Lay(S, f, 8)) \in Nat /\ Cardinality(Lay(S, g, 8)) \in Nat
    BY LayType
  <1>19 Cardinality(Lay(S, f, 9)) \in Nat /\ Cardinality(Lay(S, g, 9)) \in Nat
    BY LayType
  <1>20 Cardinality(Lay(S, f, 10)) \in Nat /\ Cardinality(Lay(S, g, 10)) \in Nat
    BY LayType
  <1>21 B(f[r], 1) \in Nat /\ B(g[r], 1) \in Nat
    BY BType
  <1>22 B(f[r], 2) \in Nat /\ B(g[r], 2) \in Nat
    BY BType
  <1>23 B(f[r], 3) \in Nat /\ B(g[r], 3) \in Nat
    BY BType
  <1>24 B(f[r], 4) \in Nat /\ B(g[r], 4) \in Nat
    BY BType
  <1>25 B(f[r], 5) \in Nat /\ B(g[r], 5) \in Nat
    BY BType
  <1>26 B(f[r], 6) \in Nat /\ B(g[r], 6) \in Nat
    BY BType
  <1>27 B(f[r], 7) \in Nat /\ B(g[r], 7) \in Nat
    BY BType
  <1>28 B(f[r], 8) \in Nat /\ B(g[r], 8) \in Nat
    BY BType
  <1>29 B(f[r], 9) \in Nat /\ B(g[r], 9) \in Nat
    BY BType
  <1>30 B(f[r], 10) \in Nat /\ B(g[r], 10) \in Nat
    BY BType
  <1>31 LLo(S, g) = LLo(S, f) - (B(f[r], 1) + B(f[r], 2) + B(f[r], 3) + B(f[r], 4) + B(f[r], 5)) + (B(g[r], 1) + B(g[r], 2) + B(g[r], 3) + B(g[r], 4) + B(g[r], 5))
    BY ONLY <1>1, <1>2, <1>3, <1>4, <1>5, <1>11, <1>12, <1>13, <1>14, <1>15, <1>21, <1>22, <1>23, <1>24, <1>25 DEF LLo
  <1>32 LHi(S, g) = LHi(S, f) - (B(f[r], 6) + B(f[r], 7) + B(f[r], 8) + B(f[r], 9) + B(f[r], 10)) + (B(g[r], 6) + B(g[r], 7) + B(g[r], 8) + B(g[r], 9) + B(g[r], 10))
    BY ONLY <1>6, <1>7, <1>8, <1>9, <1>10, <1>16, <1>17, <1>18, <1>19, <1>20, <1>26, <1>27, <1>28, <1>29, <1>30 DEF LHi
  <1>33 (B(f[r], 1) + B(f[r], 2) + B(f[r], 3) + B(f[r], 4) + B(f[r], 5)) + (B(f[r], 6) + B(f[r], 7) + B(f[r], 8) + B(f[r], 9) + B(f[r], 10)) = f[r]
    BY IfSum
  <1>34 (B(g[r], 1) + B(g[r], 2) + B(g[r], 3) + B(g[r], 4) + B(g[r], 5)) + (B(g[r], 6) + B(g[r], 7) + B(g[r], 8) + B(g[r], 9) + B(g[r], 10)) = g[r]
    BY IfSum
  <1>35 LLo(S, f) \in Nat /\ LHi(S, f) \in Nat
    BY ONLY <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF LLo, LHi
  <1> QED
    BY ONLY <1>31, <1>32, <1>33, <1>34, <1>35, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF LSum

\* pointwise not larger, sum not larger
LEMMA LSumMono ==
  ASSUME NEW S, IsFiniteSet(S), NEW f, NEW g, \A x \in S : g[x] \in Int /\ f[x] \in Int /\ g[x] <= f[x]
  PROVE LSum(S, g) <= LSum(S, f)
  <1>1 Lay(S, g, 1) \subseteq Lay(S, f, 1) /\ Lay(S, f, 1) \subseteq S
    BY DEF Lay
  <1>2 Lay(S, g, 2) \subseteq Lay(S, f, 2) /\ Lay(S, f, 2) \subseteq S
    BY DEF Lay
  <1>3 Lay(S, g, 3) \subseteq Lay(S, f, 3) /\ Lay(S, f, 3) \subseteq S
    BY DEF Lay
  <1>4 Lay(S, g, 4) \subseteq Lay(S, f, 4) /\ Lay(S, f, 4) \subseteq S
    BY DEF Lay
  <1>5 Lay(S, g, 5) \subseteq Lay(S, f, 5) /\ Lay(S, f, 5) \subseteq S
    BY DEF Lay
  <1>6 Lay(S, g, 6) \subseteq Lay(S, f, 6) /\ Lay(S, f, 6) \subseteq S
    BY DEF Lay
  <1>7 Lay(S, g, 7) \subseteq Lay(S, f, 7) /\ Lay(S, f, 7) \subseteq S
    BY DEF Lay
  <1>8 Lay(S, g, 8) \subseteq Lay(S, f, 8) /\ Lay(S, f, 8) \subseteq S
    BY DEF Lay
  <1>9 Lay(S, g, 9) \subseteq Lay(S, f, 9) /\ Lay(S, f, 9) \subseteq S
    BY DEF Lay
  <1>10 Lay(S, g, 10) \subseteq Lay(S, f, 10) /\ Lay(S, f, 10) \subseteq S
    BY DEF Lay
  <1>11 Cardinality(Lay(S, g, 1)) <= Cardinality(Lay(S, f, 1))
    BY <1>1, FS_Subset
  <1>12 Cardinality(Lay(S, g, 2)) <= Cardinality(Lay(S, f, 2))
    BY <1>2, FS_Subset
  <1>13 Cardinality(Lay(S, g, 3)) <= Cardinality(Lay(S, f, 3))
    BY <1>3, FS_Subset
  <1>14 Cardinality(Lay(S, g, 4)) <= Cardinality(Lay(S, f, 4))
    BY <1>4, FS_Subset
  <1>15 Cardinality(Lay(S, g, 5)) <= Cardinality(Lay(S, f, 5))
    BY <1>5, FS_Subset
  <1>16 Cardinality(Lay(S, g, 6)) <= Cardinality(Lay(S, f, 6))
    BY <1>6, FS_Subset
  <1>17 Cardinality(Lay(S, g, 7)) <= Cardinality(Lay(S, f, 7))
    BY <1>7, FS_Subset
  <1>18 Cardinality(Lay(S, g, 8)) <= Cardinality(Lay(S, f, 8))
    BY <1>8, FS_Subset
  <1>19 Cardinality(Lay(S, g, 9)) <= Cardinality(Lay(S, f, 9))
    BY <1>9, FS_Subset
  <1>20 Cardinality(Lay(S, g, 10)) <= Cardinality(Lay(S, f, 10))
    BY <1>10, FS_Subset
  <1>21 Cardinality(Lay(S, f, 1)) \in Nat /\ Cardinality(Lay(S, g, 1)) \in Nat
    BY LayType
  <1>22 Cardinality(Lay(S, f, 2)) \in Nat /\ Cardinality(Lay(S, g, 2)) \in Nat
    BY LayType
  <1>23 Cardinality(Lay(S, f, 3)) \in Nat /\ Cardinality(Lay(S, g, 3)) \in Nat
    BY LayType
  <1>24 Cardinality(Lay(S, f, 4)) \in Nat /\ Cardinality(Lay(S, g, 4)) \in Nat
    BY LayType
  <1>25 Cardinality(Lay(S, f, 5)) \in Nat /\ Cardinality(Lay(S, g, 5)) \in Nat
    BY LayType
  <1>26 Cardinality(Lay(S, f, 6)) \in Nat /\ Cardinality(Lay(S, g, 6)) \in Nat
    BY LayType
  <1>27 Cardinality(Lay(S, f, 7)) \in Nat /\ Cardinality(Lay(S, g, 7)) \in Nat
    BY LayType
  <1>28 Cardinality(Lay(S, f, 8)) \in Nat /\ Cardinality(Lay(S, g, 8)) \in Nat
    BY LayType
  <1>29 Cardinality(Lay(S, f, 9)) \in Nat /\ Cardinality(Lay(S, g, 9)) \in Nat
    BY LayType
  <1>30 Cardinality(Lay(S, f, 10)) \in Nat /\ Cardinality(Lay(S, g, 10)) \in Nat
    BY LayType
  <1>31 LLo(S, g) <= LLo(S, f) /\ LLo(S, g) \in Nat
    BY ONLY <1>11, <1>12, <1>13, <1>14, <1>15, <1>21, <1>22, <1>23, <1>24, <1>25 DEF LLo
  <1>32 LHi(S, g) <= LHi(S, f) /\ LHi(S, g) \in Nat
    BY ONLY <1>16, <1>17, <1>18, <1>19, <1>20, <1>26, <1>27, <1>28, <1>29, <1>30 DEF LHi
  <1>33 LLo(S, f) \in Nat /\ LHi(S, f) \in Nat
    BY ONLY <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF LLo, LHi
  <1> QED
    BY ONLY <1>31, <1>32, <1>33 DEF LSum

\* an element of a finite set makes it count
LEMMA CardPos ==
  ASSUME NEW S, IsFiniteSet(S), NEW x \in S
  PROVE Cardinality(S) >= 1
  BY FS_EmptySet, FS_CardinalityType
=============================================================================
