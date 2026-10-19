# Messauftrag zum Bug-Hunt 2026-10-16 … 19 — streambuffer

Dieser Auftrag sammelt die Läufe, die der Bug-Hunt offen gelassen hat. Hintergrund: `BUGHUNT-FOUND.md`
(F73, F149) und `TODO.md` („Run the concurrency and formal-verification suites after the write/close fix“).

**Regeln für den ausführenden Agenten**

- **Nur laufen lassen und berichten.** Keine Produktionsänderung, keine Fixes; committet wird nur diese
  Datei mit den Ergebnissen.
- Arbeitsstand: Branch `ccr-90fc5f6a-vs4s0f`.
- Dateien aus `.github/shared-files.sha256` nicht verändern.
- Jeder Punkt wird beantwortet (sonst mit Grund). Zu jedem Ergebnis die Umgebung (CPU, Kerne, OS, JDK) und
  die wörtlichen Ausgaben, die es tragen (jcstress-Tabelle, Beweiszahl, Testzahlen).
- Ergebnis unter **Ergebnis:**, darunter **Folgerung:**.

---

## Messumgebung (Ergebnisse vom 2026-10-19)

Ausgeführt am 2026-10-19, lokal auf einer Wegwerf-VM (kein `workflow_dispatch`, Entscheidung des Auftraggebers).
Keine Datei im Repository geändert außer dieser; die Wegwerf-Harness aus S4 lag nur auf der VM.

**Gemeinsame Umgebung (gilt für alle Punkte)**

- Stand: Branch `ccr-90fc5f6a-vs4s0f`, `0a3b488fd64eee785dd55433c6ff9f1ea0e52c50` („Add the measurement brief
  for the open points of the bug hunt“), frisch von GitHub geklont; jeder Punkt in einer eigenen Kopie des Klons.
- Maschine: Vultr-VM, `AMD EPYC-Rome Processor` (virtualisiert, QEMU `pc-q35-8.2`), 8 vCPU = 1 Sockel ×
  4 Kerne × 2 Threads, 16 GB RAM, Ubuntu 24.04.5 LTS, Kernel `6.8.0-146-generic`.
- JDK für Maven, jcstress, vmlens und den RAC-Build: Temurin `21.0.12.1+1` (`.java-version` = 21).
- JDK für JPF: Temurin `11.0.32.1+1`.
- Maven `3.9.11`.
- OpenJML `21.0.28` aus `openjml-ubuntu-24.04-21.0.28.zip`, SHA-256 gegen den Wert im Workflow geprüft
  (`/tmp/openjml.zip: OK`), Fixups wie `.github/actions/setup-openjml` (die beiden JML-Dateien gelöscht,
  `JAVA_VERSION` in `jdk/release` ergänzt). Der RAC-Testlauf forkt die mitgelieferte JVM von OpenJML.
- jcstress 0.16, vmlens 1.2.28, jpf-core `e61e396087983cde00b1e4a5f4b3dde39c0f9f7f` (mit dem
  AtomicLong-Modell aus `src/test/jpf/jpf-model`).
- Die Punkte liefen nacheinander, jcstress (S1) allein auf der Maschine. Nur RAC-Lauf 1 (S3) lief
  zeitweise neben JPF, S4 und einem gezielten RAC-Zusatzlauf. RAC-Lauf 2 lief allein.

---

## S1 jcstress: Schreiben gegen `close()`

`writeFromArray` prüft `streamClosed` seit F149 unter `bufferLock`, `closeAll()` setzt es unter derselben
Sperre. Der neue Test `jcstress/WriteRacingCloseRace` (Schreiber, Schließer, Leser) verbietet das Ergebnis
`1, -1` (Schreiben erfolgreich, Leser sah aber schon das Ende).

```bash
mvn -B -Pjcstress test
```

Den Abschnitt zu `WriteRacingCloseRace` und zu den bestehenden `Close*`/`Write*`-Tests aus dem Bericht
übernehmen (Ergebnisse je Outcome mit Häufigkeit).

**Hypothese.** Kein `FORBIDDEN`-Ergebnis, alle übrigen Tests wie vorher.
**Entscheidet.** Ob F149 unter echter Nebenläufigkeit hält.

**Ergebnis:** `mvn -B -Pjcstress test`: `BUILD SUCCESS`, `Total time:  34:21 min`. Davor lief im selben Aufruf die
normale Surefire-Phase: `Tests run: 299, Failures: 0, Errors: 0, Skipped: 0`.

jcstress-Konfiguration (wörtlich):

```
    Test preset mode: "default"
    Hardware CPUs in use: 8
    Spinning style: Thread.onSpinWait()
    Test selection: ".*"
    Forks per test: 1 normal, 5 stress
    Iterations per fork: 5
    Time per iteration: 1000 ms
```

Gesamturteil (wörtlich):

```
(Results: 604 planned; 604 passed, 0 failed, 0 soft errs, 0 hard errs)

RUN RESULTS:
  Interesting tests: No matches.

  Failed tests: No matches.

  Error tests: No matches.

  All remaining tests: 8 matching test results.
```

Ergebnisse über alle Konfigurationen (wörtlich aus dem Bericht):

```
.......... [OK] net.ladenthin.streambuffer.jcstress.WriteRacingCloseRace

  RESULT        SAMPLES     FREQ      EXPECT  DESCRIPTION
   0, -1  2,341,015,301   66.14%  Acceptable  close before write, the write failed
   1, -1              0    0.00%   Forbidden  write succeeded but the reader already saw the end
    1, 7  1,198,259,507   33.86%  Acceptable  write before close, reader got the byte

.......... [OK] net.ladenthin.streambuffer.jcstress.CloseDuringReadRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  Reader stuck after close()
  TERMINATED   42,869  100.00%  Acceptable  close() unblocked the reader

.......... [OK] net.ladenthin.streambuffer.jcstress.CloseUnblocksArrayReadRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  Array reader stuck after close()
  TERMINATED   39,215  100.00%  Acceptable  close() unblocked the array reader

.......... [OK] net.ladenthin.streambuffer.jcstress.CloseUnblocksWaitForAtLeastRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  waitForAtLeast stuck after close()
  TERMINATED   33,728  100.00%  Acceptable  close() unblocked waitForAtLeast

.......... [OK] net.ladenthin.streambuffer.jcstress.ConcurrentWriteRace

  RESULT        SAMPLES     FREQ      EXPECT  DESCRIPTION
   false              0    0.00%   Forbidden  Torn / interleaved write
    true  1,495,618,828  100.00%  Acceptable  Both payloads intact in some order

.......... [OK] net.ladenthin.streambuffer.jcstress.WriteUnblocksArrayReadRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  Array reader stuck after write()
  TERMINATED   33,599  100.00%  Acceptable  write() unblocked the array reader

.......... [OK] net.ladenthin.streambuffer.jcstress.WriteUnblocksReadRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  Reader stuck after write()
  TERMINATED   33,639  100.00%  Acceptable  write() unblocked the reader

.......... [OK] net.ladenthin.streambuffer.jcstress.WriteUnblocksWaitForAtLeastRace

      RESULT  SAMPLES     FREQ      EXPECT  DESCRIPTION
       STALE        0    0.00%   Forbidden  waitForAtLeast stuck after write()
  TERMINATED   36,257  100.00%  Acceptable  write() unblocked waitForAtLeast
```

**Folgerung:** Die Hypothese gilt. Bei rund 3,54 Milliarden Proben von `WriteRacingCloseRace` kam der
verbotene Ausgang `1, -1` kein einziges Mal vor. Beide erlaubten Ausgänge traten häufig auf (66 % / 34 %),
das Rennen wurde also tatsächlich von beiden Seiten getroffen. Die sieben bestehenden `Close*`/`Write*`-
und `ConcurrentWrite*`-Tests sind grün. Auch nachdem `close()` jetzt `bufferLock` nimmt, gab es keinen
`STALE`-Ausgang und keine zerrissene Schreiboperation. F149 hält unter echter Nebenläufigkeit auf dieser
Hardware (x86, also TSO; zu ARM sagt der Lauf nichts). jcstress ist ein Stresstest und kein Beweis. Den
Beweis für die Reihenfolge Schreiben/Schließen liefert S4.

---

## S2 vmlens: Leser/Schreiber-Verschränkungen

```bash
mvn -B -Pvmlens test
```

**Hypothese.** Grün.
**Ergebnis:** `mvn -B -Pvmlens test`: `BUILD SUCCESS` (Exit 0). Die normale Surefire-Phase im selben Aufruf ergab
`Tests run: 299, Failures: 0, Errors: 0, Skipped: 0`. Danach lief der vmlens-Agent (`agent started, Build: 1.2.28`):

```
[INFO] Running net.ladenthin.streambuffer.vmlens.StreamBufferReaderWriterInterleavingTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 1.639 s -- in net.ladenthin.streambuffer.vmlens.StreamBufferReaderWriterInterleavingTest
[INFO] Running net.ladenthin.streambuffer.vmlens.VmlensInterleavingSmokeTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.096 s -- in net.ladenthin.streambuffer.vmlens.VmlensInterleavingSmokeTest
...
[INFO] Tests run: 290, Failures: 0, Errors: 0, Skipped: 0
[INFO] See /root/sb-s2/target/vmlens-report for the vmlens report.
[INFO] BUILD SUCCESS
```

