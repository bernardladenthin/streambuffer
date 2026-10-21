# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- OpenSSF Best Practices badge added to README (project 12861).
- `CONTRIBUTING.md` with build instructions, test policy, and PR workflow.
- `SECURITY.md` with vulnerability reporting process and response SLA.
- `CODE_OF_CONDUCT.md` based on the Contributor Covenant 2.0.
- `docs/RELEASE.md` describing the Maven Central release process (moved out of `CHANGELOG.md`).
- Initial `CHANGELOG.md`, retroactively populated from git tags v1.0.0–v1.2.0 and GitHub release notes.
- Cancellable pipeline start-gate via a `startgate` GitHub Environment with configurable wait timer.

### Changed
- Formal verification: the last bundled-spec workaround is gone. OpenJML 21.0.29 also ships the RAC fix
  for `ArrayDeque.jml` (OpenJML/OpenJML#1012), so the setup action no longer deletes any bundled spec
  (fixups v3); RAC 285/285 against the unmodified 21.0.29 distribution. The class-invariant blocker is
  narrowed down: RAC miscompiles an unqualified call from an inner-class method to an outer instance
  method (`writeSingleByte(b)` in `SBOutputStream`), see TODO.md.
- **Documented: `read(byte[], off, len)` waits for all `len` bytes** (or for `close()`), a deliberate
  deviation from the `InputStream` contract that has been the design since the first version but was
  stated nowhere. The Javadoc of `getInputStream()` and the README ("Full `InputStream`/`OutputStream`
  Compatibility", "Deadlock Behavior → Read") now say so, with the `waitForAnyData()` + `available()`
  pattern for request/response protocols; the README's `maxAllocationSize` default reads
  `Integer.MAX_VALUE - 8`, as the code has it.
- Build tooling: spotbugs-maven-plugin 4.10.4.1 -> 4.10.5.0 (SpotBugs 4.10.5, the first release that reads
  JSpecify; nothing to report here), in step with the sibling repositories.
- Build and test tooling bumped in step with the sibling repositories: Spotless 3.10.4 and Checker
  Framework 4.3.1. The shared `check-versions.py` now also compares the Kotlin Gradle plugins of a
  repository with its POMs' Kotlin (nothing to compare here) and reads java-llama.cpp's
  `examples/server/pom.xml`.
- **CI prints the runner's CPU** at the top of `test`, `vmlens` and the three formal-verification jobs
  (`.github/print-host-info.sh`, a shared file of the four repositories): Z3's proof times and the
  Lincheck and jcstress runs depend on it.
- Formal verification: OpenJML 21.0.29 (from 21.0.28). ESC 14/14 (1.7 s locally: SMT commands are now
  pipelined) and RAC 285/285 unchanged. The `AtomicLong.jml` workaround is gone -- the upstream fix
  (OpenJML/Specs#29) shipped in 21.0.29 -- while `ArrayDeque.jml` was still deleted at install. Class
  invariants still break RAC (now `NoSuchMethodError` on the inner stream classes), so they stay out.
- Build tooling: `anthropics/claude-code-action` v1.0.255 (from v1.0.252) and Gradle 9.8.2 in the shared
  `verify-signing-key-gradle` job, in step with the sibling repositories.
- Formal verification: OpenJML 21.0.28 (from 21.0.27; default solver z3 5.1.0). ESC 14/14 and RAC
  285/285 unchanged; the bundled-spec workarounds stay (the upstream fixes are not in 21.0.28).
- **CI: shared files and the release gate are checked.** The files kept byte-identical with the sibling
  repositories are listed with their SHA-256 in `.github/shared-files.sha256`; a new `shared-files` job
  fails on a copy changed here alone and warns on a sibling's differing copy. The same job runs the
  shared build-check library's tests and `check-release-gate.py`: every job must gate both publish
  jobs unless `.github/release-gate-exemptions.txt` says why (`vmlens` now gates). The crash-log step
  and the signing-key preflight are shared scripts (`print-crash-logs.sh`, `verify-signing-key.sh`)
  instead of copies pasted into the workflow.
- **Workflow jobs kept identical across the repositories are checked too**: a
  `.github/shared-files.sha256` entry `.github/workflows/publish.yml#<job>` hashes one job (`startgate`,
  `shared-files`, `verify-signing-key`, `check-snapshot`, `check-tag`, and where present
  `verify-signing-key-gradle`, `github-snapshot`, `github-release`).
- **More shared files, and files identical up to the repository name**: a shared-files entry ending
  in `?repo` is hashed with the repository's name replaced by `{repo}`. Added: `.editorconfig`,
  `.gitattributes` (now with `*.gguf binary` everywhere), `FUNDING.yml`, `CODEOWNERS`, the license texts,
  `SUPPORT.md`, `ISSUE_TEMPLATE/config.yml` and further files listed in `.github/shared-files.sha256`;
  the signing self-test now runs on Gradle 9.8.0 in all four repositories.
- **The JDK is named once, in `.java-version`**: every workflow reads it through setup-java's
  `java-version-file` (the `JAVA_VERSION` env and the literal `21`s are gone); `.java-version` and
  `codeql.yml` are now byte-identical in all four sibling repositories and in the shared-files manifest.
  The one-JDK `test` matrix became a plain job on `.java-version` (check name `Test`, crash artifact
  `crash-dumps`); the JPF job still pins 11 + 21 explicitly, since jpf-core needs JDK 11.
- **CI files are licensed `MIT OR Apache-2.0`**: every `.github` file carrying only the owner's
  copyright now has the same license header in all four sibling repositories, so the shared ones are
  byte-identical. `claude.yml`, `claude-code-review.yml`, `scorecard.yml`, `reuse.yml`,
  `osv-scanner.yml`, `dependabot.yml` and `CODE_OF_CONDUCT.md` joined the shared-files manifest;
  `osv-scanner.yml` now grants `contents: read` instead of `read-all` (as java-llama.cpp already did).
- **Workflow run scripts are parsed in the `shared-files` job**: `check-run-scripts.py` runs `bash -n`
  over every `run:` script of the workflows and composite actions that runs in bash (shell decided as
  the runner does), so a broken script fails within minutes instead of in the job that runs it.
- **Maven versions are compared with the sibling repositories**: `check-versions.py` (in the
  `shared-files` job) warns where a dependency or plugin -- incl. annotation-processor paths and the
  Spotless formatter version -- is used in another version than in a sibling's default branch.
- Build and test tooling bumped to latest stable in step with the sibling repos: spotless 3.10.2 → 3.10.3,
  palantir-java-format 2.98.0 → 2.99.0, NullAway 0.14.1 → 0.14.2, archunit-junit5 1.5.0 → 1.5.1.
- Build plugins bumped to latest stable: `com.diffplug.spotless:spotless-maven-plugin` 3.9.0 → 3.10.0,
  `com.github.spotbugs:spotbugs-maven-plugin` 4.10.3.0 → 4.10.4.0 (restores parity with the
  cross-repo tool-version matrix).
- CI actions bumped to latest: `actions/setup-java` v5 → v6, `github/codeql-action/*` v4.37.7 →
  v4.37.8, `google/osv-scanner-action` reusable workflows v2.5.0 → v2.5.1.
- CI `publish.yml`: added `check-snapshot`/`check-tag` gate jobs to fix release routing.
- CI `publish.yml`: `softprops/action-gh-release` bumped from v2 to v3.
- CI `publish.yml`: `org.codehaus.mojo:exec-maven-plugin` bumped to 3.6.3.
- Release Process prompt template moved from `CHANGELOG.md` to `docs/RELEASE.md`.
- `maxAllocationSize` defaults to `Integer.MAX_VALUE - 8` (was `Integer.MAX_VALUE`);
  `setMaxAllocationSize` clamps larger values to it.
- **Tests that could pass without checking anything are tightened.** The jqwik properties
  (`StreamBufferProperties`) now run in every build: their class name matched none of Surefire's
  default include patterns, so they ran nowhere; under `-Pjml-rac` they use 100 tries instead of 1000.
  The concurrent `safeWrite` test records every failure of its background threads and checks the byte
  count, since `Waiter.resume()` never rethrows and a reader that died early left it green. A test
  whose wrapping output stream threw before it reached the buffer is removed (its message was the
  test's own). A new test pins that `close()` waits for a write on another thread, the half of the
  write/close fix the existing single-threaded test does not see. The close-during-trim tests describe
  the current `trim()`, which copies straight from the FIFO, instead of a read phase and a write-back
  through the streams.
- **Formal verification: a third JPF harness** (`WriteClose.jpf`) model-checks writer, closer and
  reader in three threads, i.e. the order of write and close, which the existing harness cannot see.
  Under RAC the two stress loops of `StreamBufferTest` are scaled down (`streambuffer.test.rac`):
  RAC prints a stack trace for every `System.arraycopy`/`clone` (OpenJML/OpenJML#1050), and unscaled
  the job ran into its timeout with every contract holding.

### Fixed
- **`safeWrite` could be bypassed by a concurrent `write(int)`.** A single-byte write set an
  instance-wide flag that told an array write running on another thread not to clone its array, so
  with `setSafeWrite(true)` the caller's array could land in the buffer by reference and later changes
  to it reached the reader. The flag is gone; whether to clone is a parameter of the private write path.
- **A concurrent `trim()` no longer lets a reader see a half-emptied buffer.** `trim()` drained the
  buffer through its own input stream and wrote the bytes back, so the buffered count fell to 0 and rose
  again while `read()` and `waitForAtLeast` read it without the lock: a reader could get fewer bytes
  than requested, or end of stream, on an open stream. `trim()` now copies the entries straight from the
  FIFO into blocks of at most `maxAllocationSize` and leaves the count unchanged.
- **A `write` racing `close()` from another thread can no longer land after the close.** The closed
  check ran before the lock was taken and `close()` set the flag without it, so a writer that had passed
  the check could append after a reader had seen "closed, 0 bytes" and reported end of stream. The check
  now runs under `bufferLock` and `close()` sets the flag under the same lock: a write is either fully
  buffered before the close or fails with "Stream closed"; `close()` waits for a write or `trim()` in
  progress on another thread.
- **CI: the GitHub `snapshot` pre-release holds exactly the current build, and the release assets
  include the pom.** `gh release upload --clobber` replaces same-named assets and never removes any
  other, so the `snapshot` release accumulated: the 1.2.0-SNAPSHOT jar and javadoc jar (unsigned, from before the
  signature check existed) and three SpotBugs plugin jars (`fb-contrib-7.6.4.jar`, `fb-contrib-7.7.4.jar`,
  `findsecbugs-plugin-1.14.0.jar`) an old collect step uploaded from `target/spotbugs/` in 2026-05, 5 of its
  11 assets. `github-snapshot` now deletes every asset
  the run did not upload, after the upload and each printed by name; it refuses an empty upload,
  treats an asset that is already gone as removed and fails only after trying every deletion (asset
  by asset on purpose: the job's first form deleted and recreated the release, and failed in every
  burst of main pushes in May 2026); versioned releases are never pruned, and the next snapshot run
  clears the backlog by itself. The collect steps copy
  `<artifactId>-<version>.pom` + `.pom.asc` as well (Central had them, the release did not), and
  the signature check counts every attachable type (`*.jar`, `*.aar`, `*.pom`) instead of jars
  alone. Shared job text with the two sibling repositories (`shared-files.sha256`), the convention
  in `workspace/policies/fat-jar-release-assets.md`.
- **CI: snapshot deploy fails with HTTP 401 on Maven 3.10 (seen in java-llama.cpp).** The runners moved to Maven 3.10, which
  sends a `<server>`'s credentials only to the origins declared for it; for the id `central` that is
  `https://repo.maven.apache.org`, so the upload to `central.sonatype.com/repository/maven-snapshots/`
  goes out without credentials ("Not using credentials of server 'central'"). Every `deploy` step now
  passes `-Dmaven.repository.credentialScope=id`, Maven's own switch back to id-only matching, until a
  setup-java release can write `<repositoryOrigins>` (`mvn-server-repository-origins`, merged upstream
  but not yet released).
- **Statistics count the I/O of a trim start signal.** A write or read made from a trim start
  signal's `release()` on the trim thread changed the buffered count but was left out of
  `getTotalBytesWritten()`, `getMaxObservedBytes()` and `getTotalBytesRead()`, contrary to their
  Javadoc and to `written == read + available`. The guards dated from when `trim()` read and wrote
  through the streams itself; it copies straight from the FIFO now, so every counted byte is user
  I/O. `isTrimRunning` still prevents a nested trim.
- `trim()` with more than 2 GB buffered no longer allocates `new byte[Integer.MAX_VALUE]`, which the
  JVM always rejects ("Requested array size exceeds VM limit"). Allocations are capped at
  `Integer.MAX_VALUE - 8`, the JDK's `SOFT_MAX_ARRAY_LENGTH`.

## [1.2.0] - 2026-05-11

### Added
- Statistics tracking: `getTotalBytesWritten()`, `getTotalBytesRead()`, `getMaxObservedBytes()` — user I/O only, excluding internal trim operations.
- Configurable trim allocation size via `setMaxAllocationSize(long)` / `getMaxAllocationSize()`; trim may produce multiple smaller chunks when `availableBytes > maxAllocationSize`.
- Trim observer signals: `addTrimStartSignal(Semaphore)`, `removeTrimStartSignal(Semaphore)`, `addTrimEndSignal(Semaphore)`, `removeTrimEndSignal(Semaphore)`.
- `isTrimRunning()` volatile flag reflecting active trim execution.
- `decideTrimExecution` pure function with comprehensive table-driven tests.
- `getBufferElementCount()` synchronized method (preferred over legacy `getBufferSize()`).
- JMH throughput benchmark (`StreamBufferThroughputBenchmark`) replacing the prior ad-hoc memory test.
- CI: JARs are now attached to GitHub Releases on tag push.
- CI: GitHub Packages snapshot pre-release updated on every push to `main`.
- CI: unified `publish.yml` with Sonatype Central Portal publishing (replaced OSSRH).
- CI: CodeQL workflow with `security-and-quality` query suite.
- CI: Coveralls and Codecov coverage reporting.
- CI: PIT mutation testing in the report job (100% mutation coverage threshold).
- Claude Code review workflow (`claude-code-review.yml`).
- Dependabot configuration for Maven and GitHub Actions dependencies.

### Changed
- Testing framework migrated from JUnit 4 (`DataProviderRunner`) to JUnit 5 (JUnit Jupiter) with `@Nested` and `@DisplayName` grouping.
- Internal semaphore (`signalModification`) now registered via the public `addSignal` mechanism.
- Listener/callback pattern replaced by signal/slot via external `Semaphore` objects.
- `read()` conditional replaced with `Math.min` to eliminate equivalent mutation.
- All Javadoc comments updated to use HTML entities for operators and Unicode symbols.
- Distribution management migrated from OSSRH to Sonatype Central Publisher Portal.
- GH Actions bumped to latest: `checkout@v6`, `setup-java@v5`, `upload-artifact@v7`, `download-artifact@v8`, `codecov-action@v6`, `codeql-action@v4`.
- Maven plugins updated: JaCoCo 0.8.14, PIT 1.23.0, and others to latest stable.

### Fixed
- Race condition between `trim()` write-back and `close()` — `releaseTrimStartSignals()` moved inside `try-finally`.
- `read(byte[], int, int)` over-read on closed stream — six edge-case tests added.
- Coveralls authentication switched from deprecated token to `GITHUB_TOKEN`.
- JaCoCo re-enabled and JMH run in in-process mode (`-f 0`) to fix CI flakiness.
- CodeQL action bumped from v3 to v4 with explicit workflow permissions.

## [1.1.0] - 2015-02-03

### Added
- `setMaxBufferElements(int)` and `setSafeWrite(boolean)` runtime setters allowing reconfiguration after construction (commit `87cdff1`).

### Changed
- Maven plugins updated to current versions (commit `1fb046f`).
- README and test improvements (commits `3409a44`, `9c467f1`, `d8a8b9e`, `7fe9577`).

## [1.0.1] - 2014-10-31

### Added
- `blockDataAvailable()` method (commit `7a780d5`).

### Changed
- Repository moved to GitHub; version bumped to 1.0.1 (commit `5e3203c`).

## [1.0.0] - 2014-09-17

### Added
- Initial public release of `net.ladenthin:streambuffer` (commit `64e8739`). Project inception year 2014 (per `pom.xml` `<inceptionYear>`).

[Unreleased]: https://github.com/bernardladenthin/streambuffer/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/bernardladenthin/streambuffer/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/bernardladenthin/streambuffer/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/bernardladenthin/streambuffer/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/bernardladenthin/streambuffer/releases/tag/v1.0.0
