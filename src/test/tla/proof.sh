#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# TLAPS proofs (TODO roadmap A13), each that SafeInv is an inductive invariant, so Spec => []Safety:
# - StreamBufferCountersProof.tla: read(), ANY number of readers and bytes;
# - StreamBufferRecordsProof.tla: read(b, 0, K), any number of readers, record size K, bytes and
#   chunking of the writes (whole aligned records, #212).
# Fails unless every obligation of both is proved. Not in CI yet: tlapm has no tagged 1.6 release,
# and the rolling 1.6.0-pre asset changes, so a pinned checksum would break; see README.md here.
#
# Usage: src/test/tla/proof.sh <path to tlapm>   (run from anywhere)
set -euo pipefail
tlapm="$1"
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp StreamBufferCounters.tla StreamBufferCountersProof.tla \
   StreamBufferRecords.tla StreamBufferRecordsProof.tla "$work/"
cd "$work"
failed=0
for proof in StreamBufferCountersProof StreamBufferRecordsProof; do
  set +e
  "$tlapm" --threads "$(nproc 2>/dev/null || echo 4)" --stretch 3 "$proof.tla" > "$proof.log" 2>&1
  set -e
  result="$(grep -E 'All [0-9]+ obligations proved|obligations failed' "$proof.log" | tail -1)"
  echo "$proof: $result"
  case "$result" in
    *"All "*" obligations proved"*) ;;
    *) grep -A2 '^File' "$proof.log" | head -20; failed=1 ;;
  esac
done
exit "$failed"