vmlens-Bericht (`target/vmlens-report/index.html`, als Text):

```
#  Name                                       Count  Result
0  StreamBuffer.readerWriterAccounting          19   Success
1  VmlensInterleavingSmokeTest.atomicIncrements  2   Success
```

**Folgerung:** Grün, die Hypothese gilt. vmlens hat 19 Verschränkungen des Leser/Schreiber-Tests
durchlaufen, ohne Fehler und ohne gemeldetes Datenrennen. Die Lock-Änderung aus F149 (`requireNonClosed()`
unter `bufferLock`) hat die Byte-Buchhaltung zwischen Schreiber und Leser also nicht beschädigt. Der
vmlens-Test enthält kein `close()` und sagt deshalb nichts über das Rennen aus F149 selbst. Das decken S1
und S4 ab.

---

## S3 Formale Verifikation (OpenJML ESC + RAC, JPF) — deckt auch F73 ab

Die Pipeline `formal-verification.yml` läuft auf Pull Requests und per `workflow_dispatch`; auf dem Branch
auslösen und Run-ID eintragen, oder lokal nach CLAUDE.md („Formal Verification“). Zu prüfen:

- **ESC:** die Beweiszahl muss `ESC_EXPECTED_PROOFS` (14) sein, der Umfang ist unverändert.
- **RAC:** die ganze Suite gegen die instrumentierten Klassen, mit dem neuen Test
  `StreamBufferTest$ConcurrentWriteAndCloseTests` und dem in F73 geänderten `trim` (lief nie unter RAC).
- **JPF:** der Job `jpf-interleavings`.

**Hypothese.** ESC 14/14, RAC grün, JPF grün.
**Entscheidet.** Ob F73 und F149 die Spezifikationen und das Sperrprotokoll einhalten.

**Ergebnis:** **ESC.**

```
Completed proving methods in net.ladenthin.streambuffer.StreamBuffer [26.32 secs]
Summary:
  Valid:        14
  Invalid:      0
  Infeasible:   0
  Timeout:      0
  Error:        0
  Skipped:      52
 TOTAL METHODS: 66
 Classes:       0 proved of 3
 DURATION:         26.6 secs

== Guard ==
Completed clean proofs: 14 (expected: 14)
```

Bewiesen wurden genau die 14 Methoden aus `ESC_METHODS`, jede mit `Completed proof of … - no warnings`
(Prover `z3-5.1.0`): `calculateResultingChunks`, `clampToMaxInt`, `decideTrimExecution`,
`decrementAvailableBytesBudget`, `isAvailableBytesPositive`, `isMaxAllocSizeLessThanAvailable`,
`shouldCheckEdgeCase`, `shouldSkipTrimDueToEdgeCase`, `shouldSkipTrimDueToInvalidMaxBufferElements`,
`shouldSkipTrimDueToSmallBuffer`, `shouldSkipTrimDueToSufficientBuffer`, `shouldUpdateMaxObservedBytes`,
`validateOffsetAndLengthToRead`, `validateOffsetAndLengthToWrite`. Exit 0.

**RAC.**

Kompilieren mit `openjml --rac --rac-show-source=line --code-math=java --spec-math=java …`: ohne Fehler.
Guard: `RAC instrumentation present (org/jmlspecs referenced)`.

Voller Suite-Lauf `mvn -B --no-transfer-progress -P jml-rac -Dopenjml.home=… -Dopenjml.jdk.java=…/jdk/bin/java test`:

**Lauf 1 (ganze Suite, ohne Ausschluss) – abgebrochen, ohne Ergebnis.** Er startete um 10:36:26Z. Der
Test `StreamBufferTest$ConcurrentTrimAndWriteTests#waitForAtLeast_concurrentTrim_neverReturnsFewerBytesThanRequested`
(F73) lief unter RAC gut zwei Stunden und blieb dabei grün:

```
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 7344 s -- in concurrent trim and write
```

(Der zweite Test der Klasse, `concurrentTrimAndWrite_noCrashOrCorruption`, braucht unter RAC 0,3 s, siehe
Lauf 2.) Der Test macht 2.000.000 Einzelbyte-`write`s mit `maxBufferElements` 1000, also rund 2.000
Trims zu je etwa 1.000 Einträgen. Der F73-`trim` ruft für jeden Eintrag `System.arraycopy` auf. Für jeden
dieser Aufrufe gibt RAC einen Hinweis samt Stacktrace aus (≈10 KB), weil die mitgelieferte JDK-Spezifikation
eine nicht kompilierte Modellmethode benutzt:

```
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.util.Arrays.equalArrays
java.lang.NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], org.jmlspecs.lang.internal.bigint, byte[], org.jmlspecs.lang.internal.bigint, org.jmlspecs.lang.internal.bigint)'
	at net.ladenthin.streambuffer.StreamBuffer.trim(StreamBuffer.java:302)
	at net.ladenthin.streambuffer.StreamBuffer.writeFromArray(StreamBuffer.java:1048)
	at net.ladenthin.streambuffer.StreamBuffer.writeSingleByte(StreamBuffer.java:989)
	at net.ladenthin.streambuffer.StreamBuffer$SBOutputStream.write(StreamBuffer.java:1096)
	at net.ladenthin.streambuffer.StreamBufferTest$ConcurrentTrimAndWriteTests.waitForAtLeast_concurrentTrim_neverReturnsFewerBytesThanRequested(StreamBufferTest.java:2194)
```

Bis zum Abbruch kam das 2.003.546-mal vor. Das Log wuchs auf 20.985.623.867 Bytes (196.240.539 Zeilen).
Die Laufzeit begrenzt dabei nicht der Test selbst, sondern das Durchreichen der Ausgabe über surefire. Der
Thread-Dump der surefire-Fork (`jcmd 665138 Thread.print`, 12:50:52Z) zeigt den Test-Thread beim
Schreiben auf diesem Kanal:

```
"main" #1 [665139] prio=5 os_prio=0 cpu=7296572.50ms elapsed=8050.14s tid=0x0000722980028030 nid=665139 runnable  [0x0000722986111000]
   java.lang.Thread.State: RUNNABLE
	at java.io.FileOutputStream.writeBytes(java.base/Native Method)
	...
	at org.apache.maven.surefire.booter.spi.EventChannelEncoder.testOutput(EventChannelEncoder.java:168)
	...
	at java.lang.Throwable.printStackTrace(java.base/Throwable.java:673)
```

`@Timeout(60)` greift unter RAC nicht, weil das Profil `jml-rac` mit
`junit.jupiter.execution.timeout.mode=disabled` alle JUnit-Timeouts abschaltet. Um ~12:50:46Z wurde die
Fork beendet (im Dump steht ein `"SIGTERM handler"`-Thread mit `elapsed=4.86s`): Die koordinierende Sitzung hielt
den Lauf nach 2 h 14 min für hängend und schickte SIGTERM, danach SIGKILL. Das war eine Fehldeutung — zu diesem
Zeitpunkt lief schon ein späterer Test
(`MaxAllocationSizeTests.trim_recursiveTrim_onChunkOverflow_allDataPreserved`). Danach habe ich den
Maven-Prozess beendet. Lauf 1 liefert also keine Gesamtzahl. Im gefilterten Log bis zum Abbruch steht
kein einziges `Failures: [1-9]`, `Errors: [1-9]` und kein `JmlAssertionError`.

**Lauf 2 (ganze Suite, ein Ausschluss, Obergrenze `timeout 45m`).** Alle Workflow-Schritte liefen in einer
frischen Kopie neu (Klassenpfad, RAC-Kompilat, Guard `RAC instrumentation present (org/jmlspecs referenced)`).
Ausgeschlossen war nur diese eine Testmethode, über `-Dsurefire.excludesFile=/root/rac-excludes.txt` mit
dem Inhalt

```
StreamBufferTest$ConcurrentTrimAndWriteTests#waitForAtLeast_concurrentTrim_neverReturnsFewerBytesThanRequested
```

(Die Excludes-Datei wird an die `<excludes>` des Profils angehängt. `-Dtest` hätte diese ersetzt.)
Ergebnis, wörtlich:

```
[INFO] Running concurrent trim and write
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.316 s -- in concurrent trim and write
[INFO] Running concurrent write and close
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.011 s -- in concurrent write and close
[INFO] Running concurrent read/write
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 753.6 s -- in concurrent read/write
...
[INFO] Tests run: 0, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 824.4 s -- in net.ladenthin.streambuffer.StreamBufferTest
[ERROR] Surefire is going to kill self fork JVM. The exit has elapsed 30 seconds after System.exit(0).
[INFO] Tests run: 287, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
real	17m16.471s
EXIT=0
```

