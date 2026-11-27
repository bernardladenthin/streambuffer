#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Local side of a long run on a rented machine (README.md here): builds the payload the machine
# needs, from the working tree, into one archive. Contents (payload root):
#   sb/        src/test/{tla,jpf,remote} and .github/workflows/formal-verification.yml (the tool
#              pins setup.sh reads, so the machine uses the versions CI uses)
#   traced/, traced-mutant/, traced-nosignal/   the instrumented StreamBuffer classes (A18;
#                             TracedClassDump, the last two with a defect of TraceMutants)
#   lib/       the annotation jars the production bytecode references (checker-qual, jspecify,
#              error-prone-annotations), for JPF's classpath
#   traces/    Trace_*.tla of TraceGenerator (A6; TRACE_SEEDS seeds per scenario, yields 32/256)
#   COMMIT, DIRTY   the commit and `git status --porcelain`, so a result names what it ran
# Nothing private goes in: no key, no host, no account.
#
# Usage: src/test/remote/pack.sh [archive]   (default target/remote/payload.tgz; needs mvn and a
#        JDK for the build, as for `mvn test`)
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
out="${1:-target/remote/payload.tgz}"
work=target/remote
stage="$work/stage"
rm -rf "$stage"
mkdir -p "$stage/lib" "$stage/sb/src/test" "$stage/sb/.github/workflows"

# the classpath separator of the local java (Git Bash on Windows runs a Windows JDK)
sep=":"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) sep=";" ;; esac

mvn -B -q -DskipTests -Denforcer.skip=true test-compile dependency:build-classpath \
  -Dmdep.includeScope=test -Dmdep.outputFile="$work/test-classpath.txt"
# a fresh folder: after a version bump an old jar would match the globs below too
rm -rf "$work/anno"
mvn -B -q dependency:copy-dependencies -DincludeScope=compile -DoutputDirectory="$work/anno"
cp "$work"/anno/checker-qual-*.jar "$stage/lib/checker-qual.jar"
cp "$work"/anno/jspecify-*.jar "$stage/lib/jspecify.jar"
cp "$work"/anno/error_prone_annotations-*.jar "$stage/lib/error-prone-annotations.jar"

cp="target/test-classes${sep}target/classes${sep}$(cat "$work/test-classpath.txt")"
java -cp "$cp" net.ladenthin.streambuffer.trace.TracedClassDump "$stage/traced"
java -cp "$cp" net.ladenthin.streambuffer.trace.TracedClassDump "$stage/traced-mutant" no-decrement
java -cp "$cp" net.ladenthin.streambuffer.trace.TracedClassDump "$stage/traced-nosignal" no-write-signal
java -ea -cp "$cp" net.ladenthin.streambuffer.trace.TraceGenerator "$stage/traces" "${TRACE_SEEDS:-3}" 32

cp -r src/test/tla src/test/jpf src/test/remote "$stage/sb/src/test/"
cp .github/workflows/formal-verification.yml "$stage/sb/.github/workflows/"
git rev-parse HEAD > "$stage/COMMIT"
git status --porcelain > "$stage/DIRTY"

mkdir -p "$(dirname "$out")"
tar czf "$out" -C "$stage" .
echo "payload: $out ($(du -h "$out" | cut -f1)), commit $(cut -c1-12 "$stage/COMMIT"), $(wc -l < "$stage/DIRTY") changed files"
