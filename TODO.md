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
  - **Report the three OpenJML defects upstream** (all reproduced on 21.0.27, all documented in
    the spec-file header / setup-openjml action): bundled `ArrayDeque.jml` references undeclared
    `containsNull`; bundled `atomic/AtomicLong.jml` makes RAC emit an access to the private field
    `AtomicLong.value` (`IllegalAccessError` at test runtime); RAC crashes with a javac `Lower`
    AssertionError ("no enclosing instance") when a class with non-static inner classes declares
    any instance invariant.
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