Prüfung im surefire-Bericht (`TEST-net.ladenthin.streambuffer.StreamBufferTest.xml`): `tests="287"
errors="0" skipped="0" failures="0"`. Die ausgeschlossene Methode kommt 0-mal vor. Gelaufen sind unter
anderem `ConcurrentWriteAndCloseTests#write_closedWhileTheWriterWaitsForTheLock_failsInsteadOfAppendingAfterTheClose`,
`ConcurrentTrimAndWriteTests#concurrentTrimAndWrite_noCrashOrCorruption`, `TrimTests` (2),
`TrimWithPartialBufferEntryTests`, `TrimWithSafeWriteTests`, `MaxAllocationSizeTests` (18, darunter alle
`trim_*`), `BufferElementCountAndTrimStateTests`, `MaxBufferElementsZeroDisablesTrimTests`, die
`trim_*`-Tests in `ExceptionSafetyAndSignalManagementTests` und `MutationSurvivorTests` (u. a.
`trim_closeCalledDuringTrim_handlesGracefully`) sowie `ReadTests#read_afterTrimAndClose_returnsRemainingBytesThenEOF`.
Im Vergleich zum normalen Lauf (`StreamBufferTest` 288) fehlt genau die eine ausgeschlossene Methode.

Auch Lauf 2 hatte einen langsamen Test, der aber nicht hängt: `ConcurrentReadWriteTests#safeWrite_concurrentSingleByteWrite_arrayStillCloned`
(200.000 `write(byte[8])` mit `safeWrite`). Für jedes `b.clone()` unter `bufferLock` gibt RAC einmal
`java.lang.NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], byte[])'` samt Stacktrace aus.
Das kam genau 200.000-mal vor, die Klasse brauchte 753,6 s. Ein Thread-Dump während des Laufs zeigt `main`
RUNNABLE beim Erzeugen eines Stacktraces, Schreiber und Leser BLOCKED auf `bufferLock`. Der Fortschritt
war messbar (13:09:40Z 179.711, 13:13:42Z 200.000 der 200.000 Schreibvorgänge), danach lief der Test
grün durch. Ein zweiter Ausschluss war deshalb nicht nötig. Die Meldung `[ERROR] Surefire is going to kill
self fork JVM …` betrifft das Herunterfahren nach dem letzten Test: Laut Dump wartete die Fork auf die
Bestätigung des Exits, während Maven noch den Ausgabe-Rückstau las.

Wie in Lauf 1 meldet RAC einmal in `thread interruption during read()`
`JML undefined exceptional postcondition - exception thrown` /
`java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException`.
RAC wertet die Klausel `signals (IllegalArgumentException e) bytes <= 0;` von `waitForAtLeast` auch dann
aus, wenn eine `InterruptedException` geworfen wurde. Das sieht nach einem OpenJML-Fehler bei der
`signals`-Typprüfung aus, nicht nach einer verletzten Vorgabe. Mit `rac=exception` würde eine Verletzung
werfen, der Test blieb aber grün.

Gezielter Zusatzlauf (gleiche RAC-Klassen, gleiches Profil, nur
`-Dtest=StreamBufferTest$ConcurrentWriteAndCloseTests,…$TrimTests,…$TrimWithPartialBufferEntryTests,…$TrimWithSafeWriteTests,…$MaxAllocationSizeTests,…$BufferElementCountAndTrimStateTests,…$MaxBufferElementsZeroDisablesTrimTests`),
gestartet, um den neuen F149-Test und die `trim`-Tests früh unter RAC zu sehen:

```
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.367 s -- in trim()
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.007 s -- in maxBufferElements=0 disables trim
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.052 s -- in buffer element count and trim state
[INFO] Tests run: 18, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 3.653 s -- in maxAllocationSize: getter, setter, trim behavior
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.011 s -- in concurrent write and close
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.016 s -- in trim() — partial buffer entry
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.021 s -- in trim() with safeWrite enabled
[INFO] Tests run: 28, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
real	0m15.966s
```

**JPF (`jpf-interleavings`).**

Produktionsklassen mit JDK 21 gebaut (`BUILD SUCCESS`). Annotation-JARs bereitgestellt
(`checker-qual-4.3.1.jar`, `error_prone_annotations-2.50.0.jar`, `jspecify-1.0.1.jar`). jpf-core mit
JDK 11 gebaut (`BUILD SUCCESSFUL in 20s`). Harness mit `javac --release 8` übersetzt und unter JDK 11
geprüft:

```
JavaPathfinder core system v8.0 (rev e61e396087983cde00b1e4a5f4b3dde39c0f9f7f) - (C) 2005-2014 United States Government. All rights reserved.

====================================================== system under test
net.ladenthin.streambuffer.jpf.JpfStreamBufferHarness.main()

====================================================== results
no errors detected

====================================================== statistics
elapsed time:       00:00:02
states:             new=13616,visited=17704,backtracked=31320,end=30
search:             maxDepth=127,constraints=0
choice generators:  thread=13614 (signal=0,lock=1453,sharedRef=6979,threadApi=652,reschedule=4250), data=0
heap:               new=11650,released=6631,maxLive=718,gcCycles=31184
instructions:       853148
max memory:         300MB
loaded code:        classes=122,methods=3245

== Gate ==
states: new=13616
```

Das Gate des Workflows ist bestanden (kein `^error #`, `no errors detected` vorhanden). Exit 0.

**Folgerung:** - **ESC 14/14.** Die Beweiszahl stimmt mit `ESC_EXPECTED_PROOFS` überein, der Umfang ist unverändert
  (die 14 Methoden aus `ESC_METHODS`). F73 und F149 haben keinen der bewiesenen statischen Helfer berührt.
- **RAC grün, mit einem Ausschluss.** Ausgeschlossen war nur
  `ConcurrentTrimAndWriteTests#waitForAtLeast_concurrentTrim_neverReturnsFewerBytesThanRequested`. Die
  übrigen 287 Tests laufen gegen die instrumentierten Klassen grün, ohne eine einzige Vertragsverletzung
  (`rac=exception`). Darunter sind der neue F149-Test `ConcurrentWriteAndCloseTests` und alle `trim`-Tests,
  also auch der in F73 geänderte `trim`, der damit zum ersten Mal unter RAC lief. Der ausgeschlossene Test
  lief in Lauf 1 ebenfalls grün (`Tests run: 2, Failures: 0 … 7344 s`). Ein vollständiger Lauf aller 288
  Tests in einem Stück liegt aber nicht vor, weil Lauf 1 (irrtümlich als hängend) abgebrochen wurde.
- **Für die CI wichtig, eine Messung und keine Vorhersage aus einem CI-Lauf.** Im Job `openjml-rac`
  (`timeout-minutes: 30`, Runner mit 2 Kernen) passt der F73-Test unter RAC nicht ins Zeitlimit. Lokal
  brauchte er auf 8 vCPU allein 7.344 s und erzeugte rund 21 GB Log. Der Job würde also vermutlich rot
  (Timeout), ohne dass ein Vertrag verletzt ist. Die Ursache ist kein Hänger: Der Test ist für den
  Produktionspfad bemessen (2 Mio. Writes, `@Timeout(60)`), RAC schaltet die Timeouts ab und gibt pro
  `System.arraycopy`/`clone` einen Stacktrace aus. Abhilfe wäre zu entscheiden (Test im Profil `jml-rac`
  ausschließen oder kleiner skalieren). Das ist hier nicht gemacht, weil der Auftrag keine Änderungen erlaubt.
- **JPF grün** (`no errors detected`, 13.616 Zustände, maxDepth 127, wie dokumentiert „~14,000 states,
  maxDepth 130“).
- Insgesamt halten F73 und F149 die Spezifikationen und das bestehende Sperrprotokoll ein, soweit ESC,
  RAC und das heutige JPF-Harness reichen. Die Reihenfolge Schreiben/Schließen deckt erst S4 ab.
- **Nebenbefund, nicht Teil des Auftrags:** `StreamBufferProperties` (jqwik, 5 `@Property`) erscheint in
  keinem surefire-Lauf, weder im normalen (`Tests run: 299` = `StreamBufferTest` 288 +
  `StreamBufferArchitectureTest` 10 + `StreamBufferLincheckTest` 1) noch unter vmlens oder RAC. Der
  Klassenname passt nicht auf die Standard-Includes von surefire (`*Test`, `*Tests`, `Test*`, `*TestCase`),
  und die pom setzt keine eigenen Includes. CLAUDE.md („picked up by Surefire as a JUnit 6 engine“) und der
  Kommentar im Profil `jml-rac` („… and the jqwik properties (StreamBufferProperties)“) sagen etwas anderes.
  Nicht weiter untersucht.

---

## S4 Optional: JPF-Harness mit einem dritten Thread, der schließt

Das heutige Harness (`src/test/jpf/`) schreibt und schließt aus demselben Thread und sieht das Rennen aus
F149 deshalb nicht. Ein Wegwerf-Harness mit Schreiber-, Schließer- und Leser-Thread, erschöpfend modellgeprüft,
würde die Reihenfolge Schreiben/Schließen beweisen. Ergebnis und Harness-Quelltext hier eintragen, nicht
committen.

**Entscheidet.** Ob das erweiterte Harness dauerhaft aufgenommen werden soll.

