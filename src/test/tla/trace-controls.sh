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

control() {  # control <label> <dir> [own model]: at least one trace rejected
  if out=$(TRACE_OWN_MODEL="${3:-0}" bash "$here/trace.sh" "$jar" "$2" reject 2>&1); then
    echo "OK    $1: $(printf '%s\n' "$out" | tail -n 1)"
  else
    echo "FAIL  $1: $(printf '%s\n' "$out" | tail -n 1)"
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
# no spurious wake-ups here: they could explain the wake-ups the missing signal leaves out
sed -i 's/    Spurious = [0-9]*/    Spurious = 0/' "$d"/*.cfg
control "mutant: the writer never signals" "$d" 1

# A spurious wake-up written into a trace: right after a reader's park, before any other thread's
# line, the lines of one more round of the loop of awaitAtLeast (unpark, the test of availableBytes
# and streamClosed, park). Nothing can wake the reader there (the other threads move only at their
# own lines), so the trace must be accepted with the budget of TraceGenerator and rejected with
# Spurious = 0. One trace each from up to three; each in a directory of its own.
d=$(copy spurious "")
names=$("$py" -I - "$d" <<'EOF'
import glob, os, re, sys
d = sys.argv[1]
done = 0
for f in sorted(glob.glob(os.path.join(d, 'Trace_*.tla'))):
    name = os.path.basename(f)[:-4]
    lines = open(f, encoding='utf-8').read().split('\n')
    park = [i for i, l in enumerate(lines) if 'a |-> "park"' in l]
    if done >= 3 or not park:
        os.remove(f)
        os.remove(f[:-4] + '.cfg')
        continue
    p = park[0]
    t = re.search(r'\[t \|-> "([^"]+)"', lines[p]).group(1)
    # the value of availableBytes at the park: the last access of it before
    v = [re.search(r'v \|-> (\d+)', lines[j]).group(1) for j in range(p)
         if re.search(r'a \|-> "(getAvail|putAvail)"', lines[j])][-1]
    row = ', [t |-> "%s", m |-> "awaitAtLeast", a |-> "%s", n |-> %d, v |-> %s, b |-> <<>>]'
    lines[p + 1:p + 1] = [row % (t, 'unpark', 0, 0), row % (t, 'getAvail', 2, v),
                          row % (t, 'getClosed', 0, 0), row % (t, 'park', 0, 0)]
    os.makedirs(os.path.join(d, name))
    open(os.path.join(d, name, name + '.tla'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    os.replace(f[:-4] + '.cfg', os.path.join(d, name, name + '.cfg'))
    os.remove(f)
    print(name)
    done += 1
EOF
)
names=$(printf '%s\n' "$names" | tr -d '\r')
ok=0
for n in $names; do
  with=$(bash "$here/trace.sh" "$jar" "$d/$n" accept 2>&1 || true)
  sed -i 's/    Spurious = [0-9]*/    Spurious = 0/' "$d/$n/$n.cfg"
  without=$(bash "$here/trace.sh" "$jar" "$d/$n" reject 2>&1 || true)
  if printf '%s\n' "$with" | grep -q 'accepted: 1, rejected: 0' \
     && printf '%s\n' "$without" | grep -q 'accepted: 0, rejected: 1'; then
    ok=$((ok + 1))
  else
    echo "      $n: with the budget: $(printf '%s\n' "$with" | tail -n 1); without: $(printf '%s\n' "$without" | tail -n 1)"
  fi
done
count=$(printf '%s\n' "$names" | grep -c . || true)
if [ "$count" -gt 0 ] && [ "$ok" = "$count" ]; then
  echo "OK    a spurious wake-up written into a trace: $ok/$count accepted with the budget, rejected without"
else
  echo "FAIL  a spurious wake-up written into a trace: $ok/$count accepted with the budget, rejected without"
  failed=1
fi

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
rejected=$(printf '%s\n' "$out" | grep -c "^REJECT" || true)
if [ "$corrupted" -gt 0 ] && [ "$rejected" = "$corrupted" ]; then
  echo "OK    corrupted traces (first returned byte + 1): $rejected/$corrupted rejected"
else
  echo "FAIL  corrupted traces (first returned byte + 1): $rejected/$corrupted rejected"
  failed=1
fi

exit "$failed"
