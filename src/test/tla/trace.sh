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

# absolute paths: the loop below runs in the trace directory
jar="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
dir="$(cd "$2" && pwd)"
expect="${3:-accept}"
here="$(cd "$(dirname "$0")" && pwd)"
for f in StreamBuffer.tla TraceStreamBuffer.tla; do
  [ -f "$dir/$f" ] || cp "$here/$f" "$dir/$f"
done

# a temporary directory of its own: TLC extracts its standard modules into java.io.tmpdir, and two
# runs in parallel (shards, the controls) truncated each other's copies
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

accepted=0
rejected=0
total=0
start=$(date +%s)
cd "$dir"
for t in Trace_*.tla; do
  m="${t%.tla}"
  total=$((total + 1))
  # TLC's output goes to a file: here-strings of it hung Git Bash on Windows when it was large
  out="$tmp/tlc.out"
  java -XX:+UseParallelGC -Djava.io.tmpdir="$tmp" -cp "$jar" tlc2.TLC -workers 1 -metadir "md_$m"     -config "$m.cfg" "$m.tla" > "$out" 2>&1 || true
  lines=$(grep -c '\[t |->' "$t" || true)
  states=$(grep -oE '[0-9]+ distinct states found' "$out" | grep -oE '^[0-9]+' | tail -1 || true)
  if grep -q "Invariant TraceNotDone is violated" "$out"; then
    accepted=$((accepted + 1))
    echo "ACCEPT $m ($lines lines, ${states:-?} states)"
  elif grep -q "Model checking completed. No error has been found." "$out"; then
    rejected=$((rejected + 1))
    reached=$(grep -oE '<<"line", [0-9]+>>' "$out" | grep -oE '[0-9]+' | sort -n | tail -1 || true)
    echo "REJECT $m ($lines lines, first line no placement consumes: ${reached:-1})"
  else
    # neither verdict: a parse error, a crash, a JVM that did not start
    echo "ERROR  $m"
    grep -E "Error|error|Exception" "$out" | head -5 || true
    exit 2
  fi
done
echo "traces: $total, accepted: $accepted, rejected: $rejected, $(( $(date +%s) - start )) s"

if [ "$expect" = "accept" ]; then
  [ "$rejected" -eq 0 ] && [ "$total" -gt 0 ]
else
  [ "$rejected" -gt 0 ]
fi