**Ergebnis:** Die Wegwerf-Harness `JpfWriteCloseHarness` wurde nur auf der VM angelegt (`/root/s4src`, Arbeitskopien
`/root/s4-*`) und nicht ins Repository übernommen. Sie lief mit derselben jpf-core-Build und denselben
Annotation-JARs wie der JPF-Job oben, mit `--release 8` übersetzt und unter JDK 11 geprüft. Es gibt drei
Threads: Der Schreiber schreibt zwei Einzelbytes, der Schließer ruft `sb.close()` auf, der Leser liest
bis `-1`. Das Orakel nach dem Join prüft:

- Ein `write` nach einem gescheiterten `write` darf nicht mehr gelingen.
- Der Leser erhält **genau** die Bytes, deren `write` normal zurückkehrte, in der richtigen Reihenfolge.

Dazu kommen die JPF-Eigenschaften Deadlock und nicht gefangene Exception.

Konfiguration `WriteClose.jpf`:

```
target = net.ladenthin.streambuffer.jpf.JpfWriteCloseHarness
classpath = ${config_path}/out;${config_path}/streambuffer-classes;${config_path}/lib/checker-qual.jar;${config_path}/lib/jspecify.jar;${config_path}/lib/error-prone-annotations.jar
vm.enable_assertions = true
```

Quelltext:

```java
// Throwaway JPF harness for BUGHUNT-MEASUREMENTS.md S4 -- NOT committed.
package net.ladenthin.streambuffer.jpf;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import net.ladenthin.streambuffer.StreamBuffer;

/**
 * Writer, closer and reader in three separate threads over one StreamBuffer (bug-hunt F149).
 * The writer writes two single bytes; each write either succeeds or fails with "Stream closed".
 * Oracle over every interleaving JPF enumerates:
 *  - no deadlock, no uncaught exception (JPF properties);
 *  - once a write failed, every later write fails too (close is sticky);
 *  - the reader, which reads until -1, receives EXACTLY the bytes whose write returned normally,
 *    in order -- a successful write is ordered before the close and never lost for the reader.
 */
public final class JpfWriteCloseHarness {

    private JpfWriteCloseHarness() {}

    public static void main(String[] args) throws Exception {
        final StreamBuffer sb = new StreamBuffer();
        final OutputStream os = sb.getOutputStream();
        final InputStream is = sb.getInputStream();

        final byte[] payload = {0x41, 0x42};
        final boolean[] ok = new boolean[payload.length];

        final Thread writer = new Thread(() -> {
            for (int i = 0; i < payload.length; i++) {
                try {
                    os.write(payload[i]);
                    ok[i] = true;
                } catch (IOException e) {
                    ok[i] = false;
                }
            }
        });

        final Thread closer = new Thread(() -> {
            try {
                sb.close();
            } catch (IOException e) {
                throw new AssertionError("close must not fail", e);
            }
        });

        final byte[] got = new byte[payload.length + 1];
        final int[] count = {0};

        final Thread reader = new Thread(() -> {
            try {
                int c;
                while ((c = is.read()) != -1) {
                    if (count[0] < got.length) {
                        got[count[0]] = (byte) c;
                    }
                    count[0]++;
                }
            } catch (IOException e) {
                throw new AssertionError("reader must not fail", e);
            }
        });

        writer.start();
        closer.start();
        reader.start();
        writer.join();
        closer.join();
        reader.join();

        int succeeded = 0;
        for (int i = 0; i < payload.length; i++) {
            if (ok[i]) {
                if (i != succeeded) {
                    throw new AssertionError("write " + i + " succeeded after an earlier write failed");
                }
                succeeded++;
            }
        }
        if (count[0] != succeeded) {
            throw new AssertionError("reader got " + count[0] + " bytes, but " + succeeded
                    + " writes returned normally (F149: write succeeded after the reader saw EOF)");
        }
        for (int i = 0; i < succeeded; i++) {
            if (got[i] != payload[i]) {
                throw new AssertionError("byte " + i + " corrupted");
            }
        }
    }
}
```

Lauf gegen den Stand des Branches (`0a3b488`, mit F149-Fix):

```
====================================================== system under test
net.ladenthin.streambuffer.jpf.JpfWriteCloseHarness.main()

====================================================== results
no errors detected

====================================================== statistics
elapsed time:       00:00:15
states:             new=75438,visited=151499,backtracked=226937,end=72
search:             maxDepth=135,constraints=0
choice generators:  thread=75433 (signal=0,lock=6451,sharedRef=39211,threadApi=1358,reschedule=26614), data=0
heap:               new=93087,released=49976,maxLive=751,gcCycles=216153
instructions:       5688950
max memory:         250MB
loaded code:        classes=126,methods=3283
```

Negativkontrolle: dieselbe Harness gegen die Produktionsklassen **vor** dem F149-Fix (`1529d3b^` =
`b54b620`, mit JDK 21 gebaut). Damit ist gezeigt, dass das Orakel nicht leer ist:

```
====================================================== error 1
gov.nasa.jpf.vm.NoUncaughtExceptionsProperty
java.lang.AssertionError: reader got 1 bytes, but 2 writes returned normally (F149: write succeeded after the reader saw EOF)

====================================================== results
error #1: gov.nasa.jpf.vm.NoUncaughtExceptionsProperty "java.lang.AssertionError: reader got 1 bytes, but ..."

====================================================== statistics
elapsed time:       00:00:01
states:             new=3956,visited=5948,backtracked=9836,end=18
```

**Folgerung:** Mit dem Fix ist die Harness über alle von JPF aufgezählten Verschränkungen fehlerfrei
(75.438 neue Zustände, 15 s). Ohne den Fix findet JPF das Rennen aus F149 nach 3.956 Zuständen in 1 s:
Der Leser meldet `-1` nach einem Byte, danach kehrt der zweite `write` normal zurück. Die Harness sieht
also genau den Fehler, den das heutige Harness nicht sehen kann, und beweist für dieses kleine Modell
(zwei Bytes, ein Schließer) die Reihenfolge Schreiben/Schließen. Kosten: etwa 5,5-mal so viele Zustände
wie das heutige Harness (13.616), Laufzeit weiter im Sekundenbereich. Aus Sicht der Messung spricht nichts
dagegen, sie dauerhaft aufzunehmen, etwa als zweites `target` im Job `jpf-interleavings`. Die Entscheidung
liegt beim Nutzer.

---

## OpenJML-Verdachtsfälle (RAC)

Zwei Verdachtsfälle aus S3 (TODO.md, „Formal verification — follow-ups“) wurden am 2026-10-19 geprüft:
in streambuffer, mit eigenständigen Minimalreproduzenten und gegen einen selbst gebauten OpenJML-`dev-21`.
Beide Befunde wurden am 2026-10-19 in einem Issue gemeldet: [OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050). Die Rohlogs sind nicht ins Repository übernommen.

**Umgebung**

- Maschine: DigitalOcean-Droplet, 4 geteilte vCPU (`lscpu`: `DO-Regular`), 8 GB RAM (plus 8 GB Swapfile, für den
  Build angelegt), 160 GB Platte, Ubuntu 24.04.5 LTS, Kernel `6.8.0-142-generic`.
- JDK für Maven und den dev-21-Build: Temurin `21.0.12.1+1`. Maven `3.9.11`.
- streambuffer: Branch `ccr-90fc5f6a-vs4s0f`, `98000f5` („Record the two suspected OpenJML defects and drop the done
  measurement item“), frisch von GitHub geklont.
- **OpenJML 21.0.28:** `openjml-ubuntu-24.04-21.0.28.zip`, SHA-256 gegen den Workflow-Wert geprüft
  (`/root/openjml.zip: OK`). Fixups genau wie in `.github/actions/setup-openjml`: `rm specs/java/util/ArrayDeque.jml`,
  `rm specs/java/util/concurrent/atomic/AtomicLong.jml` und `JAVA_VERSION="21"` an `jdk/release` angehängt.
  `openjml --version` gibt `openjml 21.0.28` aus. Laut `version-info.txt` wurde der Build aus OpenJML `01a0fe69db3d`
  und Specs `1a91cb699082` erzeugt. Der Tag `21.0.28` zeigt auf `5df29e0f52c8`. `JmlAssertionAdder.java` und
  `runtime/Utils.java` sind in beiden Commits byteidentisch. Die Zeilenangaben unten gelten daher für beide.
