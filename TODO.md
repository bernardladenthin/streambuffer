# TODO — streambuffer

Open work items for this repo. Cross-cutting tracking lives in
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md);
items here are streambuffer-specific or are this repo's slice of a
cross-cutting initiative.

**Completed work is not recorded here.** It lives in git history and in
`crossrepostatus.md`; a finished item is deleted from this file rather than
annotated, so everything below is genuinely still open.

## Open

- **Formal verification — follow-ups.** The two-layer setup (OpenJML ESC proof of the static
  sequential core + OpenJML RAC under the full test suite) landed 2026-09 — see CLAUDE.md
  "Formal Verification" and `.github/workflows/formal-verification.yml`. Still open, in priority
  order:
  - **Checker Framework Lock Checker (deferred, not rejected).** Would soundly gate the
    `@GuardedBy("bufferLock")` discipline (Error Prone gates it heuristically today, in the
    default build). Blocked on a real cascade, not effort aversion: CF's JDK stubs for
    `Closeable`, `InputStream` and `OutputStream` declare mutually inconsistent `close()`
    receiver types (`@GuardSatisfied` vs `@GuardedBy`), so any receiver annotation that
    satisfies one stub violates another — plus `toString()`'s `synchronized` block trips
    `synchronized.block.in.lockingfree.method`. Revisit if CF ships consistent stubs, or gate it
    with a curated `-AskipDefs`/stub override.
  - ~~JPF interleaving harness~~ **DONE (2026-09).** Java PathFinder now exhaustively model-checks
    the concurrent read/write/close protocol over all enumerated interleavings — the erschöpfende
    counterpart to the jcstress stress tests. Lives in `src/test/jpf/` (harness, `.jpf` config, and
    a completed jpf-core `AtomicLong` model patch); wired as the scheduled/dispatch
    `jpf-interleavings` job in `formal-verification.yml`; locally reproducible via the Docker+JDK 11
    recipe in `src/test/jpf/README.md`. Confirmed: `no errors detected`, ~14k states, with a
    negative-control proving the byte-fidelity oracle is non-vacuous. jpf-core is pinned to commit
    `e61e396`. Open sub-item: the AtomicLong model completion is a genuine jpf-core deficiency worth
    reporting upstream (its native peer already implements the methods the stub model never
    declared). Possible extension: a second harness for the array-read / `waitForAtLeast` blocking
    paths (jcstress already covers those; JPF would make them exhaustive too).
  - **OpenJML 21.0.28: bump once its binaries are published.** The tag appeared on 2026-10-01 with
    only GitHub's source archives attached -- no `openjml-ubuntu-24.04-21.0.28.zip`, so there is
    nothing `setup-openjml` could download or hash yet. When the asset is there: update
    `OPENJML_VERSION` + `OPENJML_SHA256` in `formal-verification.yml`, and expect real work rather
    than a version edit -- the release changes the default solver to z3 5.1.0 (from z3 4.x), which
    can move `ESC_EXPECTED_PROOFS`, and its notes do not say whether the two bundled specs the setup
    action deletes (`ArrayDeque.jml`, `AtomicLong.jml`) or the missing `JAVA_VERSION` key were fixed.
    The `rm` without `-f` fails loudly if they are gone, which is the intended signal.
  - **Report the OpenJML bundled-spec defects upstream** (both reproduced on 21.0.27 with a
    minimal standalone class — the reproducers live in this session's notes, re-create before
    filing):
    - `java/util/ArrayDeque.jml:30` has an ungated `//@ instance public invariant !containsNull;`,
      but `containsNull` is declared only in `java/lang/Iterable.jml` behind a `-RAC` key (and
      carries the maintainers' own `// FIXME - get rid of this`). So under `openjml --rac` the
      symbol is undeclared and RAC-compiling any ArrayDeque-using class fails with
      "cannot find symbol: containsNull". ESC is unaffected (it keeps the `-RAC`-gated
      declaration). Confirmed with a 4-line class.
    - `java/util/concurrent/atomic/AtomicLong.jml` keeps `value`-referencing clauses that are not
      `-RAC`-gated (e.g. line 16 `ensures value == v`), so RAC emits a direct read of the private
      `java.base` field `AtomicLong.value`; running the instrumented class on a stock modular JVM
      throws `IllegalAccessError` (compile succeeds, run fails). Confirmed with a 5-line class.
      Also fails on OpenJML's own bundled JVM and via `openjml-java` (re-checked 2026-09-29).
      The maintainers already `-RAC`-gate most `value` clauses → incomplete-guard defect.
      Same defect in `AtomicInteger.jml` / `AtomicBoolean.jml`.
      **Reported (2026-09-30), awaiting maintainer review:**
      [OpenJML/Specs#29](https://github.com/OpenJML/Specs/pull/29) (fix for all three, base
      `master-21`) + [OpenJML/OpenJML#982](https://github.com/OpenJML/OpenJML/pull/982)
      (testspecs, base `master-21`). Verified locally: streambuffer RAC suite green WITH the
      fixed `AtomicLong.jml` (285/285), red with the original (258/285 `IllegalAccessError`).
      Once an OpenJML release ships it: drop the `rm` in `.github/actions/setup-openjml`.
  - **NOT a confirmed OpenJML bug (do not report yet):** during this work RAC once aborted with a
    catastrophic javac `Lower` AssertionError ("no enclosing instance of type
    StreamBuffer.SBInputStream") when the `.jml` declared instance invariants on the class with the
    non-static inner stream classes. That crash was real but could NOT be reproduced minimally
    (invariant + inner class, invariant + inner class extending InputStream, and invariant +
    eager inner-class-instance fields all compiled cleanly). Until a minimal reproducer exists it
    is unclear whether it is an OpenJML defect or an artifact of some specific spec construct;
    the invariants stay omitted defensively regardless. Isolate before filing.
  - **Deeper ESC — instance-method / trim() functional correctness (parked, revisit).** Today
    ESC proves the 14 static helpers; the instance methods and trim() are RAC-only. A full
    functional proof (e.g. a ghost model sequence for the deque with the invariant
    `availableBytes == sum of buffered byte[] lengths`, preserved across read/write/trim) is the
    "TimSort-level" target. Currently blocked two ways: OpenJML ESC returns solver "unknown" on
    instance methods of this class (the non-static inner stream classes poison the receiver
    context), and modelling the deque as a ghost `\seq` is large (the LinkedList/KeY study was
    ~7 person-months for 328 LoC). Not gold-plating in principle — just expensive today; worth a
    re-scoping spike to see whether a *partial* invariant (e.g. non-negativity + position bounds
    proven on a static extraction of the read/write inner loops) is reachable more cheaply.
  - **On every OpenJML upgrade:** re-try dropping the two spec-file deletions in
    `.github/actions/setup-openjml/action.yml` (bump the cache-key fixup suffix), and re-try the
    four class invariants documented in the `.jml` header.
  - **Evaluated and rejected 2026-09** (do not re-open without new facts) — deductive/model-checking
    alternatives beyond OpenJML: **KeY 3.0.0** — could
    re-prove the same static scope with archived `.proof` files, but proof replay is
    version-brittle and adds maintenance without widening the scope (generics unsupported, no
    concurrency, no `Deque`/`java.util.concurrent` stubs); **VerCors 2.4.0** — only candidate
    with concurrent-Java separation logic, but models locks as single-entrant, has no
    volatile/JMM semantics and near-empty JDK stubs: verifying StreamBuffer means re-modeling it,
    a research project; **JBMC (cbmc 6.11)** — its JDK-8 model library has no
    `ArrayDeque`/`java.util.concurrent`, thread support officially limited; would only duplicate
    the ESC scope, bounded; **Infer/RacerD v1.3.0** — explicitly "avoids reasoning about weak
    memory and Java's volatile keyword", i.e. blind to exactly this class's design.

- **jqwik pin policy** — see [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md). `jqwik.version ≤ 1.9.3` is mandatory. A standing constraint, not a task: it has to be re-checked whenever the dependency is bumped.

- **`@VisibleForTesting` audit.** `StreamBuffer` has **15** package-private methods that exist so tests can reach them (`decideTrimExecution`, `shouldTrim`, `clampToMaxInt`, `decrementAvailableBytesBudget`, `calculateResultingChunks`, the five `shouldSkipTrim*`/`should*` predicates, `isAvailableBytesPositive`, `isMaxAllocSizeLessThanAvailable`, `shouldCheckEdgeCase`, `recordReadStatistics`, `shouldUpdateMaxObservedBytes`, `updateMaxObservedBytesIfNeeded`). None is annotated, and Guava is not a dependency here — so closing this means deciding between (a) adding a project-local marker annotation, which puts a new public type into the API surface of a deliberately one-class library, and (b) recording that the convention does not apply to this repo. Decide and act; do not leave it as a permanently open audit.

- **Null-safety refinement.** JSpecify + NullAway are enforced at compile time in **strict JSpecify mode** with the extra options `CheckOptionalEmptiness`, `AcknowledgeRestrictiveAnnotations`, `AcknowledgeAndroidRecent`, `AssertsEnabled` (see `pom.xml`); the package carries an explicit `@NullMarked` via `package-info.java`. The production code has no `@Nullable` markers because every value is non-null by construction (constructors reject `null`, no `return null` sites). Open follow-up: as new public API surfaces are added, evaluate whether `@Nullable` or `Optional<T>` would be more precise than the implicit non-null default.

- **Cross-repo code-quality TODOs** — see [`../workspace/policies/code-quality-todos.md`](../workspace/policies/code-quality-todos.md) for the canonical `@VisibleForTesting` design-fit review, package hierarchy review, and class/method naming review. This module is single-package, so the package review is trivially satisfied; the naming review is still open.
