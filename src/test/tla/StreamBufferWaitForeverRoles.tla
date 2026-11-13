\* SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
\*
\* SPDX-License-Identifier: Apache-2.0

---------------------- MODULE StreamBufferWaitForeverRoles ----------------------
(***************************************************************************)
(* The actions of the fairness by role (StreamBufferWaitForeverLive.tla),  *)
(* in a module of their own: StreamBufferWaitForeverEnabled.tla expands    *)
(* ENABLED of them, which crashes tlapm 1.6.0-pre in a context with the    *)
(* temporal definitions of the liveness modules.                           *)
(***************************************************************************)
EXTENDS StreamBufferWait

BLHolder == \E q \in Threads : bl = q /\ ThreadStep(q)
WLHolder == \E q \in Threads : wl = q /\ ThreadStep(q)
Signal == (\E i \in Writers : WriterSigLock(i)) \/ (\E c \in Closers : CloserSigLock(c))
Closing == \E c \in Closers : CloserClose(c)
=============================================================================