- **OpenJML dev-21:** selbst gebaut nach `.github/workflows/build.yml` und den Actions `os-setup`, `openjml-checkout`
  und `openjml-build`. Dazu gehörten die apt-Pakete aus `os-setup`, flache Klone von OpenJML `dev-21`
  (`529ac454da0ab45ed1c103b7206fa8b6dc04d7dc`, Stand 2026-10-17, 232 Commits nach 21.0.28) und Specs `dev-21`
  (`dc9f6be7c095`), außerdem OpenJMLDemo, JMLAnnotations und openjml.github.io sowie ein sparse-Checkout von
  `smtlib/Solvers` (`Solvers-linux`). Danach `./configure && make release`. Der Start war um 15:19:04 UTC.
  `Finished building target 'default (exploded-image)'` kam gegen 15:44 UTC, nach rund 25 Minuten.
  `make release` brach danach in `post → openjml-lsp → vsix` ab: `/bin/sh: 1: npm: not found` / `make[3]: *** [Makefile:121: vsix] Error 127`.
  Dieser Schritt baut nur die VS-Code-Erweiterung und ist für RAC unerheblich.
  Die Distribution wurde deshalb von Hand so zusammengesetzt, wie `post` das Zip baut: `release-temp/` plus
  `cp -rL build/linux-x86_64-server-release/jdk` plus `Solvers-linux`. `JAVA_VERSION` kam mit der Regel aus dem
  `post`-Target dazu. `openjml --version` gibt `openjml 21.0.28a` aus. `version-info.txt` nennt `OpenJML 529ac454da0a…`
  und `Specs dc9f6be7c095…`. Auf dev-21 wurden keine Spezifikationsdateien gelöscht.
- RAC-Programme liefen immer mit der JVM von OpenJML (`<openjml>/jdk/bin/java`), mit `jmlruntime.jar` im Klassenpfad.

---

### Verdacht 1: `signals (E e) P` wird für eine Ausnahme eines anderen Typs ausgewertet

**Ergebnis:** **Bestätigt, aber enger als vermutet.** Der Fehler steckt im Code, den RAC **an der Aufrufstelle**
erzeugt, um die Ausnahme-Nachbedingungen des Aufgerufenen zu prüfen. Am Aufgerufenen selbst tritt er nicht auf. Er
zeigt sich nur, wenn das `signals`-Prädikat nach dem Einsetzen der tatsächlichen Argumente zum Literal `false` gefaltet
wird. In streambuffer passiert das, weil `waitForAnyData()` `waitForAtLeast(1L)` aufruft: Aus `bytes <= 0` wird dort
`1L <= 0`, also `false`.

Dann entfällt der `instanceof`-Schutz, der Cast `(IllegalArgumentException) exception` bleibt aber stehen. Eine
`InterruptedException` (von `signals_only` erlaubt) löst dadurch eine `ClassCastException` aus. RAC fängt sie ab und
meldet `JML undefined exceptional postcondition - exception thrown`.

- Bestätigt in streambuffer, auf 21.0.28 und dev-21.
- Der Minimalreproduzent aus dem Auftrag mit `m(1)` (`int`-Literal) löst den Fehler **nicht** aus, weder auf 21.0.28
  noch auf dev-21. Mit `m(1L)` löst er ihn aus.
- Mit einem Argument, das keine Konstante ist, tritt der Fehler nicht auf.
- Die Meldung erscheint **an jeder Aufrufstelle**: direkt aus `main` **und** über `caller()`. Ob `caller()` eine
  Spezifikation hat (`signals_only InterruptedException;` wie `waitForAnyData`) oder nicht, ändert nichts.
- Unter `-Dorg.jmlspecs.openjml.rac=exception` wird **nichts geworfen**. Es wird nur gemeldet, der Exit-Code ist 0.
  Der Grund: Der erzeugte `catch (RuntimeException)` ruft `Utils.reportException(String, RuntimeException)` auf, und
  das gibt nur aus (`System.out.println` + `printStackTrace`). Das prüft weder `rac=exception` noch sonst eine
  Einstellung.
- Gegenproben: (a) ohne `signals`-Klausel keine Meldung, (b) mit `signals (Exception e) true;` keine Meldung, (c) eine
  echte Verletzung liefert die richtige Meldung `JML signals condition is false` ohne CCE und wirft unter
  `rac=exception` einen `JmlAssertionError` (Exit 1). Das Orakel ist also nicht leer.

**streambuffer (Aufgabe 1)**, 21.0.28, RAC-Rezept aus dem Workflow (`--rac --rac-show-source=line --code-math=java
--spec-math=java`). Danach
`mvn -B --no-transfer-progress -P jml-rac -Dopenjml.home=… -Dopenjml.jdk.java=…/jdk/bin/java '-Dtest=StreamBufferTest$ThreadInterruptionDuringReadTests' test`
(`openjml-sb-2128.log`). Der Testteil vollständig und wörtlich:

```
[INFO] Running net.ladenthin.streambuffer.StreamBufferTest
[INFO] Running thread interruption during read()
java.lang.NoSuchMethodError: 'boolean java.io.IOException.standardThrowable(java.lang.Throwable)'
	at net.ladenthin.streambuffer.StreamBuffer.readIntoArray(StreamBuffer.java:14)
	at net.ladenthin.streambuffer.StreamBuffer$SBInputStream.read(StreamBuffer.java:1080)
	at net.ladenthin.streambuffer.StreamBufferTest$ThreadInterruptionDuringReadTests.lambda$read_arrayThreadInterruptedWhileWaitingForSecondByte_throwsIOException$1(StreamBufferTest.java:2673)
	at java.base/java.lang.Thread.run(Thread.java:1583)
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.io.IOException.standardThrowable
JML undefined exceptional postcondition - exception thrown
java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException (java.lang.InterruptedException and java.lang.IllegalArgumentException are in module java.base of loader 'bootstrap')
	at net.ladenthin.streambuffer.StreamBuffer.waitForAnyData(StreamBuffer.java:418)
	at net.ladenthin.streambuffer.StreamBuffer.readSingleByte(StreamBuffer.java:835)
	at net.ladenthin.streambuffer.StreamBuffer$SBInputStream.read(StreamBuffer.java:1073)
	at net.ladenthin.streambuffer.StreamBufferTest$ThreadInterruptionDuringReadTests.lambda$read_threadInterrupted_throwsIOException$0(StreamBufferTest.java:2630)
	at java.base/java.lang.Thread.run(Thread.java:1583)
java.lang.NoSuchMethodError: 'boolean java.io.IOException.standardThrowable(java.lang.Throwable)'
	at net.ladenthin.streambuffer.StreamBuffer.readSingleByte(StreamBuffer.java:14)
	at net.ladenthin.streambuffer.StreamBuffer$SBInputStream.read(StreamBuffer.java:1073)
	at net.ladenthin.streambuffer.StreamBufferTest$ThreadInterruptionDuringReadTests.lambda$read_threadInterrupted_throwsIOException$0(StreamBufferTest.java:2630)
	at java.base/java.lang.Thread.run(Thread.java:1583)
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.io.IOException.standardThrowable
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 1.474 s -- in thread interruption during read()
[INFO] Tests run: 0, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 1.508 s -- in net.ladenthin.streambuffer.StreamBufferTest
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

Die Meldung kommt genau einmal, der Test bleibt grün (wie in S3). Auf dev-21 ist sie identisch, bis auf die Laufzeit
`1.288 s` (`openjml-sb-dev21.log`). Die Zeilennummer `StreamBuffer.java:418` zeigt nicht auf `waitForAnyData`
(Zeilen 804–806, die Zeile 418 liegt in `validateOffsetAndLengthToWrite`). Die `.jml` hat nur 384 Zeilen. RAC ordnet
dem eingefügten Code hier eine falsche Zeile zu. Im Minimalreproduzenten ist es die Zeile der `signals`-Klausel
(`SignalsRepro.java:5`). Nebenbei zeigt dieser Lauf einen zweiten Fall von Verdacht 2: `IOException.standardThrowable`.

**Bytecode-Beleg (streambuffer).** `javap -c -p` der RAC-Klasse, `waitForAnyData()` (`openjml-waitForAnyData-2128-javap.log`).
Der Cast steht ohne `instanceof` davor, die Bedingung ist die Konstante `false` (`iconst_0`):

```
     955: aload         11
     957: checkcast     #482                // class java/lang/IllegalArgumentException
     960: astore        14
     962: iconst_0
     963: istore        15
     965: ldc_w         #2196               // String src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:805: verify: JML signals condition is false
     ...
     984: ldc           #69                 // String JML undefined exceptional postcondition - exception thrown
     986: aload         14
     988: invokestatic  #17                 // Method org/jmlspecs/runtime/Utils.reportException:(Ljava/lang/String;Ljava/lang/RuntimeException;)V
