<!--
SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: Apache-2.0
-->

# Long verification runs on a rented machine

CI runs the formal checks in sizes that fit a runner (`formal-verification.yml`). What needs more
runs on a rented Linux machine: the A18 scenarios (CI runs the smallest; the larger take hours to
days of JPF and TLC each), all TLAPS proofs at once, `check.sh` with every model. This directory has the scripts
for that, independent of the provider. Which provider, machine and account a run used stays in the
owner's private notes, never in this repository.

| Script | Where | What |
|---|---|---|
| `pack.sh` | local | builds the payload: the TLA+ and JPF sources, the instrumented classes, the annotation jars, the A6 traces, the workflow with the tool pins, the commit |
| `setup.sh` | machine | installs JDK 11 (and 21 for Apalache), tla2tools, Apalache, jpf-core with the AtomicLong patch, tlapm, at the versions and checksums of the workflow |
| `run-a18.sh` | machine | `check-graph.sh` with its controls for every scenario of `a18-scenarios.txt`, several at once, no time limit |
| `run-formal.sh` | machine | `check.sh`, `inductive.sh`, `trace.sh` with its controls, every proof module of `proof.sh`, all at once, no time limit |
| `detach.sh` | machine | starts a run so that it outlives the ssh session and the ssh call returns |
| `status.sh` | machine | one look at a run: progress, results so far, processes, memory, disk, warnings |
| `lift-timeout.sh` | machine | lifts the limit of a run started under `timeout`, without losing it |

## The run, step by step

1. **Size the machine.** A18: each scenario at once needs its JPF heap (`JPF_HEAP`, 7 GB) plus
   about 3 GB for TLC, and about 4 cores (JPF is single-threaded, TLC gets 4 workers);
   `run-a18.sh` picks the parallelism from memory and cores (at most a quarter of the cores). Proofs: cores (`PROOF_THREADS` per
   module, all modules at once). Disk: TLC's dump of a product reaches several GB per scenario
   while it runs (deleted when the scenario ends); 100 GB is plenty.
2. **Note the machine first, then start it.** Before anything runs, write the instance, its
   address and the path of its key into the private notes, so nothing is left running unknown if
   the session ends. Create a key pair for this machine only (`ssh-keygen -t ed25519 -N "" -f
   <key>`); never reuse a personal key, never a password.
3. **Pack and upload.**
   ```bash
   src/test/remote/pack.sh                                   # target/remote/payload.tgz
   S="ssh -i <key> -o IdentitiesOnly=yes -o UserKnownHostsFile=<known_hosts of this machine> -o BatchMode=yes root@<host>"
   scp -i <key> -o IdentitiesOnly=yes -o UserKnownHostsFile=<known_hosts> target/remote/payload.tgz root@<host>:/root/
   $S 'mkdir -p /root/run && tar xzf /root/payload.tgz -C /root/run'
   ```
   A known-hosts file per machine (`StrictHostKeyChecking=accept-new` on the first call) keeps
   the personal one clean; addresses are reused for other machines.
4. **Set up and start, detached.**
   ```bash
   R=/root/run/sb/src/test/remote
   $S "bash $R/detach.sh /root/run/out/setup.out bash $R/setup.sh tlc jpf swap"
   # when /root/run/out/setup.log ends with "setup done":
   $S "bash $R/detach.sh /root/run/out/a18.out bash $R/run-a18.sh"
   # or the TLA+ checks and proofs (setup.sh tlc apalache tlapm first):
   $S "bash $R/detach.sh /root/run/out/formal.out bash $R/run-formal.sh"
   ```
5. **Watch it every 30 minutes**, with `$S "bash $R/status.sh"` (exit 1 at a WARN, 2 once every run is DONE). Stop the run
   (and the machine) at a WARN: memory or disk almost full, or nothing computing without `DONE`.
   A run that is merely slow goes on: there is no time limit.
6. **Copy the results off before anything is destroyed**:
   `scp -r -i <key> ... root@<host>:/root/run/out <local results dir>`, then put the numbers into
   the READMEs (with the date, the commit from `COMMIT`, the machine's cores and memory, never its
   provider or address).
7. **Destroy the machine and sweep**: list the account's machines, volumes and snapshots
   afterwards and remove whatever this run left. Then the throwaway key at the provider (the owner
   decides), and the entry in the private notes.

## Pitfalls, each met once

- **No time limit.** A scenario cut off at a limit (`timeout 4h`, `12h`) has no result, and the
  hours up to it are paid for nothing. The run scripts have none; `status.sh` shows progress
  instead. A limit already running is lifted with `lift-timeout.sh`, never by killing `timeout`
  (its caller then takes the scenario as ended and deletes the dump TLC is still writing).
- **An ssh call that does not return.** `ssh host 'cd x && cmd &'` stays open as long as `cmd`
  runs: the subshell around it holds ssh's output. `detach.sh` gives the command a session of its
  own and points every file descriptor at the log or `/dev/null`.
- **tlapm's leftover provers.** tlapm can leave an Isabelle or z3 running after it ends, which slows
  the next proof into timeouts. Each proof runs in a process group of its own (`setsid`) that is
  killed when tlapm ends, and in a directory of its own (`.tlacache` per directory).
- **ENABLED proofs under load** need `--stretch 12` (one timed out at 3 and 6 with the other cores
  busy); `run-formal.sh` uses it for the `*Enabled` modules, as `proof.sh` does.
- **Tool versions drift.** `setup.sh` reads every pin (tla2tools, Apalache, jpf-core, tlapm,
  OCaml, Isabelle) from the workflow in the payload and checks the checksums CI checks, so a
  machine proves with the tools CI uses.
- **JPF needs JDK 11** (jpf-core's build and run); TLC runs on it too, Apalache needs 17 or later.
- **Kill by PID**, never `pkill -f <pattern>`: a pattern also hits the shells and the other runs
  whose command lines contain it.
- **Windows line endings.** A script written on Windows fails on the machine with `$'\r'`; the
  repository's `.gitattributes` keeps these files LF, a script from elsewhere needs
  `sed -i 's/\r$//'` first.
- **Memory peaks after a day of JPF.** `graphmin.py` holds a scenario's whole graph in memory.
  Its first version kept every edge as Python objects (about 150 bytes each): two scenarios with
  two readers ended JPF within minutes of each other after 20 hours, with 9 GB graphs each, and
  one `graphmin.py` alone filled 62 GB and 74 GB of swap before its parse ended. Now the edges are
  flat integer arrays (0.9 GB peak for a 1.36 GB graph); `run-a18.sh` still lets them take turns
  (`GRAPHMIN_LOCK`), and `setup.sh swap` (in its default) adds swap, so that a peak slows the run
  instead of the OOM killer ending a JPF or TLC that has computed for hours.
- **A scenario cut off after its JPF.** The graph and the JPF log stay in its `WORK`;
  `REUSE_GRAPH=1 check-graph.sh ...` with the same `WORK` runs the rest of the chain from them
  (checked as a new graph: the trailer, no JPF error), without repeating the day of JPF.
- **Big dumps.** `-dump dot` of TLC grows to GBs per scenario; `run-a18.sh` deletes it when the
  scenario ends, the logs keep the numbers.
- **Nothing private in the payload or the results.** `pack.sh` packs sources, classes and the
  public workflow only. Results name the commit and the machine's size; keys, addresses, account
  and provider stay in the private notes.
