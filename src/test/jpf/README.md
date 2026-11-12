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

- **deadlocks** — a thread parked forever waiting for data (lost wakeup),
- **uncaught exceptions** — any thread dying unexpectedly,
- **byte fidelity** — the reader must receive exactly the two bytes, in order, then EOF (an explicit
  `throw`, validated with a negative control so it cannot be vacuous).

Last confirmed run (2026-11-11, after bug-hunt fix F278): **no errors detected**, 20,050 states,
maxDepth 143 (13,616 before F278; the separate wait lock adds interleavings).

A second harness (`JpfWriteCloseHarness.java`, run configuration `WriteClose.jpf`) puts the writer,
a separate closer and the reader in three threads, so a write can race the close — which the first
harness cannot show, since its writer closes after its own writes. The writer writes two single
bytes, each of which either succeeds or fails with "Stream closed"; JPF checks over every
interleaving that a write after a failed write fails too, and that the reader receives **exactly**
the bytes whose write returned normally, in order. That is the property bug-hunt finding F149 broke
(a write passed the closed check outside the lock and added its bytes after the reader had already
seen the end). Last confirmed run (2026-11-11): **no errors detected**, 195,915 states (~1:25 min;
75,438 before F278); against the production classes before the F149 fix (`6ece270^`) it reports
"reader got 1 bytes, but 2 writes returned normally" after 3,956 states, so the oracle is not
vacuous.

A third harness (`JpfTwoReadersHarness.java`, run configuration `TwoReaders.jpf`) puts two readers
on the same input stream; the writer writes two bytes and closes. JPF checks that no reader blocks
forever, that no thread dies, and that each byte reaches exactly one reader (a reader that got both
got them in order). That is what bug-hunt finding F278 broke: a write or close woke at most one
waiting reader, and a reader took the first FIFO entry without checking the count again under the
lock. Last confirmed run (2026-11-11): **no errors detected**, 3,530,400 states, maxDepth 190,
about 18 minutes. Against the production classes before the F278 fix (`b3c309e`) it reports the
`NoSuchElementException` after 251 states; with `+search.multiple_errors=true` it finds 24,350
interleavings with that exception and 337 deadlocks in 765,968 states (14 min).

A fourth harness (`JpfRecordReadersHarness.java`, run configuration `RecordReaders.jpf`) checks
fixed-size records with two competing readers: the writer writes the 2-byte records `{1, 2}` and
`{3, 4}` fragmented across the record boundary (`[1]`, then `[2, 3, 4]`) and closes; both readers
call `read(b, 0, 2)` until the end. Every read must return a whole record, and both records must
arrive exactly once. Last confirmed run (2026-11-11, after bug-hunt fix F279): **no errors
detected**, 2,352,249 states, about 12 minutes. Against the read path before `read(b, off, len)` took its bytes in
one step (`a53305b`), it reports "reader 0 got a torn record" after 392 states.

A fifth harness (`JpfWaitAndReadHarness.java`, `WaitAndRead.jpf`) puts a `waitForAtLeast(2)` caller
next to a reader of one byte; the writer writes one byte and closes. The reader must get the byte,
and the waiter may return fewer than two bytes only on a closed buffer (checked right after its
return; closed stays closed). Last confirmed run (2026-11-11): **no errors detected**, 286,494
states, maxDepth 107, about 1.5 minutes. Before F278 (`b3c309e`) it reports a deadlock after 9,009
states: the one permit went to the waiter, which waits for more and went back to waiting.

A sixth harness (`JpfTrimReentrancyHarness.java`, `TrimReentrancy.jpf`) covers trim re-entrancy:
with `maxBufferElements` 1 the second write trims, and the trim start signal writes a byte from
inside the trim, on the writer thread that holds the lock; a reader reads concurrently. The reader
gets `1, 2, 9` when the trim ran and `1, 2` when it took the first byte before the second write
(then there is no trim); the 9 arrives exactly when the signal fired. Last confirmed run: **no
errors detected**, 24,972 states (24,880 before the geometric trim of A14, 2026-11-11); also green before F278 (the defect concerned several
readers). It uses named static classes: with an anonymous `Semaphore` subclass next to lambdas,
jpf-core's `Thread.start` peer failed with a `NullPointerException`.

A seventh harness (`JpfWaitSnapshotHarness.java`, `WaitSnapshot.jpf`) checks what `waitForAtLeast`
returns next to a reader: a writer writes two bytes in one write and closes, one thread calls
`waitForAtLeast(2)`, another `read()`. The result may be fewer than two only once the close has
begun (the writer sets a flag right before `close()`, so a later close cannot excuse a short
result). Before 2026-11-12 the waiting branch read `availableBytes` again after its check and the
reader could take a byte in between: against `main` at `0ac6180` JPF reports `waitForAtLeast(2)
returned 1 before the close began` after 4,845 states (1 s). With the fix: **no errors detected**,
127,525 states, maxDepth 97, 27 s (Vultr, 2026-11-12).

## Files

| File | Role |
|---|---|
| `net/ladenthin/streambuffer/jpf/JpfStreamBufferHarness.java` | the model-checked harness (the oracle) |
| `StreamBuffer.jpf` | JPF run configuration (target + classpath) |
| `net/ladenthin/streambuffer/jpf/JpfWriteCloseHarness.java` | the write/close harness (writer, closer, reader) |
| `WriteClose.jpf` | its JPF run configuration (same classpath) |
| `net/ladenthin/streambuffer/jpf/JpfTwoReadersHarness.java` | the two-readers harness (writer that closes, two readers) |
| `TwoReaders.jpf` | its JPF run configuration (same classpath) |
| `net/ladenthin/streambuffer/jpf/JpfRecordReadersHarness.java` | the record-readers harness (fragmented 2-byte records, two readers) |
| `RecordReaders.jpf` | its JPF run configuration (same classpath) |
| `net/ladenthin/streambuffer/jpf/JpfWaitAndReadHarness.java` | a `waitForAtLeast(2)` caller next to a reader |
| `WaitAndRead.jpf` | its JPF run configuration (same classpath) |
| `net/ladenthin/streambuffer/jpf/JpfTrimReentrancyHarness.java` | a trim start signal writing from inside the trim |
| `TrimReentrancy.jpf` | its JPF run configuration (same classpath) |
| `net/ladenthin/streambuffer/jpf/JpfWaitSnapshotHarness.java` | what `waitForAtLeast(2)` returns next to a reader and a 2-byte write |
| `WaitSnapshot.jpf` | its JPF run configuration (same classpath) |
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
  javac --release 8 -cp streambuffer-classes -d out net/ladenthin/streambuffer/jpf/*.java
  java -jar /jpf/build/RunJPF.jar StreamBuffer.jpf
  java -jar /jpf/build/RunJPF.jar WriteClose.jpf
  java -jar /jpf/build/RunJPF.jar TwoReaders.jpf   # about 18 minutes
  java -jar /jpf/build/RunJPF.jar RecordReaders.jpf   # about 12 minutes
  java -jar /jpf/build/RunJPF.jar WaitAndRead.jpf
  java -jar /jpf/build/RunJPF.jar TrimReentrancy.jpf
  java -jar /jpf/build/RunJPF.jar WaitSnapshot.jpf
'
```

The annotation jars must be present under an `.m2` the container can see; the CI job resolves them
with `mvn dependency:copy-dependencies` instead. Expected tail: `no errors detected`.