```

**Minimalreproduzent (Aufgabe 2).** Die Vorlage aus dem Auftrag, Variante `base`:

```java
public class SignalsRepro {
  /*@ public behavior
    @   requires true;
    @   signals_only IllegalArgumentException, InterruptedException;
    @   signals (IllegalArgumentException e) x <= 0;
    @*/
  public static void m(long x) throws InterruptedException {
    if (x <= 0) throw new IllegalArgumentException();
    throw new InterruptedException();
  }
  public static void caller() throws InterruptedException { m(1); }
  public static void main(String[] a) {
    try { m(1); } catch (InterruptedException e) { System.out.println("direct ok"); }
    try { caller(); } catch (InterruptedException e) { System.out.println("via caller ok"); }
  }
}
```

Weitere Varianten:

- `speccaller`: wie `base`, `caller()` zusätzlich mit `public behavior requires true; signals_only InterruptedException;`.
- `nonconst`: wie `speccaller`, Argument `long one = a.length + 1;` statt eines Literals.
- `nosignals`: Gegenprobe (a).
- `sigexc`: Gegenprobe (b).
- `violation`: Gegenprobe (c), `if (x == 1) throw new IllegalArgumentException();`.

Jede Variante lief einmal wörtlich (`m(1)`) und einmal mit allen `m(1)` durch `m(1L)` ersetzt. Ablauf jeweils:
`openjml --rac -d out SignalsRepro.java`, dann `<openjml>/jdk/bin/java -cp out:<openjml>/jmlruntime.jar SignalsRepro`,
ohne und mit `-Dorg.jmlspecs.openjml.rac=exception`.

| Variante | `m(1)` (int-Literal) | `m(1L)` (long-Literal) |
|---|---|---|
| `base` | keine Meldung | Meldung direkt **und** über `caller()` |
| `speccaller` | keine Meldung | Meldung direkt **und** über `caller()` |
| `nonconst` | keine Meldung | keine Meldung |
| (a) `nosignals` | keine Meldung | keine Meldung |
| (b) `sigexc` | keine Meldung | keine Meldung |
| (c) `violation` | richtige Verletzung, kein CCE | richtige Verletzung, kein CCE |

Die Tabelle ist auf 21.0.28 und dev-21 identisch (`openjml-signals-{2128,dev21}{,-1L}.log`). Mit `m(1)` lieferten
alle Läufe nur `direct ok` / `via caller ok` und `run exit=0`. Die Sweep-Läufe (`openjml-sweep-*.log`) zeigen, dass die
Mathe-Optionen keine Rolle spielen. `--code-math=java --spec-math=java` ändert nichts: `1` bleibt ohne, `1L` mit Meldung.

Ausgabe `base` mit `m(1L)`, 21.0.28. Ohne und mit `-Dorg.jmlspecs.openjml.rac=exception` ist sie wörtlich gleich, auf
dev-21 ebenfalls:

```
JML undefined exceptional postcondition - exception thrown
java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException (java.lang.InterruptedException and java.lang.IllegalArgumentException are in module java.base of loader 'bootstrap')
	at SignalsRepro.main(SignalsRepro.java:5)
direct ok
JML undefined exceptional postcondition - exception thrown
java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException (java.lang.InterruptedException and java.lang.IllegalArgumentException are in module java.base of loader 'bootstrap')
	at SignalsRepro.caller(SignalsRepro.java:5)
	at SignalsRepro.main(SignalsRepro.java:14)
