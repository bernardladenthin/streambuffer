
# Bug-Hunt: gefundene Fehler — streambuffer

Fortlaufendes Fundbuch der Fehlersuche auf dem Arbeitsbranch `ccr-90fc5f6a-vs4s0f`. Jeder Fund hat eine
globale ID (`Fnn`, über alle drei Repos eindeutig), Datei:Zeile, Schwere, Beschreibung, Reproduktion (Testname),
Status und Commit. Neue Funde werden **unten angehängt**; die nächste freie ID ist die höchste ID in allen drei
Repos plus eins. Geprüfte Klassen ohne Fund stehen in [`BUGHUNT-CHECKED.md`](BUGHUNT-CHECKED.md).

## Übersicht

- [F02](#f02) — mittel — *gefixt*
- [F03](#f03) — mittel — *Designentscheidung, offen für den Nutzer*
- [F73](#f73) — hoch — *gefixt*

## Funde

<a id="f02"></a>
### F02 – streambuffer: `safeWrite` wird von gleichzeitigem `write(int)` ausgehebelt
- **Zeit:** 2026-10-16 23:05 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:1015` (`writeSingleByte`), `:1057` (Klon-Entscheidung in `writeFromArray`)
- **Schwere:** mittel
- **Beschreibung:** `writeSingleByte()` setzte das **instanzweite** `volatile` Feld `ignoreSafeWrite=true` um seinen eigenen Schreibvorgang. Läuft auf einem anderen Thread gleichzeitig `write(byte[])` mit `setSafeWrite(true)` und bekommt den Lock in diesem Fenster, wird das Array **nicht** geklont, sondern per Referenz in die Deque gelegt. Ändert der Aufrufer sein Array danach (genau das, wovor `safeWrite` schützen soll), liest der Leser die geänderten Bytes. Klassen-Javadoc erlaubt gleichzeitige Aufrufe; ein Test im Repo spricht von „concurrent writers“.
- **Reproduktion:** `StreamBufferTest$ConcurrentReadWriteTests#safeWrite_concurrentSingleByteWrite_arrayStillCloned` – vor dem Fix rot (geänderte Bytes beim Leser), danach grün; ganze `StreamBufferTest` 286/286 grün.
- **Status:** gefixt (Feld entfernt, Klon-Erlaubnis als Parameter der privaten Schreibmethode). Nicht geprüft: OpenJML-ESC/RAC-Pipeline (die privaten Schreibmethoden stehen nicht in der `.jml`), PIT, jcstress.
- **Commit:** streambuffer `fb371e0`

<a id="f03"></a>
### F03 – streambuffer: `read(byte[],off,len)` wartet auf **alle** `len` Bytes (Abweichung vom `InputStream`-Vertrag)
- **Zeit:** 2026-10-16 23:10 UTC
- **Datei:** `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java:912` (`readIntoArray`, „second wait phase“ `waitForAtLeast(missingBytes)`)
- **Schwere:** mittel (falls nicht gewollt) / keine (falls gewollt)
- **Beschreibung:** Nach dem ersten Byte wartet `readIntoArray` mit `waitForAtLeast(len-1)`, bis der Rest **vollständig** da ist oder der Stream geschlossen wird. `InputStream.read(byte[],int,int)` verlangt nur, bis mindestens ein Byte verfügbar ist zu blockieren, und dann zurückzugeben, was da ist. Praktische Folge: Ein `InputStreamReader`/`BufferedReader` (liest in 8-KiB-Blöcken) über einem offenen StreamBuffer hängt bei einem Request/Response-Protokoll, bis 8 KiB zusammengekommen sind oder geschlossen wird. README („second wait phase“) und die jcstress-Tests zeigen, dass das Verhalten bewusst so gebaut ist – darum kein Fix, nur zur Entscheidung.
- **Reproduktion:** keine geschrieben (Designfrage).
- **Status:** Designentscheidung, offen für den Nutzer – der Loop fasst diesen Eintrag nicht an (README „second wait phase“ und die jcstress-Tests zeigen, dass das Warten auf alle `len` Bytes gewollt ist). Ändern nur auf ausdrückliche Entscheidung des Nutzers.
- **Commit:** –

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
- **Status:** gefixt
- **Commit:** streambuffer `89d2173`

## Offene Verdachte ohne Fund-ID

- keine
