#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# TLAPS proof of StreamBufferCountersProof.tla (TODO roadmap A13): SafeInv is an inductive invariant
# of the read() counter abstraction for ANY number of readers and bytes, so Spec => []Safety. Fails
# unless every obligation is proved. Not in CI yet: tlapm has no tagged 1.6 release, and the rolling
# 1.6.0-pre asset changes, so a pinned checksum would break; see src/test/tla/README.md.
#
# Usage: src/test/tla/proof.sh <path to tlapm>   (run from anywhere)
set -euo pipefail
tlapm="$1"
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp StreamBufferCounters.tla StreamBufferCountersProof.tla "$work/"
cd "$work"
set +e
"$tlapm" --threads "$(nproc 2>/dev/null || echo 4)" --stretch 3 StreamBufferCountersProof.tla > proof.log 2>&1
set -e
result="$(grep -E 'All [0-9]+ obligations proved|obligations failed' proof.log | tail -1)"
echo "$result"
case "$result" in
  *"All "*" obligations proved"*) exit 0 ;;
  *) grep -A2 '^File' proof.log | head -20; exit 1 ;;
esac
