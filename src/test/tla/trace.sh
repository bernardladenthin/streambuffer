#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Trace validation (TODO roadmap A6): checks recorded runs of the code against StreamBuffer.tla.
#
# Usage: src/test/tla/trace.sh <tla2tools.jar> <dir with Trace_*.tla> [expect]
#   expect: "accept" (default): every trace must be accepted (the current code and model);
#           "reject": at least one trace must be rejected (a negative control).
# The traces come from net.ladenthin.streambuffer.trace.TraceGenerator (see README.md, "Trace
# validation"); this script copies StreamBuffer.tla and TraceStreamBuffer.tla next to them unless
# the directory has its own (a negative control brings a changed model).
#
# A trace is accepted when TLC violates the invariant TraceNotDone: some placement of the model's
# steps consumed every line. Otherwise TLC ends without an error, and the last "line" it printed is
# the first line no placement could consume.
set -euo pipefail

jar="$1"
dir="$2"
expect="${3:-accept}"
here="$(cd "$(dirname "$0")" && pwd)"
for f in StreamBuffer.tla TraceStreamBuffer.tla; do
  [ -f "$dir/$f" ] || cp "$here/$f" "$dir/$f"
done

accepted=0
rejected=0
total=0
start=$(date +%s)
cd "$dir"
for t in Trace_*.tla; do
  m="${t%.tla}"
  total=$((total + 1))
  out=$(java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers 1 -metadir "md_$m" -config "$m.cfg" "$m.tla" 2>&1 || true)
  lines=$(grep -c '\[t |->' "$t" || true)
  states=$(echo "$out" | grep -oE '[0-9]+ distinct states found' | grep -oE '^[0-9]+' | tail -1)
  if grep -q "Invariant TraceNotDone is violated" <<< "$out"; then
    accepted=$((accepted + 1))
    echo "ACCEPT $m ($lines lines, ${states:-?} states)"
  elif grep -qE "^Error|error:|Exception" <<< "$out"; then
    echo "ERROR  $m"
    echo "$out" | grep -E "^Error|error:|Exception" | head -5
    exit 2
  else
    rejected=$((rejected + 1))
    reached=$(echo "$out" | grep -oE '<<"line", [0-9]+>>' | grep -oE '[0-9]+' | sort -n | tail -1)
    echo "REJECT $m ($lines lines, first line no placement consumes: ${reached:-1})"
  fi
done
echo "traces: $total, accepted: $accepted, rejected: $rejected, $(( $(date +%s) - start )) s"

if [ "$expect" = "accept" ]; then
  [ "$rejected" -eq 0 ] && [ "$total" -gt 0 ]
else
  [ "$rejected" -gt 0 ]
fi
