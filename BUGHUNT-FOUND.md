
# Bug-Hunt: gefundene Fehler — streambuffer

Fortlaufendes Fundbuch der Fehlersuche auf dem Arbeitsbranch `ccr-90fc5f6a-vs4s0f`. Jeder Fund hat eine
globale ID (`Fnn`, über alle drei Repos eindeutig), Datei:Zeile, Schwere, Beschreibung, Reproduktion (Testname),
Status und Commit. Neue Funde werden **unten angehängt**; die nächste freie ID ist die höchste ID in allen drei
Repos plus eins. Geprüfte Klassen ohne Fund stehen in [`BUGHUNT-CHECKED.md`](BUGHUNT-CHECKED.md).

## Übersicht

- [F02](#f02) — mittel — *gefixt*
- [F03](#f03) — mittel — *Designentscheidung, dokumentiert*
- [F73](#f73) — hoch — *gefixt*
- [F110](#f110) — niedrig — *gefixt (Doku)*
- [F149](#f149) — mittel — *gefixt*
- [F212](#f212) — niedrig — *gefixt*

## Funde

<a id="f02"></a>
### F02 – streambuffer: `safeWrite` wird von gleichzeitigem `write(int)` ausgehebelt
- **Zeit:** 2026-10-16 23:05 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:1015` (`writeSingleByte`), `:1057` (Klon-Entscheidung in `writeFromArray`)
- **Schwere:** mittel
- **Beschreibung:** `writeSingleByte()` setzte das **instanzweite** `volatile` Feld `ignoreSafeWrite=true` um seinen eigenen Schreibvorgang. Läuft auf einem anderen Thread gleichzeitig `write(byte[])` mit `setSafeWrite(true)` und bekommt den Lock in diesem Fenster, wird das Array **nicht** geklont, sondern per Referenz in die Deque gelegt. Ändert der Aufrufer sein Array danach (genau das, wovor `safeWrite` schützen soll), liest der Leser die geänderten Bytes. Klassen-Javadoc erlaubt gleichzeitige Aufrufe; ein Test im Repo spricht von „concurrent writers“.
- **Reproduktion:** `StreamBufferTest$ConcurrentReadWriteTests#safeWrite_concurrentSingleByteWrite_arrayStillCloned` – vor dem Fix rot (geänderte Bytes beim Leser), danach grün; ganze `StreamBufferTest` 286/286 grün.
- **Status:** gefixt (Feld entfernt, Klon-Erlaubnis als Parameter der privaten Schreibmethode). Nicht geprüft: OpenJML-ESC/RAC-Pipeline (die privaten Schreibmethoden stehen nicht in der `.jml`), PIT, jcstress.
- **Nachgemessen:** Messauftrag `BUGHUNT-MEASUREMENTS.md` in `0620aa7`, lokal gelaufen 2026-10-19: jcstress (S1) und vmlens (S2) grün, ESC 14/14 und RAC grün (S3); PIT 199/199 getötet (Review 2026-10-20). Die „Nicht geprüft“-Liste oben ist damit erledigt.
- **Nachtrag (Branch-Review 2026-10-20):** der Reproduktionstest `safeWrite_concurrentSingleByteWrite_arrayStillCloned` konnte leer bestehen: er rief nur `Waiter.resume()`, das in ConcurrentUnit 0.4.6 nichts zurückwirft (das tut nur `await`), und ein Leser, der vorzeitig stirbt, ließ die einzige Prüfung „0 geänderte Bytes“ grün. Jetzt halten beide Hintergrund-Threads jede `Throwable` in einer `AtomicReference` fest, Einzelbyte-Schreiber und Leser zählen ihre Bytes, und der Test prüft „kein Fehler“ sowie „gelesen == 8·n + Einzelbytes“. Gegenprobe mit einer eingeschleusten `IOException` im Lesepfad (`readIntoArray`): die alte Fassung grün, die neue rot („Expected: is null but: was <java.io.IOException: injected reader failure>“ und „Expected: is <1812184L> but: was <0L>“); ohne Einschleusung grün. Der ältere Test `concurrentReadWrite_stressTest_noCrashOrInconsistency` ruft nach `resume()` jetzt `await(1, SECONDS, 0)`, sodass die Ursache eines toten Lesers auf dem Test-Thread erscheint (vorher nur ein `assertArrayEquals`-Fehlschlag ohne Ursache); sein falscher Kommentar ist korrigiert.
- **Commit:** streambuffer `3302ff8`

<a id="f03"></a>
### F03 – streambuffer: `read(byte[],off,len)` wartet auf **alle** `len` Bytes (Abweichung vom `InputStream`-Vertrag)
- **Zeit:** 2026-10-16 23:10 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:912` (`readIntoArray`, „second wait phase“ `waitForAtLeast(missingBytes)`)
- **Schwere:** mittel (falls nicht gewollt) / keine (falls gewollt)
- **Beschreibung:** Nach dem ersten Byte wartet `readIntoArray` mit `waitForAtLeast(len-1)`, bis der Rest **vollständig** da ist oder der Stream geschlossen wird. `InputStream.read(byte[],int,int)` verlangt nur, bis mindestens ein Byte verfügbar ist zu blockieren, und dann zurückzugeben, was da ist. Praktische Folge: Ein `InputStreamReader`/`BufferedReader` (liest in 8-KiB-Blöcken) über einem offenen StreamBuffer hängt bei einem Request/Response-Protokoll, bis 8 KiB zusammengekommen sind oder geschlossen wird. README („second wait phase“) und die jcstress-Tests zeigen, dass das Verhalten bewusst so gebaut ist – darum kein Fix, nur zur Entscheidung.
- **Historie:** So gebaut seit dem ersten Commit des Nutzers (`9da0dcd`, 2014-09-15): `tryWaitForEnoughBytes(missingBytes)`, Javadoc „blocks until the stream is closed or enough bytes are available“; `16f1df7` (2026-06-03) benannte es nur in `waitForAtLeast` um. Einen Monat später ergänzte der Nutzer `blockDataAvailable()` (`7a780d5`, 2014-10-31, heute `waitForAnyData()`), um ohne volle Blöcke auf Daten zu warten – beides war zusammen gedacht. Festgeschrieben durch `jcstress/WriteUnblocksArrayReadRace`, `CloseUnblocksArrayReadRace` und `read_arrayThreadInterruptedWhileWaitingForSecondByte_throwsIOException`; dokumentiert war es nirgends, und das README nannte die Streams „full … compatibility“.
- **Entscheidung des Nutzers (Variante A):** Verhalten bleibt, Dokumentation ergänzt: Javadoc von `getInputStream()` und `readIntoArray`, README „Full `InputStream`/`OutputStream` Compatibility“ (eine bewusste Abweichung) und „Deadlock Behavior → Read“ (Semantik, Unterschied zu `PipedInputStream`, Folge für `InputStreamReader`, Muster `waitForAnyData()` + `available()`).
- **Reproduktion:** keine (Designfrage).
- **Status:** Designentscheidung, dokumentiert
- **Commit:** 6ece270

<a id="f73"></a>
### F73 – streambuffer: ein gleichzeitiger `trim()` lässt `waitForAtLeast`/`read()` einen halb geleerten Puffer sehen
- **Zeit:** 2026-10-18 01:35 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:496` (`trim`), `:794` (`waitForAtLeast`)
- **Schwere:** hoch
- **Beschreibung:** `trim()` (läuft im Schreib-Thread unter `bufferLock`) leerte den Puffer, indem es über den eigenen `InputStream` las, und schrieb die Bytes danach zurück. Dabei sank das `volatile` Feld `availableBytes` Schritt für Schritt bis 0 und stieg dann wieder. `waitForAtLeast(long)` liest das Feld **ohne** Lock und zweimal: einmal in der Schleifenbedingung, einmal für den Rückgabewert. Fällt ein Trim dazwischen, gibt die Methode weniger zurück als verlangt, obwohl der Stream offen ist und keine Daten verbraucht wurden – entgegen ihrer Javadoc („blocks until at least `bytes` bytes are available, or the stream is closed“). Folgen über die privaten Lesepfade: `read()` prüft `waitForAnyData() < 1` und meldet bei einem Zwischenwert 0 das **Ende eines offenen Streams, der noch Daten hält** (ein Leser bricht ab, die Daten gehen verloren); `read(byte[],…)` liefert verkürzt. Ein `close()` aus einem dritten Thread während eines Trims ergibt über den `streamClosed`-Zweig dasselbe. Ausgelöst wird es im Normalbetrieb: jeder Schreibvorgang, der mehr als `maxBufferElements` (Vorgabe 100) Einträge erzeugt, trimmt.
- **Fix:** `trim()` kopiert die Einträge direkt aus der Deque in Blöcke zu höchstens `maxAllocationSize` (Ausgangsposition `positionAtCurrentBufferEntry` berücksichtigt) und lässt `availableBytes` unverändert. Kein Lesen über den Stream mehr, `throws IOException` und der Null-Check des Zwischenpuffers entfallen. README (Trim-Abschnitt, Statistik) nachgezogen; die Zeile zum längst entfernten `ignoreSafeWrite`-Flag (aus F02) war ohnehin veraltet.
- **Reproduktion:** `StreamBufferTest$ConcurrentTrimAndWriteTests#waitForAtLeast_concurrentTrim_neverReturnsFewerBytesThanRequested` – niemand liest, `maxBufferElements` 1000, Schreiber schreibt Einzelbytes, ein Wartender ruft `waitForAtLeast(gesehen)` und prüft, dass nicht weniger zurückkommt. Mit Fix ist das deterministisch (ohne Leser sinkt `availableBytes` nie), ohne Fix ein Stresstest, der in Millisekunden rot wird.
- **Rot-Grün-Nachweis:** ohne Fix rot in 4 von 4 Läufen („Expected: is null but: was "waitForAtLeast(998) returned 997 on an open stream"“, ebenso 44001→44000, 4001→4000, 989→988), 28 ms bis zum Fund; mit Fix grün in 3 von 3 Läufen (2/2 der Klasse); Gegenprobe per `git stash` wieder rot, nach `pop` grün. Breit: `StreamBufferTest` 287/287, `StreamBufferArchitectureTest` 10/10, `StreamBufferProperties` 5/5; `spotbugs:check` grün; PIT 199/199 getötet (Test strength 100 %).
- **Nicht geprüft:** OpenJML-RAC/ESC (`trim` steht nicht in der `.jml`, kein ESC-Ziel), jcstress- und vmlens-Profil, Lincheck.
- **CI-Bedarf:** die Pipeline `formal-verification.yml` (RAC-Lauf der Suite gegen den geänderten `trim`) einmal mitlaufen lassen.
- **Nachgemessen:** Messauftrag `BUGHUNT-MEASUREMENTS.md` in `0620aa7`, lokal gelaufen 2026-10-19: RAC der ganzen Suite gegen den geänderten `trim` grün ohne Vertragsverletzung, ESC 14/14, JPF grün, jcstress und vmlens grün (S1–S3); Lincheck läuft in jedem `mvn test` mit. „Nicht geprüft“ und „CI-Bedarf“ oben sind damit erledigt; die RAC-Laufzeit des Trim-Stresstests führte zur Skalierung unter `-Pjml-rac`.
- **Nachtrag (Branch-Review 2026-10-20):** der Test `write_wrappingStreamThrows_bufferStaysUsable` (früher `trim_ignoreSafeWriteFlagResetDuringWriteException_streamRecoverable`, auf diesem Branch umbenannt) ist **gelöscht**, nicht nur umbenannt. Sein `getOutputStream()`-Wrapper warf vor jedem Aufruf des echten Streams, die geprüfte Fehlermeldung war die des Tests selbst; schon vor F73 erreichte der Wrapper den Trim nie (`trim()` schrieb über das private Feld `os`). Die verbliebenen Erholungsschritte (ein Safe-Write mit echtem Trim, dann ein Lesen mit mehr als 0 Bytes) prüfen `trim_withSafeWriteEnabled_preservesDataIntegrity` und `trim_withSafeWrite_allDataPreserved` strenger; einen Fehler im echten Trim samt Zurücksetzen von `isTrimRunning` und Erholung prüfen `trim_signalReleaseExceptionDuringStart_streamRecoverable` und `trim_signalReleaseExceptionDuringEnd_flagAlreadyResetExceptionPropagates`. `StreamBufferTest` danach 289/289 grün.
- **Status:** gefixt
- **Commit:** streambuffer `27aaed6`

<a id="f110"></a>
### F110 – streambuffer: Javadoc von `clampToMaxInt` beschreibt die `trim()`-Schleife vor F73
- **Zeit:** 2026-10-18 09:10 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:634` (Javadoc von `clampToMaxInt`)
- **Schwere:** niedrig
- **Beschreibung:** Die Javadoc begründet die Klemmung mit dem Ablauf von `trim()`: „The trim() loop reads at most maxAllocationSize bytes per iteration … Loop condition (available > 0) … Next iteration calls available() again“, samt Beispiel für 5 GB. So arbeitete `trim()` bis F73 (`27aaed6`), das den Puffer über den eigenen Eingabestrom leerte. Seit F73 kopiert `trim()` direkt aus dem Deque und liest `availableBytes`, ohne `available()` oder `clampToMaxInt`; einziger Aufrufer ist jetzt `availableClamped()` (`InputStream.available()`). Die Javadoc beschreibt also Code, den es nicht mehr gibt – eine Abweichung, die mein eigener Fix F73 hinterlassen hat. Der Code ist korrekt.
- **Historie:** Der Absatz „SAFETY GUARANTEE …“ kam mit `d3b9731` (2026-04-15) und stimmte damals: `trim()` lief über `while ((available = is.available()) > 0)`. Mein F73-Fix `27aaed6` (2026-10-18) hat `trim()` auf das direkte Kopieren aus dem Deque umgestellt und die Javadoc übersehen. JML-Spezifikation und ESC-Beweis betreffen nur die Funktion und bleiben gültig.
- **Gleiche Art, mitbehoben:** README „Default: `Integer.MAX_VALUE`“ bei `maxAllocationSize` (seit `80d8c71`, 2026-04-15); seit `f88be77` (2026-09-30) ist der Default `MAX_ARRAY_LENGTH = Integer.MAX_VALUE - 8` und der Setter klemmt darauf. Code richtig, README veraltet.
- **Fix:** Entscheidung des Nutzers (Variante A): Javadoc auf den verbliebenen Zweck gekürzt (`available()` meldet höchstens `Integer.MAX_VALUE`, wenn mehr als 2 GiB gepuffert sind), README nennt den richtigen Default. `clampToMaxInt` bleibt (ESC-Beweisumfang samt Zählung).
- **Reproduktion:** keine (reine Doku-Abweichung); `clampToMaxInt` ist durch die bestehenden direkten Tests und den ESC-Beweis abgedeckt.
- **Rot-Grün-Nachweis:** – (Doku-Korrektur, Freigabe des Nutzers für Doku ohne roten Test)
- **Status:** gefixt (Doku)
- **Commit:** 5540fb0

<a id="f149"></a>
### F149 – streambuffer: ein `write`, der mit `close()` aus einem anderen Thread zusammentrifft, hängt nach dem `close` an und kehrt normal zurück
- **Zeit:** 2026-10-18 21:00 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` (`writeFromArray`: `requireNonClosed()` vor `synchronized (bufferLock)`; `closeAll()`: Flag ohne Lock)
- **Schwere:** mittel (Datenverlust für einen Leser, der bei `-1` aufhört; nur bei `close()` aus einem dritten Thread während eines laufenden `write`)
- **Beschreibung:** Der Schreiber besteht `requireNonClosed()`, ein anderer Thread schließt, ein Leser sieht „geschlossen, 0 Bytes“ und meldet `-1`, danach hängt der Schreiber an und kehrt ohne Exception zurück. Ein erfolgreicher `write` muss vor dem `close` eingeordnet werden, also ist das nicht linearisierbar. Ein Leser, der nach `-1` noch einmal liest, bekäme die Bytes.
- **Historie:** Seit dem ersten Commit (`9da0dcd`, 2014) steht die Prüfung vor dem Lock. Die Absicht des Projekts zeigt `e61f359` (2026-05-07, Wettlauf `trim()`/`close()`): eine Exception bei einem unbeteiligten `write` und stillschweigend verworfene Bytes wurden als Fehler behoben (`trim_closeCalledDuringTrim_handlesGracefully`, `37132b3`, `8924e88`). Das README verspricht „Parallel close without deadlock“. Weder die JPF-Prüfung (Schreiber und Schließer im selben Thread) noch Lincheck (ohne blockierendes `read`) decken den Fall ab.
- **Fix:** Entscheidung des Nutzers (Variante A). `requireNonClosed()` steht jetzt in `synchronized (bufferLock)`, und `closeAll()` setzt `streamClosed` unter demselben Lock (das Signal danach). Ein `write` ist damit entweder vor dem `close` vollständig gepuffert – `waitForAtLeast` liest beim geschlossenen Stream `availableBytes` neu und sieht ihn – oder er wirft „Stream closed“. Kosten: ein `close()` wartet auf einen laufenden `write` oder `trim()`.
- **Reproduktion:** `StreamBufferTest$ConcurrentWriteAndCloseTests#write_closedWhileTheWriterWaitsForTheLock_failsInsteadOfAppendingAfterTheClose`, deterministisch ohne Reflexion: Das Trim-Start-Signal läuft im Trim-Thread, der `bufferLock` hält; dort wird ein zweiter Schreiber gestartet, der am Lock parkt (`Thread.State.BLOCKED`), und während er parkt, wird geschlossen. Erwartet: nach dem `close` bleibt der Puffer bei 2 Bytes, der späte `write` scheitert.
- **Rot-Grün-Nachweis:** ohne Fix rot („Expected: is <2L> but: was <3L>“ – der späte `write` hängte nach dem `close` an), mit Fix grün; Gegenprobe per `git stash` des Produktionscodes wieder rot, nach `pop` grün. Breit: 304 Tests grün (`StreamBufferTest`, jqwik, Lincheck, Architektur), SpotBugs, Javadoc, PIT 199/199.
- **Zusätzlich angelegt, nicht ausgeführt:** `jcstress/WriteRacingCloseRace` (Schreiber, Schließer, Leser; Ausgang `1, -1` verboten).
- **CI-Bedarf:** `mvn -Pjcstress test`, `mvn -Pvmlens test`, die Formal-Verification-Pipeline (ESC, RAC, JPF) – alles in `TODO.md`, „Run the concurrency and formal-verification suites after the write/close fix“.
- **Nachgemessen:** Messauftrag `BUGHUNT-MEASUREMENTS.md` in `0620aa7`, lokal gelaufen 2026-10-19: jcstress `WriteRacingCloseRace` grün bei rund 3,54 Milliarden Proben (S1), vmlens grün (S2), ESC 14/14, RAC und JPF grün (S3), dazu die neue JPF-Harness `JpfWriteCloseHarness` mit drei Threads (S4): mit dem Fix fehlerfrei über 75.438 Zustände, gegen `6ece270^` rot nach 3.956. Sie läuft seither im Job `jpf-interleavings`. Der TODO-Punkt aus „CI-Bedarf“ ist danach gelöscht worden.
- **Nachtrag (Branch-Review 2026-10-20):** der Rot-Grün-Nachweis oben nahm beide Hälften des Fixes auf einmal zurück; der Reproduktionstest ruft `close()` im Trim-Start-Signal auf dem Thread, der `bufferLock` schon hält (reentrant), und bleibt grün, wenn nur der Lock in `closeAll()` fehlt. Neu: `ConcurrentWriteAndCloseTests#close_fromAnotherThreadDuringAWrite_waitsUntilTheWriteIsBuffered` startet den Schließer im Signal als eigenen Thread und hält dort dessen Zustand, `isClosed()` und den Pufferstand fest (geprüft wird erst nach dem `write`): der Schließer muss `BLOCKED` sein, der Stream noch offen, 2 Bytes gepuffert, danach geschlossen mit 2 Bytes. Gegen `closeAll()` allein (Lock dort entfernt, `requireNonClosed()` unter dem Lock in `writeFromArray` belassen) rot in 3 von 3 Läufen („Expected: is <BLOCKED> but: was <TERMINATED>“, einmal „… was <RUNNABLE>“, dazu „Expected: is <false> but: was <true>“), der bestehende Test blieb dabei grün; mit Fix grün in 5 von 5 Läufen, `StreamBufferTest` 290/290.
- **Status:** gefixt
- **Commit:** 6ece270

<a id="f212"></a>
### F212 – streambuffer: I/O aus einem Trim-Start-Signal fehlt in den Statistiken
- **Zeit:** 2026-10-20 20:31 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` (`writeFromArray`: `if (!isTrimRunning)` um `totalBytesWritten`/`updateMaxObservedBytesIfNeeded`; `recordReadStatistics`: `if (!isTrimRunning)` um `totalBytesRead`; Javadoc von `isTrimRunning`)
- **Schwere:** niedrig (falsche Zähler, nur für I/O aus einem Trim-Start-Signal auf dem Trim-Thread)
- **Historie:** Gefunden beim Review des Branches am 2026-10-20 (Fund S1-2). Vor F73 (`27aaed6`) leerte `trim()` den Puffer über den eigenen `InputStream` und schrieb ihn zurück; die beiden Wächter hielten diese interne I/O aus den Zählern. Seit F73 kopiert `trim()` direkt aus der Deque, die Wächter schlossen nur noch einen Fall aus: ein `write`/`read`, den ein Trim-Start-Signal in seinem `release()` auf dem Trim-Thread macht (`bufferLock` ist reentrant). Die mit F73 umgeschriebene Javadoc von `isTrimRunning` schrieb diesen Ausschluss fest („nor be counted in the statistics“).
- **Beschreibung:** Ein solcher `write` erhöhte `availableBytes`, aber weder `totalBytesWritten` noch `maxObservedBytes`; ein solcher `read` senkte `availableBytes`, ohne `totalBytesRead` zu erhöhen. Das widerspricht der Javadoc von `getTotalBytesWritten`/`getTotalBytesRead` („by user I/O operations“), dem README („the statistics always reflect user I/O only“) und der Invariante `totalBytesWritten == totalBytesRead + available` (`StreamBufferProperties`): nach dem Auslesen standen 12 gelesene gegen 9 geschriebene Bytes.
- **Fix:** Die beiden Wächter um die Statistik entfallen, der in `shouldTrim()` bleibt (er verhindert den verschachtelten Trim). Javadoc von `isTrimRunning` und `recordReadStatistics` angepasst, zwei veraltete Testkommentare („trim internally reads and writes …“) korrigiert. Die JML-Spezifikation deckt keine der drei Methoden ab, daher keine Spiegelung nötig; README und Getter-Javadoc stimmen jetzt mit dem Code überein.
- **Tests:** `StreamBufferTest$StatisticsTests#statistics_writeFromTrimStartHook_isCounted` (Hook schreibt `{10,11,12}` beim ersten Trim; danach `getTotalBytesWritten()` und `getMaxObservedBytes()` 12, nach dem Auslesen `getTotalBytesRead()` 12 und gleich `getTotalBytesWritten()`), `#statistics_readFromTrimStartHook_isCounted` (Hook liest ein Byte; `getTotalBytesRead()` 1, geschrieben 9, verfügbar 8).
- **Rot-Grün-Nachweis:** ohne Fix rot („Expected: is <12L> but: was <9L>“ dreimal im Schreibtest – geschrieben, maxObserved und geschrieben gegen gelesen –, „Expected: is <1L> but: was <0L>“ im Lesetest), mit Fix grün (`StatisticsTests` 15/15). Breit: ganze Suite grün (306/306: `StreamBufferTest`, jqwik, Lincheck, Architektur), SpotBugs ohne Befund, PIT 197/197 (vorher 199: die beiden Mutanten der entfernten Wächter entfallen).
- **Status:** gefixt
- **Commit:** 00fc010

## Offene Verdachte ohne Fund-ID

Keine (Stand 2026-10-18).
