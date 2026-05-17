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
- CI `publish.yml`: added `check-snapshot`/`check-tag` gate jobs to fix release routing.
- CI `publish.yml`: `softprops/action-gh-release` bumped from v2 to v3.
- CI `publish.yml`: `org.codehaus.mojo:exec-maven-plugin` bumped to 3.6.3.
- Release Process prompt template moved from `CHANGELOG.md` to `docs/RELEASE.md`.

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
