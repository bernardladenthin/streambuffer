#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Writes the manifest of one verification job (roadmap A16): which commit and run it checked, the
# tools with their versions and SHA-256, and the job's counts (proofs, obligations, models,
# states, traces). Every job of formal-verification.yml calls it after its checks pass and uploads
# the file as an artifact, so each row of VERIFICATION-ASSUMPTIONS.md has a run tied to a revision.
#
# Usage: src/test/verification/manifest.sh <file.json> <job> <key=value>...
#   every value is written as a JSON string (encoded by Python's json module, so any character is
#   valid); the commit is GITHUB_SHA (else git's HEAD), the run GITHUB_RUN_ID (else "local").
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo "usage: manifest.sh <file.json> <job> <key=value>..." >&2
  exit 2
fi
out="$1"
job="$2"
shift 2
for kv in "$@"; do
  case "$kv" in
    ?*=*) ;;
    *) echo "manifest.sh: not key=value: $kv" >&2; exit 2 ;;
  esac
done
py="$(command -v python3 || command -v python)"
commit="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
"$py" -I -c '
import json, sys
out, job, commit, run, created = sys.argv[1:6]
manifest = {"job": job, "commit": commit, "run": run, "created": created}
for kv in sys.argv[6:]:
    key, value = kv.split("=", 1)
    manifest[key] = value
with open(out + ".tmp", "w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=True)
    f.write("\n")
' "$out" "$job" "$commit" "${GITHUB_RUN_ID:-local}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@"
mv "$out.tmp" "$out"
echo "manifest: $out ($job, $commit)"
