# TODO — streambuffer

Open work items for this repo. Cross-cutting tracking lives in
[`../workspace/crossrepostatus.md`](../workspace/crossrepostatus.md);
items here are streambuffer-specific or are this repo's slice of a
cross-cutting initiative.

## Open

- **jqwik pin policy** — see [`../workspace/policies/jqwik-prompt-injection.md`](../workspace/policies/jqwik-prompt-injection.md). `jqwik.version ≤ 1.9.3` is mandatory.

- **`@VisibleForTesting` audit.** No usages currently. Walk the production tree for package-private/protected methods or fields that exist purely so tests can reach them, and either annotate (`com.google.common.annotations.VisibleForTesting`) or move into the test source tree.

- **Null-safety refinement.** JSpecify + NullAway are enforced at compile time in **strict JSpecify mode** with the following extra options: `CheckOptionalEmptiness`, `AcknowledgeRestrictiveAnnotations`, `AcknowledgeAndroidRecent`, `AssertsEnabled` (see `pom.xml`). The package carries an explicit `@NullMarked` via `package-info.java`. The production code currently has no `@Nullable` markers because every value is non-null by construction (constructors reject `null`, no `return null` sites). Open follow-up: as new public API surfaces are added, evaluate whether `@Nullable` or `Optional<T>` would be more precise than the implicit non-null default.

- **SpotBugs `effort=Max` + `threshold=Low`** — currently default effort/threshold. Raising both surfaces more findings (and takes longer per build). Worth a one-off experiment to triage what appears before committing. Cross-cutting (tracked in `crossrepostatus.md`).

- **No LogCaptor smoke test needed** — this module has no logging code (`org.slf4j.*` not used in `src/main/java/`). If logging is ever introduced, add a LogCaptor smoke test at the same time so the binding/configuration is exercised in tests.

- **Cross-repo code-quality TODOs** — see [`../workspace/policies/code-quality-todos.md`](../workspace/policies/code-quality-todos.md) for the canonical `@VisibleForTesting` design-fit review, package hierarchy review, and class/method naming review. This module is single-package and has no `@VisibleForTesting` usages; the package and naming reviews remain open.

## Done (kept for history)

- **Error Prone bug-pattern promotions to `ERROR`** — `ad95d66` (12 patterns promoted).
- **`javac -Werror` + `-Xlint:all,-serial,-options,-classfile,-processing`** — `7a4fbf0`. ElementType.MODULE blocker resolved by the module-level `@NullMarked` move.
- **`-parameters` javac arg** — `912f14b`.
- **`--release N`** instead of `-source N -target N` — `912f14b`.
- **Mutation-testing threshold enforcement (PIT)** — 100 % over the whole package.
- **Checker Framework as a second static-nullness pass** — `5a9be1b`.
- **JPMS `module-info.java`** — exports `net.ladenthin.streambuffer`; two-execution `maven-compiler-plugin` pattern (release 8 sources, release 9 module-info); the resulting jar carries `module-info.class` at its root and is backward-compatible with Java 8 classpath consumers. Module-level `@NullMarked` was intentionally NOT added — the per-package `package-info.java` annotation already covers the same nullness scope.
- **Banned-API enforcement** — Maven Enforcer (`c0148c8`); ArchUnit `Thread.sleep` / `System.exit` / `new Random` bans (`eaf4337`).
- **ArchUnit additions** — public-fields-final (`5dd816d`), internal-JDK banned-imports (`de29bd4`), `noTestFrameworksInProduction` + `noPackageCycles` (`bbdb505`). Full `layeredArchitecture` is N/A: this module is a single-package library.
- **Abstract the Java and test writing guidelines to a workspace-level shared layer.** Workspace version chain at [`../workspace/guides/src/CODE_WRITING_GUIDE-8.md`](../workspace/guides/src/CODE_WRITING_GUIDE-8.md) and [`../workspace/guides/test/TEST_WRITING_GUIDE-8.md`](../workspace/guides/test/TEST_WRITING_GUIDE-8.md). Canonical TDD skill at [`../workspace/.claude/skills/java-tdd-guide/SKILL.md`](../workspace/.claude/skills/java-tdd-guide/SKILL.md). This repo has no project-specific writing-guide supplements (production code is a single class).
- **Standardised CLAUDE.md template** — [`../workspace/templates/CLAUDE.md.template`](../workspace/templates/CLAUDE.md.template).
