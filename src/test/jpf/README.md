<!--
SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# JPF interleaving model-check

Exhaustive thread-interleaving verification of `StreamBuffer`'s concurrent read/write/close protocol
with [Java PathFinder](https://github.com/javapathfinder/jpf-core). Where the jcstress
`Mode.Termination` tests (`-Pjcstress`) *stress* the blocking paths under hardware-driven schedules,
JPF *exhaustively enumerates* the interleavings of a small harness — a strictly stronger guarantee
for the schedules it covers. It is the erschöpfende ("exhaustive") counterpart flagged in
[`../../../TODO.md`](../../../TODO.md).

This directory is **not** part of the Maven build (Maven compiles only `src/test/java`). The harness
is compiled with `javac --release 8` and executed by JPF on **JDK 11** (jpf-core's required
runtime). Nothing here reaches the shipped jar.

## What is verified

The harness (`JpfStreamBufferHarness.java`) runs one writer (writes two bytes, then `close()`) and
one reader (`read()` until EOF) over one real `StreamBuffer`, and JPF explores every interleaving,
reporting:

- **deadlocks** — a thread parked forever on the semaphore (lost wakeup),
- **uncaught exceptions** — any thread dying unexpectedly,
- **byte fidelity** — the reader must receive exactly the two bytes, in order, then EOF (an explicit
  `throw`, validated with a negative control so it cannot be vacuous).

Last confirmed run: **no errors detected**, ~14,000 states, maxDepth 130.

## Files

| File | Role |
|---|---|
| `net/ladenthin/streambuffer/jpf/JpfStreamBufferHarness.java` | the model-checked harness (the oracle) |
| `StreamBuffer.jpf` | JPF run configuration (target + classpath) |
| `jpf-model/java/util/concurrent/atomic/AtomicLong.java` | a completed `AtomicLong` model that patches a jpf-core stub (see below) |

## Why the AtomicLong patch

jpf-core (pinned commit `e61e396087983cde00b1e4a5f4b3dde39c0f9f7f`) ships a 2014-era model class for
`java.util.concurrent.atomic.AtomicLong` that declares only legacy `attempt*` helpers, so a class
under model check that calls `addAndGet` (as `StreamBuffer` does for its statistics counters) dies
with `NoSuchMethodError` — even though jpf-core's native peer already implements those methods (they
appear as "orphan NativePeer method" warnings for lack of a matching model declaration).
`jpf-model/.../AtomicLong.java` is jpf-core's model class with the modern surface added; the build
copies it over the stub before compiling jpf-core. This is the only change to jpf-core, and it is a
genuine upstream deficiency worth reporting.

## Run it locally (Docker, no JDK 11 needed on the host)

From the repository root, with `target/classes` already built (`mvn -DskipTests compile`):

```bash
SB="$(pwd)"                       # streambuffer checkout
WORK="$(mktemp -d)"
git clone https://github.com/javapathfinder/jpf-core.git "$WORK/jpf-core"
git -C "$WORK/jpf-core" checkout e61e396087983cde00b1e4a5f4b3dde39c0f9f7f
# apply the AtomicLong model patch
cp "$SB/src/test/jpf/jpf-model/java/util/concurrent/atomic/AtomicLong.java" \
   "$WORK/jpf-core/src/classes/modules/java.base/java/util/concurrent/atomic/AtomicLong.java"

docker run --rm -v "$WORK/jpf-core:/jpf" -v "$SB:/sb" -w /jpf eclipse-temurin:11-jdk bash -lc '
  apt-get update -qq && apt-get install -y -qq git >/dev/null
  git config --global --add safe.directory /jpf
  sed -i "s/\r$//" gradlew            # tolerate a Windows (CRLF) checkout
  ./gradlew --no-daemon buildJars -x test

  cd /sb/src/test/jpf
  rm -rf out streambuffer-classes lib && mkdir -p out streambuffer-classes lib
  cp -r /sb/target/classes/net streambuffer-classes/
  cp "$(find ~/.m2 /root/.m2 -name "checker-qual-*.jar"        2>/dev/null | head -1)" lib/checker-qual.jar
  cp "$(find ~/.m2 /root/.m2 -name "jspecify-*.jar"            2>/dev/null | head -1)" lib/jspecify.jar
  cp "$(find ~/.m2 /root/.m2 -name "error_prone_annotations-*.jar" 2>/dev/null | head -1)" lib/error-prone-annotations.jar
  javac --release 8 -cp streambuffer-classes -d out net/ladenthin/streambuffer/jpf/JpfStreamBufferHarness.java
  java -jar /jpf/build/RunJPF.jar StreamBuffer.jpf
'
```

The annotation jars must be present under an `.m2` the container can see; the CI job resolves them
with `mvn dependency:copy-dependencies` instead. Expected tail: `no errors detected`.
