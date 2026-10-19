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
