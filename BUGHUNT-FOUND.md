
# Bug-Hunt: gefundene Fehler — streambuffer

Fortlaufendes Fundbuch der Fehlersuche auf dem Arbeitsbranch `ccr-90fc5f6a-vs4s0f`. Jeder Fund hat eine
globale ID (`Fnn`, über alle drei Repos eindeutig), Datei:Zeile, Schwere, Beschreibung, Reproduktion (Testname),
Status und Commit. Neue Funde werden **unten angehängt**; die nächste freie ID ist die höchste ID in allen drei
Repos plus eins. Geprüfte Klassen ohne Fund stehen in [`BUGHUNT-CHECKED.md`](BUGHUNT-CHECKED.md).

## Übersicht

- [F02](#f02) — mittel — *gefixt*
- [F03](#f03) — mittel — *Designentscheidung, offen für den Nutzer*

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

## Offene Verdachte ohne Fund-ID

- keine
