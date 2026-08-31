#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Post-`package` smoke for the PACKAGED library jar: puts it on a classpath, exactly as a consumer
# does, and calls the API through the JDK single-file source launcher.
#
# Why this exists: every other check in the pipeline (unit tests, jqwik, Lincheck, PIT, SpotBugs,
# javadoc) runs off `target/classes`. Nothing ever loads the assembled jar, yet the assembled jar is
# what is attached to the GitHub release and deployed to Central. So a jar that is missing classes,
# carries a broken module-info.class, or was assembled from a stale target/ passes an all-green
# pipeline. See workspace/policies/fat-jar-release-assets.md ("No release asset is attached that CI
# has not run").
#
# streambuffer is the one sibling that ships NO fat jar — it is a library with no Main-Class, so
# `java -jar` is not a contract it can satisfy and the shared smoke-fatjar-cli.sh (BitcoinAddressFinder
# + srcmorph) does not apply. Same job shape, repo-appropriate assertion: classpath + API call
# instead of launch + exit code.
#
# Usage: smoke-jar.sh <jar-dir> <jar-glob>
#   <jar-dir>   directory to search for the jar (recursively)
#   <jar-glob>  filename glob; must match EXACTLY ONE jar

set -euo pipefail

JAR_DIR="${1:?usage: smoke-jar.sh <jar-dir> <jar-glob>}"
JAR_GLOB="${2:?usage: smoke-jar.sh <jar-dir> <jar-glob>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="packaged-jar smoke OK"

fail() {
    echo "::error::$*" >&2
    exit 1
}

[ -d "$JAR_DIR" ] || fail "jar directory '$JAR_DIR' does not exist"

# Exactly one match, never "pick the first": an ambiguous glob is precisely how the wrong artifact
# gets smoke-tested while the shipped one is not. The -sources / -javadoc siblings are excluded
# unconditionally -- `mvn package` builds them into the same directory and they are never the
# artifact under test.
jars=()
while IFS= read -r j; do jars+=("$j"); done < <(
    find "$JAR_DIR" -type f -name "$JAR_GLOB" ! -name '*-sources.jar' ! -name '*-javadoc.jar' | sort
)
[ "${#jars[@]}" -eq 1 ] \
    || fail "expected exactly 1 jar matching '$JAR_GLOB' under '$JAR_DIR', got ${#jars[@]}: ${jars[*]:-none}"
JAR="$(cd "$(dirname "${jars[0]}")" && pwd)/$(basename "${jars[0]}")"
echo "smoke jar: $JAR ($(wc -c < "$JAR") bytes)"

# The jar must carry its JPMS descriptor: it is compiled in a separate `release 9` execution, so a
# broken or reordered build can drop it without failing anything else.
unzip -l "$JAR" | grep -q ' module-info\.class$' \
    || fail "the jar contains no module-info.class — the release 9 compile execution did not reach it"

echo "== classpath load + API round-trip =="
out="$(java -cp "$JAR" "$SCRIPT_DIR/smoke/StreamBufferSmoke.java" 2>&1)" || {
    echo "$out"
    fail "the packaged jar did not run a StreamBuffer round-trip"
}
echo "$out"

# Exit code 0 alone is satisfied by a JVM that starts and does nothing; the marker proves the
# round-trip actually completed.
grep -qF "$MARKER" <<<"$out" || fail "success marker '$MARKER' missing from the output"

echo "smoke test PASSED"
