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

**Ergebnis:**

**Folgerung:**

---

## S2 vmlens: Leser/Schreiber-Verschränkungen

```bash
mvn -B -Pvmlens test
```

**Hypothese.** Grün.
**Ergebnis:**

**Folgerung:**

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

**Ergebnis:**

**Folgerung:**

---

## S4 Optional: JPF-Harness mit einem dritten Thread, der schließt

Das heutige Harness (`src/test/jpf/`) schreibt und schließt aus demselben Thread und sieht das Rennen aus
F149 deshalb nicht. Ein Wegwerf-Harness mit Schreiber-, Schließer- und Leser-Thread, erschöpfend modellgeprüft,
würde die Reihenfolge Schreiben/Schließen beweisen. Ergebnis und Harness-Quelltext hier eintragen, nicht
committen.

**Entscheidet.** Ob das erweiterte Harness dauerhaft aufgenommen werden soll.

**Ergebnis:**

**Folgerung:**
