#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# TLAPS proofs (TODO roadmap A13). Safety, each that SafeInv is an inductive invariant, so
# Spec => []Safety:
# - StreamBufferCountersProof.tla: read(), ANY number of readers and bytes;
# - StreamBufferRecordsProof.tla: read(b, 0, K), any number of readers, writers and closers, any
#   record size K, bytes and chunking of the writes (whole aligned records, #212);
# - StreamBufferWaitProof.tla: any set of threads, each making any number of calls, each a
#   read(b, 0, K[r]) or a waitForAtLeast(M[r]), any numbers of writers and closers, any read sizes,
#   requests, bytes and chunking (fewer than M[r] only for a closed buffer, whole reads).
# Refinement, RefineWaitProof.tla: StreamBuffer.tla with the current code refines
# StreamBufferWait.tla for ANY finite set of readers (every step is a step of the abstraction or
# stutters), so the safety results above hold for the detailed model too (not the liveness:
# the refinement is of the specifications without fairness).
# Liveness, StreamBufferWaitLiveProof.tla: with at least one closer and finitely many threads,
# every behaviour with weak fairness of Next ends with every call returned and all done; it uses
# StreamBufferCountLemmas.tla (sums as layers of cardinalities) and StreamBufferWaitEnabled.tla (a
# step is possible until all are done), both proved here too.
# Liveness with threads that call forever, StreamBufferWaitForeverLiveProof.tla: with at least one
# closer, in every behaviour of StreamBufferWaitForever.tla with the fairness by role, every call
# of every thread returns (or the thread stopped), for any number of threads, writers and closers;
# it uses StreamBufferWaitForeverEnabled.tla (the role actions are enabled where needed).
# Fails unless every obligation of every proof is proved. In CI: the scheduled tlaps-proofs job of
# formal-verification.yml, with tlapm built from a pinned commit (no tagged 1.6 release; README.md).
#
# Usage: src/test/tla/proof.sh <path to tlapm>   (run from anywhere)
set -euo pipefail
tlapm="$1"
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp StreamBufferCounters.tla StreamBufferCountersProof.tla \
   StreamBufferRecords.tla StreamBufferRecordsProof.tla \
   StreamBufferWait.tla StreamBufferWaitProof.tla \
   StreamBufferWaitLive.tla StreamBufferCountLemmas.tla StreamBufferWaitEnabled.tla \
   StreamBufferWaitLiveProof.tla StreamBuffer.tla RefineWait.tla RefineWaitProof.tla \
   StreamBufferWaitForever.tla StreamBufferWaitForeverRoles.tla StreamBufferWaitForeverLive.tla \
   StreamBufferWaitForeverEnabled.tla StreamBufferWaitForeverLiveProof.tla "$work/"
cd "$work"
failed=0
for proof in StreamBufferCountersProof StreamBufferRecordsProof StreamBufferWaitProof \
             StreamBufferCountLemmas StreamBufferWaitEnabled StreamBufferWaitLiveProof RefineWaitProof \
             StreamBufferWaitForeverEnabled StreamBufferWaitForeverLiveProof; do
  # the ENABLED steps need more time on a loaded machine (one timed out at --stretch 3 and 6
  # with the other cores busy, none in three runs at 12; 2026-11-12)
  stretch=3
  [ "$proof" = StreamBufferWaitEnabled ] && stretch=12
  [ "$proof" = StreamBufferWaitForeverEnabled ] && stretch=12
  # tlapm can leave backend provers running after it ends (an Isabelle or z3 started for an
  # obligation another backend proved); in their own process group they are killed before the
  # next proof, which they would otherwise slow down into timeouts
  set +e
  setsid "$tlapm" --threads "$(nproc 2>/dev/null || echo 4)" --stretch "$stretch" "$proof.tla" \
    > "$proof.log" 2>&1 &
  pid=$!
  wait "$pid"
  kill -9 -- "-$pid" 2>/dev/null
  set -e
  result="$(grep -E 'All [0-9]+ obligations proved|obligations failed' "$proof.log" | tail -1)"
  echo "$proof: $result"
  case "$result" in
    *"All "*" obligations proved"*) ;;
    *) grep -B1 -A3 'Could not prove' "$proof.log" | head -40; failed=1 ;;
  esac
done
exit "$failed"
