
# Bug-Hunt: geprüfte Stellen — streambuffer

Jede Zeile ist eine gründlich gelesene Produktionsklasse: `Pfad` · Blob-Hash der Datei beim Prüfen · Datum ·
Ergebnis — Notiz. Eine Klasse gilt als erledigt, solange `git rev-parse --short HEAD:<Pfad>` noch denselben
Blob-Hash liefert; hat sich die Datei seitdem geändert, wird sie erneut geprüft und die Zeile ersetzt.
Ergebnisse: `kein Fund`, `widerlegt` (Verdacht geprüft, Code korrekt), `unsicher` (offen, siehe
[`BUGHUNT-FOUND.md`](BUGHUNT-FOUND.md)), `Fund Fnn` (Fehler gefunden und dort beschrieben).

## Geprüft

- `src/main/java/net/ladenthin/streambuffer/package-info.java` · `e30da5b` · 2026-10-17 · kein Fund — gelesen, keine Notiz
- `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` · `5e0f51d` · 2026-10-17 · Fund F02 — streambuffer: `safeWrite` wird von gleichzeitigem `write(int)` ausgehebelt
- `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` (Schnittstelle SBInputStream.read(byte[],int,int) ↔ waitForAtLeast) · `5e0f51d` · 2026-10-17 · kein Fund — Nach dem ersten Byte wartet `readIntoArray` über `waitForAtLeast(len-1)`, also bis zur vollen Länge oder bis zum Schließen, statt nach den verfügbaren Bytes zurückzukehren. Das ist im README (Zeile 328: „To avoid blocking, only read as many bytes as available() reports“) als Verhalten festgelegt und entspricht der Standardimplementierung von `InputStream.read(byte[],int,int)`, die ebenfalls je Byte blockiert; `len == 0` kehrt ohne Warten mit 0 zurück, ein Interrupt wird als `IOException` mit gesetztem Flag gemeldet.
- `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` (Schnittstelle Lese-/Schreibpfad ↔ Statistik und `trim`) · `5e0f51d` · 2026-10-18 · kein Fund — `recordReadStatistics` (1 Byte bzw. je kopiertem Block) und `totalBytesWritten`/`maxObservedBytes` laufen unter `bufferLock`, den `trim()` für seine ganze Dauer hält; das globale Flag `isTrimRunning` kann deshalb nur die eigenen internen Lese-/Schreibvorgänge von `trim` ausblenden, nie die eines anderen Threads. `skip` ist `InputStream`s Vorgabe über `read(byte[])` und wird dort gezählt; das Lesen aus `trim` heraus nutzt den reentranten Monitor desselben Threads.
- `src/main/java/net/ladenthin/streambuffer/StreamBuffer.java` (Schnittstelle `trim()` ↔ `waitForAtLeast`/`read()` über das ungeschützte `availableBytes`) · `95bac9a` · 2026-10-18 · Fund F73 — Signalisierung (max-1-Permit, `close` → Signal) ohne verlorenes Aufwecken nachgerechnet; der Trim las über den eigenen Stream und machte den Zwischenstand des Zählers sichtbar (F73). `skip`/`readAllBytes` laufen über `read(byte[],…)` und erben F03, kein eigener Fund.
