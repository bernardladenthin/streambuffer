#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Negative controls of the trace validation (TODO roadmap A6): a trace validation that accepts
# everything shows nothing, so wrong models and corrupted traces must be rejected.
#
# Usage: src/test/tla/trace-controls.sh <tla2tools.jar> <dir with the Trace_*.tla of TraceGenerator>
#
# Each control copies the traces into a directory of its own and changes the model or the traces:
#   - the model of older code that allows fewer behaviours than the current code: a read(b, 0, n)
#     that takes the first byte and waits for the rest (AtomicRead = FALSE, before #212), the
#     semaphore wait (before F278), no re-check under bufferLock (ReCheck = FALSE, before F278,
#     read() traces only, as the model allows), and a mutated model whose writer never signals;
#     each must reject at least one trace;
#   - every trace with a completed read, its first returned byte changed by one: every one of
#     them must be rejected.
# Older code whose model allows MORE behaviours (CountOnce = FALSE before F279, CheckedReturn =
# FALSE) accepts the traces of the current code, which is right: trace validation checks that the
# code's runs are runs of the model, not the model's properties (README, "Trace validation").
set -euo pipefail

jar="$1"
src="$2"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
py="$(command -v python3 || command -v python)"
failed=0

copy() {  # copy <name> <glob>: the traces matching the glob into $work/<name>
  mkdir -p "$work/$1"
  cp "$src"/Trace_$2*.tla "$src"/Trace_$2*.cfg "$work/$1/"
  echo "$work/$1"
}

control() {  # control <label> <dir>: at least one trace rejected
  if out=$(bash "$here/trace.sh" "$jar" "$2" reject 2>&1); then
    echo "OK    $1: $(tail -n 1 <<< "$out")"
  else
    echo "FAIL  $1: $(tail -n 1 <<< "$out")"
    failed=1
  fi
}

d=$(copy atomicread "Records")
sed -i 's/    AtomicRead = TRUE/    AtomicRead = FALSE/' "$d"/*.cfg
control "AtomicRead = FALSE (records)" "$d"

d=$(copy semaphore "")
sed -i 's/    Protocol = "condition"/    Protocol = "semaphore"/' "$d"/*.cfg
control "Protocol = semaphore" "$d"

d=$(copy recheck "Bytes")
sed -i 's/    ReCheck = TRUE/    ReCheck = FALSE/' "$d"/*.cfg
control "ReCheck = FALSE (read())" "$d"

d=$(copy nosignal "")
cp "$here/StreamBuffer.tla" "$d/"
before=$(grep -c 'IF waiters # 0 THEN "siglock" ELSE WriterDone' "$d/StreamBuffer.tla")
sed -i 's/IF waiters # 0 THEN "siglock" ELSE WriterDone/WriterDone/' "$d/StreamBuffer.tla"
[ "$before" = 1 ] || { echo "FAIL  the writer's signal not found in StreamBuffer.tla"; exit 1; }
control "mutant: the writer never signals" "$d"

d=$(copy corrupted "")
corrupted=$("$py" -I - "$d" <<'EOF'
import glob, re, sys, os
n = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], 'Trace_*.tla'))):
    s = open(f, encoding='utf-8').read()
    m = re.search(r'a \|-> "ret", n \|-> \d+, v \|-> \d+, b \|-> <<(\d+)', s)
    if m is None:
        # no completed read: nothing to corrupt
        os.remove(f)
        os.remove(f[:-4] + '.cfg')
        continue
    s = s[:m.start(1)] + str(int(m.group(1)) + 1) + s[m.end(1):]
    open(f, 'w', encoding='utf-8', newline='\n').write(s)
    n += 1
print(n)
EOF
)
out=$(bash "$here/trace.sh" "$jar" "$d" reject 2>&1 || true)
rejected=$(grep -c '^REJECT' <<< "$out" || true)
if [ "$corrupted" -gt 0 ] && [ "$rejected" = "$corrupted" ]; then
  echo "OK    corrupted traces (first returned byte + 1): $rejected/$corrupted rejected"
else
  echo "FAIL  corrupted traces (first returned byte + 1): $rejected/$corrupted rejected"
  failed=1
fi

exit "$failed"