via caller ok
run exit=0
```

Gegenprobe (c) mit `m(1L)`, ohne `rac=exception` (gemeldet) und mit (geworfen):

```
SignalsRepro.java:7: verify: JML signals condition is false
  public static void m(long x) throws InterruptedException {
                     ^
SignalsRepro.java:5: verify: Associated declaration: SignalsRepro.java:7:
    @   signals (IllegalArgumentException e) x <= 0;
        ^
SignalsRepro.java:12: verify: JML signals condition is false
    try { m(1L); } catch (IllegalArgumentException e) { System.out.println("direct IAE caught: " + e); }
           ^
SignalsRepro.java:5: verify: Associated declaration: SignalsRepro.java:12:
    @   signals (IllegalArgumentException e) x <= 0;
        ^
direct IAE caught: java.lang.IllegalArgumentException
run exit=0
== run WITH -Dorg.jmlspecs.openjml.rac=exception
Exception in thread "main" org.jmlspecs.runtime.JmlAssertionError: SignalsRepro.java:7: verify: JML signals condition is false
  public static void m(long x) throws InterruptedException {
                     ^
SignalsRepro.java:5: verify: Associated declaration: SignalsRepro.java:7:
    @   signals (IllegalArgumentException e) x <= 0;
        ^
	at java.base/org.jmlspecs.runtime.Utils.createException(Utils.java:143)
	at java.base/org.jmlspecs.runtime.Utils.assertionFailureL(Utils.java:94)
	at SignalsRepro.m(SignalsRepro.java:7)
	at SignalsRepro.main(SignalsRepro.java:12)
run exit=1
```

Bytecode der Aufrufstelle in `main()` (`openjml-javap-callsite.log`): Mit `m(1)` steht ein Schutz vor dem Cast und die
Bedingung wird ausgewertet. Mit `m(1L)` fehlt der Schutz und die Bedingung ist konstant. Die Gegenüberstellung ist
gekürzt (Konstantenpool-Kommentare verkürzt). Die wörtlichen Zeilen stehen im Log.

```
### m(1)                                              ### m(1L)
374: instanceof    IllegalArgumentException           368: aload         7
377: istore        12                                 370: checkcast     IllegalArgumentException
379: iload         12                                 373: astore        10
381: ifeq          422                                375: iconst_0
384: aload         9                                  376: istore        11
386: checkcast     IllegalArgumentException           378: ldc  "…verify: JML signals condition is false…"
389: astore        13
391: lload         5
393: lconst_0
394: lcmp
```

**Ort im Quelltext (Aufgabe 4).** Die Datei ist
`OpenJMLsrc/src/jdk.compiler/share/classes/org/jmlspecs/openjml/esc/JmlAssertionAdder.java`. Die Stelle liegt in
`applyHelper` (21.0.28: ab Z. 9910, dev-21: ab Z. 10165), im Zweig `signalsClauseKind` der Schleife „Assuming
exceptional postconditions“ für den Aufgerufenen. Der Text ist in beiden Versionen identisch (diff leer):

| | 21.0.28 | dev-21 (`529ac454da`) |
|---|---|---|
| `if (ct == SignalsClauseExtension.signalsClauseKind)` | 12311 | 12566 |
| Cast-Deklaration, Bedingung auf dem **unkonvertierten** `ex` (`!treeutils.isFalseLit(ex)`) | 12322–12331, `TypeCast` in 12326 | 12577–12586, `TypeCast` in 12581 |
| `instanceof`-Schutz nur, wenn das **konvertierte** `e` kein `false`-Literal ist (`!treeutils.isFalseLit(e)`), sonst `ex = trueLit` | 12340–12347 | 12595–12602 |
| `If(newTempIfNeeded(ex), bl, null)` | 12349 | 12604 |
| `wrapRuntimeException(…, "JML undefined exceptional postcondition - exception thrown", …)` | 12351–12353 | 12606–12608 |

```java
JCVariableDecl vdo = ((JmlMethodClauseSignals) clause).vardef;
Type vdtype = syms.exceptionType;
if (vdo != null && vdo.name != null && !treeutils.isFalseLit(ex)       // ex = unconverted clause expression
        && exceptionDeclCall != null) {
    ...
    JCExpression tc = M.at(vdo).TypeCast(vdo.type, exceptionId);      // the cast, inside bl
    ...
}
...
JCExpression e = convertJML(ex, condition, false, mpsym);             // x := 1L  ->  1L <= 0  ->  false
...
ex = treeutils.trueLit;
if (vdo != null && !treeutils.isFalseLit(e) && exceptionDeclCall != null) {   // guard dropped when e is false
    ex = M.at(clause).TypeTest(... exceptionDeclCall.sym ..., vdtype) ...;
    ...
}
JCBlock bl = popBlock(that, check8);
JCStatement st = M.at(clause).If(newTempIfNeeded(ex), bl, null);       // if (true) { E e = (E) ex; ... }
```

Die Prüfung am Aufgerufenen ist korrekt geschützt, trotz des Kommentars `// FIXME - need to check exception type of
the exception` (21.0.28 Z. 6016–6063, dev-21 Z. 6115–6162). Dort wird `test` immer als `instanceof` gebaut.

Naheliegender Fix: In Z. 12341 (dev-21: 12596) `!treeutils.isFalseLit(e)` streichen, sodass der Typtest immer
entsteht, wenn `vdo`/`exceptionDeclCall` existieren. Dann gilt `if (exc instanceof E) { E e = (E) exc; assume false; }`,
und das ist auch die richtige Semantik für ein konstant falsches `P`. **Nicht geprüft:** Der Fix wurde weder gebaut
noch getestet.

dev-21 enthält keinen Commit, der diese Stelle betrifft. Die nächstliegenden sind `b3812e9b3b` („Issue #1019 — operands
of a constant expression are not converted to the constant“), das `Arithmetic.java` ändert, und `6913458947`
(„Issue #1018“). Der dev-21-Lauf zeigt das Verhalten unverändert.

**Folgerung:** Ein echter OpenJML-RAC-Fehler. Er betrifft nur die Aufrufstellen-Prüfung und nur dann, wenn das
`signals`-Prädikat mit den tatsächlichen Argumenten konstant `false` wird. Er besteht in 21.0.28 und dev-21. Für
streambuffer ist er harmlos: Er wird nur gemeldet, nicht geworfen, der Test bleibt grün, und kein Vertrag ist verletzt.
Die Meldung ist eine Falschmeldung. Ein Workaround in streambuffer ist nicht nötig. Ein Argument, das keine Konstante
ist, würde die Meldung vermeiden, wäre aber eine Codeänderung nur für das Werkzeug und wird nicht empfohlen. Gemeldet
als [OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050).

---

### Verdacht 2: Stacktrace pro Aufruf bei nicht kompilierter Modellmethode (`Arrays.equalArrays`)

**Ergebnis:** **Bestätigt**, auf 21.0.28 und dev-21 gleich. Jede Ausführung eines `System.arraycopy` (`byte[]`) und
jedes `byte[].clone()` gibt einmal `java.lang.NoSuchMethodError` samt Stacktrace aus, gefolgt von `Skipping a
specification clause because it contains an uncompiled model method: 'boolean java.util.Arrays.equalArrays`. Das
passiert pro Aufruf, nicht pro Klausel: Bei 1000 Aufrufen kommt die Meldung 1000-mal.

Die Größe pro Meldung hängt nur von der Stacktiefe ab. Im Minimalprogramm (ein Frame) sind es 355 Bytes für
arraycopy und 242 Bytes für clone. Die ≈10 KB in streambuffer kommen von den tiefen surefire/JUnit-Stacks. Die
Mathe-Optionen ändern nichts. Die arraycopy-Signatur enthält auch unter `--spec-math=java`
`org.jmlspecs.lang.internal.bigint`, weil die Modellmethode in `Arrays.jml` mit `\bigint`-Parametern deklariert ist.

Kompilieren mit `-quiet` unterdrückt die Ausgabe vollständig. Eine echte Verletzung wird unter `-quiet` weiterhin
geworfen (Gegenprobe auf 21.0.28).

**Reproduzenten:**

```java
public class ArraycopyRepro {
  public static void main(String[] a) {
    int n = a.length > 0 ? Integer.parseInt(a[0]) : 1000;
    byte[] src = new byte[16];
    byte[] dst = new byte[16];
    for (int i = 0; i < n; i++) {
      System.arraycopy(src, 0, dst, 0, src.length);
    }
    System.out.println("arraycopy done: " + n);
  }
}
```

```java
public class CloneRepro {
  public static void main(String[] a) {
    int n = a.length > 0 ? Integer.parseInt(a[0]) : 1000;
    byte[] src = new byte[16];
    long sum = 0;
    for (int i = 0; i < n; i++) {
      byte[] c = src.clone();
      sum += c.length;
    }
    System.out.println("clone done: " + n + " " + sum);
  }
}
```

`openjml --rac [--code-math=java --spec-math=java] -d out X.java`, dann
`<openjml>/jdk/bin/java -cp out:<openjml>/jmlruntime.jar X <n>`. Gezählt mit `wc -c`, `wc -l`,
`grep -c 'Skipping a specification clause'` und `grep -c '^java.lang.NoSuchMethodError'`
(`openjml-copy-{2128,dev21}.log`). 21.0.28 und dev-21 liefern identische Zahlen:

| Programm | Optionen | n | Bytes | Zeilen | `Skipping…` | `NoSuchMethodError` | Exit |
|---|---|---|---|---|---|---|---|
| ArraycopyRepro | Standard | 1 | 373 | 4 | 1 | 1 | 0 |
| ArraycopyRepro | Standard | 1000 | 355021 | 3001 | 1000 | 1000 | 0 |
| ArraycopyRepro | `--code-math=java --spec-math=java` | 1000 | 355021 | 3001 | 1000 | 1000 | 0 |
| CloneRepro | Standard | 1 | 259 | 4 | 1 | 1 | 0 |
| CloneRepro | Standard | 1000 | 242023 | 3001 | 1000 | 1000 | 0 |
| CloneRepro | `--code-math=java --spec-math=java` | 1000 | 242023 | 3001 | 1000 | 1000 | 0 |
| ArraycopyRepro | `-quiet` | 1000 | 21 | 1 | 0 | – | 0 |
| CloneRepro | `-quiet` | 1000 | 23 | 1 | 0 | – | 0 |

Vollständige Ausgabe bei n=1 (21.0.28, wörtlich):

```
java.lang.NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], org.jmlspecs.lang.internal.bigint, byte[], org.jmlspecs.lang.internal.bigint, org.jmlspecs.lang.internal.bigint)'
	at ArraycopyRepro.main(ArraycopyRepro.java:11)
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.util.Arrays.equalArrays
arraycopy done: 1
```

```
java.lang.NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], byte[])'
	at CloneRepro.main(CloneRepro.java:12)
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.util.Arrays.equalArrays
clone done: 1 16
```

Auch hier stimmen die Zeilennummern nicht. `:11` und `:12` sind jeweils die letzte Zeile der Datei, nicht die Zeile
mit `arraycopy` (7) bzw. `clone` (7). Das abgeschnittene `'boolean java.util.Arrays.equalArrays` ohne
Parameterliste ist so gewollt: `reportNoSuchMethod` schneidet die Meldung am ersten `(` ab.

**Betroffene Klauseln** (Pfade relativ zur Distribution `<openjml>/specs/`, Zeilen aus dem 21.0.28-Zip):

- `System.arraycopy` mit `byte[]`: der Fall `requires (src instanceof byte[]) && (dest instanceof byte[]) …` in
  `java/lang/System.jml:260–269`. Die Klausel ist `java/lang/System.jml:268`
  `ensures java.util.Arrays.equalArrays(da,destPos,sa,srcPos,length_);`. Sie ruft die Modellmethode ohne Rumpf
  `java/util/Arrays.jml:968`
  `model public static spec_pure helper boolean equalArrays(byte[] arr1, \bigint index1, byte[] arr2, \bigint index2, \bigint len);`
  auf. Die übrigen Elementtypen haben dieselbe Form (`System.jml:202, 213, 224, 235, 246, 257`).
- `byte[].clone()`: der Fall `requires this instanceof byte[];` in `java/lang/Object.jml:164–169`. Die Klausel ist
  `java/lang/Object.jml:168` `ensures java.util.Arrays.equalArrays((byte[])\result,(byte[])this);` und ruft
  `java/util/Arrays.jml:984` `model public static spec_pure helper boolean equalArrays(byte[] arr1, byte[] arr2);` auf.
  Die anderen Elementtypen nutzen hier ein ausführbares `\forall`, nur `byte[]` die Modellmethode.
- Nebenbefund aus dem streambuffer-Lauf: `new IOException(cause)` löst dasselbe aus. Die Klausel ist
  `java/io/IOException.jml:21` `ensures standardThrowable(cause);` und ruft `java/lang/Throwable.jml:93` auf (Modellmethode
  ohne Rumpf).
- In Specs `dev-21` (`dc9f6be7c095`) sind `Object.jml`, `Arrays.jml`, `IOException.jml` und `Throwable.jml`
  byteidentisch zum 21.0.28-Stand. `System.jml` unterscheidet sich nur durch zwei entfernte Zeilen
  (`@Deprecated` + Javadoc, alte Z. 378–379). Die Zeilen oben gelten also auch für dev-21.

**Ort im Quelltext:**

- Laufzeit: `OpenJMLsrc/src/java.base/share/classes/org/jmlspecs/runtime/Utils.java:296–304`
  `reportNoSuchMethod(NoSuchMethodError, String)` ruft `t.printStackTrace(System.out)` und `report(msg)` auf. Es gibt
  keinen Zustand, der bereits gemeldete Klauseln oder Methoden unterdrückt. Die Datei ist auf 21.0.28 und dev-21
  identisch.
- Übersetzer: `JmlAssertionAdder.java` erzeugt um jede Klausel `catch (NoSuchMethodError) { Utils.reportNoSuchMethod(…) }`,
  außer wenn `boolean quiet = utils.jmlverbose == 0` gilt. Dann ist der catch-Block leer. Die Stellen sind:
  - `wrapRuntimeException`: 21.0.28 Z. 2931, `quiet` in Z. 2952, Aufruf in Z. 2964; dev-21 Z. 2935/2956/2968.
  - Prüfung der Nachbedingungen: 21.0.28 Z. 6207/6222 und 6263/6278; dev-21 Z. 6306/6321 und 6362/6377.
  - `makeRACTry`: 21.0.28 Z. 21295/21300/21312; dev-21 Z. 21604/21609/21621.

  Die Ortsangabe wird immer mit `null` überschrieben (`// FIXME - really need to propagate the location of the call`).

**Folgerung:** Kein falsches Ergebnis, aber ein echter Mangel an der Benutzbarkeit. Eine einmal übersprungene Klausel
wird bei jeder Ausführung erneut mit vollem Stacktrace gemeldet. Das ist der Mechanismus hinter den 7.344 s und
21 GB Log aus S3. Er besteht in 21.0.28 und dev-21 unverändert.

Für streambuffer gibt es zwei Möglichkeiten. Man behält die Skalierung der Stressschleifen unter `-Pjml-rac` bei. Oder
man kompiliert die RAC-Klassen mit `-quiet`. Das unterdrückt die Meldung vollständig, verschweigt aber auch künftige
„übersprungene Klausel“-Hinweise. **Nicht geprüft:** der volle streambuffer-Lauf mit `-quiet`. Gemeldet als
[OpenJML/OpenJML#1050](https://github.com/OpenJML/OpenJML/issues/1050). Vorschlag: einmal pro Klausel oder Methode melden, Stacktrace nur bei höherer Verbosität. Zusätzlich oder
stattdessen die zwei `byte[]`-Klauseln mit `-RAC` markieren oder durch ein ausführbares `\forall` ersetzen.

---

### Issue-Entwurf A (eingereicht, zusammen mit B, als #1050)

**Titel:** RAC: call-site check of a callee's `signals (E e) P` casts the exception to `E` without `instanceof` when `P` folds to `false` → spurious "JML undefined exceptional postcondition - exception thrown"

[Assisted by Claude Code.] I'm not a JML/OpenJML expert; this came up while running streambuffer's test suite under
RAC, and most of the analysis was done with Claude Code. I reproduced it with the 21.0.28 release (Ubuntu build) and
with `dev-21` built from source (`529ac454da`). I may have misread the cause, so **please treat this as a starting
point and verify it in your own Claude session**.

**What happens.** A method may throw two exception types (`signals_only IllegalArgumentException,
InterruptedException`), and a `signals` clause constrains only one of them (`signals (IllegalArgumentException e) x <= 0`).
If a call site passes an argument for which the predicate is constant-false (here the `long` literal `1L`), and the
callee throws the *other* allowed exception, the RAC code at the call site reports a `ClassCastException`. As far as I
understand JML, `signals (E e) P` only applies when the exception is an `E`, so nothing should be reported.

```java
public class SignalsRepro {
  /*@ public behavior
    @   requires true;
    @   signals_only IllegalArgumentException, InterruptedException;
    @   signals (IllegalArgumentException e) x <= 0;
    @*/
  public static void m(long x) throws InterruptedException {
    if (x <= 0) throw new IllegalArgumentException();
    throw new InterruptedException();
  }
  public static void caller() throws InterruptedException { m(1L); }
  public static void main(String[] a) {
    try { m(1L); } catch (InterruptedException e) { System.out.println("direct ok"); }
    try { caller(); } catch (InterruptedException e) { System.out.println("via caller ok"); }
  }
}
```

```
$ openjml --rac -d out SignalsRepro.java      # compiles, exit 0
$ openjml-java -cp out SignalsRepro            # same output with -Dorg.jmlspecs.openjml.rac=exception, exit 0
JML undefined exceptional postcondition - exception thrown
java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException (java.lang.InterruptedException and java.lang.IllegalArgumentException are in module java.base of loader 'bootstrap')
	at SignalsRepro.main(SignalsRepro.java:5)
direct ok
JML undefined exceptional postcondition - exception thrown
java.lang.ClassCastException: class java.lang.InterruptedException cannot be cast to class java.lang.IllegalArgumentException (java.lang.InterruptedException and java.lang.IllegalArgumentException are in module java.base of loader 'bootstrap')
	at SignalsRepro.caller(SignalsRepro.java:5)
	at SignalsRepro.main(SignalsRepro.java:14)
via caller ok
```

What I checked around it (same on 21.0.28 and `dev-21`):

- With `m(1)` (an `int` literal) or a non-constant argument, nothing is reported.
- Without the `signals` clause, or with `signals (Exception e) true;`, nothing is reported.
- A real violation (throwing `IllegalArgumentException` for `x == 1`) is reported correctly as `JML signals condition
  is false`, and it is thrown under `rac=exception`.
- `--code-math=java --spec-math=java` makes no difference.
- The callee-side check is fine. It is only the call-site code.

**Where I think it comes from** (`JmlAssertionAdder.applyHelper`, signals branch, 21.0.28 lines 12311–12353, `dev-21`
12566–12608). The cast `(E) exception` is declared when the *unconverted* clause expression is not `false` (12322).
The `instanceof E` guard is only built when the *converted* expression `e` is not a `false` literal (12341). With `x :=
1L`, `e` becomes `false`, the guard becomes `true`, and the cast runs unconditionally. `javap` confirms this: with
`m(1L)` there is a `checkcast IllegalArgumentException` followed by `iconst_0` and no `instanceof`. With `m(1)` there
is `instanceof`/`ifeq` before the cast.

A possible fix, untested, which you may well do differently: build the type test whenever the variable was declared,
i.e. drop `!treeutils.isFalseLit(e)` from the condition in line 12341 (`dev-21` 12596).

**Smaller things noticed:**

- The message is only printed, even with `-Dorg.jmlspecs.openjml.rac=exception`, because the `catch (RuntimeException)`
  calls `Utils.reportException`. That is probably intended for "undefined", just mentioning it.
- The line number in the stack (`SignalsRepro.java:5`, the clause line) points at the specification rather than at the
  call. In streambuffer it shows `StreamBuffer.java:418`, which is neither the call nor the clause.

In streambuffer this shows up once per run of `StreamBufferTest$ThreadInterruptionDuringReadTests`, because
`waitForAnyData()` is `return waitForAtLeast(1L);`. The tests stay green.

Thanks again for OpenJML!

---

### Issue-Entwurf B (eingereicht, zusammen mit A, als #1050)

**Titel:** RAC: a skipped clause with an uncompiled model method prints a full stack trace on every execution (`System.arraycopy`/`byte[].clone()` → `Arrays.equalArrays`)

[Assisted by Claude Code.] I'm not a JML/OpenJML expert; this came up while running streambuffer's test suite under
RAC, and most of the analysis was done with Claude Code. I reproduced it with the 21.0.28 release (Ubuntu build) and
with `dev-21` built from source (`529ac454da`, Specs `dc9f6be`). **Please treat this as a starting point and verify it
in your own Claude session.**

**What happens.** Each execution of a `System.arraycopy` on `byte[]` and each `byte[].clone()` prints a
`NoSuchMethodError` with its full stack trace, plus `Skipping a specification clause because it contains an uncompiled
model method`. This repeats on every call, not once per clause:

```java
public class ArraycopyRepro {
  public static void main(String[] a) {
    int n = a.length > 0 ? Integer.parseInt(a[0]) : 1000;
    byte[] src = new byte[16];
    byte[] dst = new byte[16];
    for (int i = 0; i < n; i++) {
      System.arraycopy(src, 0, dst, 0, src.length);
    }
    System.out.println("arraycopy done: " + n);
  }
}
```

```
$ openjml --rac -d out ArraycopyRepro.java
$ openjml-java -cp out ArraycopyRepro 1
java.lang.NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], org.jmlspecs.lang.internal.bigint, byte[], org.jmlspecs.lang.internal.bigint, org.jmlspecs.lang.internal.bigint)'
	at ArraycopyRepro.main(ArraycopyRepro.java:11)
Skipping a specification clause because it contains an uncompiled model method: 'boolean java.util.Arrays.equalArrays
arraycopy done: 1
$ openjml-java -cp out ArraycopyRepro 1000 | grep -c 'Skipping a specification clause'
1000
```

With 1000 iterations the output is 355,021 bytes (3,001 lines). The same loop with `src.clone()` gives
`NoSuchMethodError: 'boolean java.util.Arrays.equalArrays(byte[], byte[])'` 1000 times. `--code-math=java
--spec-math=java` changes nothing. Each message is only as large as the stack. Under a test framework that is about
10 KB per call. In streambuffer, one stress test (2 million single-byte writes, with periodic buffer consolidation that
calls `arraycopy` once per buffered chunk) ran for 7,344 s under RAC, with every contract holding. By the time that run
was stopped, its log held the message 2,003,546 times in about 21 GB.

**The clauses involved** (unchanged on Specs `dev-21`):

- `java/lang/System.jml:268` (`byte[]` case of `arraycopy`): `ensures java.util.Arrays.equalArrays(da,destPos,sa,srcPos,length_);`
  This calls `java/util/Arrays.jml:968`, a model method without a body. The other element types (lines 202–257) have
  the same shape.
- `java/lang/Object.jml:168` (`byte[]` case of `clone`): `ensures java.util.Arrays.equalArrays((byte[])\result,(byte[])this);`
  This calls `Arrays.jml:984`. The other element types use an executable `\forall` here.
- The same pattern with `new IOException(cause)`: `java/io/IOException.jml:21` calls `Throwable.standardThrowable(Throwable)`.

**Where the repetition comes from, as far as I can see.** `JmlAssertionAdder` wraps each clause in
`catch (NoSuchMethodError) { Utils.reportNoSuchMethod(e, null) }` (`wrapRuntimeException`, `makeRACTry`, and the
postcondition checks). `Utils.reportNoSuchMethod` (`runtime/Utils.java:296–304`) always calls `printStackTrace` and
has no memory of what it already reported. Compiling with `-quiet` (`jmlverbose == 0`) generates an empty catch block
and silences it completely. That is a workaround for us, but it also hides every other skipped-clause note.

**Possible improvements**, you will know better:

- report each skipped clause (or each missing model method) only once per run, and print the stack trace only at a
  higher verbosity;
- and/or make the two `byte[]` clauses executable (`\forall`, like the other `clone` cases) or `-RAC`, in the style of
  Specs `43ab561`.

Related: the location passed to `reportNoSuchMethod` is always `null` (`// FIXME - really need to propagate the location
of the call`), and the line number in the stack is the last line of the file (`:11`), not the call.

Thanks for OpenJML!
