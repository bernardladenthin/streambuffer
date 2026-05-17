# Contributing to streambuffer

Thank you for your interest in contributing to **streambuffer** — a single-class Java library that bridges `OutputStream` and `InputStream` through a dynamic, unbounded FIFO queue.

## How to build and run

**Prerequisites:** Java 8+ (tests require Java 17+), Maven 3.3.9+

```bash
# Compile
mvn compile

# Run all tests with coverage
mvn test

# Build the JAR
mvn package

# Install to your local Maven repository (skip GPG signing)
mvn install -Dgpg.skip=true

# Run a single test
mvn test -Dtest=StreamBufferTest#testSimpleRoundTrip

# Run mutation tests (PIT)
mvn org.pitest:pitest-maven:mutationCoverage
```

## Reporting issues

Please open a GitHub Issue at:

**https://github.com/bernardladenthin/streambuffer/issues**

Before opening a new issue, search existing issues to avoid duplicates. Include:

- A minimal reproducible example (Java code snippet + observed vs. expected behaviour)
- Java version and OS
- streambuffer version (or commit SHA if building from source)

Security vulnerabilities must **not** be reported via public Issues — see [`SECURITY.md`](SECURITY.md).

## Pull request workflow

1. **Fork** the repository on GitHub.
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/my-descriptive-name
   ```
3. **Make your changes** with tests (see [Test policy](#test-policy) below).
4. **Run the full test suite** locally before pushing:
   ```bash
   mvn verify
   ```
5. **Push** your branch to your fork and open a **Pull Request** against `bernardladenthin/streambuffer:main`.
6. Address any review comments and push updates to the same branch.
7. A maintainer will merge once the PR is approved and CI passes.

Keep PRs focused: one logical change per PR makes review faster.

## Coding standards

- **Java version:** source and binary compatibility targets Java 8; tests may use Java 17 features.
- **Encoding:** UTF-8 (enforced by `project.build.sourceEncoding` in `pom.xml`).
- **Javadoc:** use HTML entities for operators and symbols — never bare Unicode in Javadoc comments. See [`CLAUDE.md`](CLAUDE.md) for the full entity table (`&lt;`, `&gt;`, `&#x2264;`, etc.).
- **Thread safety:** all accesses to the internal `Deque` must remain guarded by `bufferLock`; state fields must remain `volatile`.
- **Formatting:** follow the style of existing source files (consistent indentation, brace placement, etc.). No external formatter is currently enforced by the build, so match the surrounding code.

Additional architectural and Javadoc guidance lives in [`CLAUDE.md`](CLAUDE.md).

## Test policy

> Every new feature or behaviour change MUST include automated tests. Pull requests that add or change functionality without corresponding tests will be asked to add tests before merge. Bug fixes SHOULD include a regression test.

Tests live in `src/test/java/net/ladenthin/streambuffer/` and use **JUnit 5 (Jupiter)** with `@Nested` and `@DisplayName` grouping. Parameterised tests use `@ParameterizedTest` + `@EnumSource(WriteMethod.class)` to exercise the three write strategies (`ByteArray`, `Int`, `ByteArrayWithParameter`). New tests should follow the same pattern where applicable. The legacy JUnit 4 + `DataProviderRunner` stack has been removed.

**Quality gates enforced by the build:**

- **PIT mutation testing** — 100% mutation coverage threshold (`mvn org.pitest:pitest-maven:mutationCoverage`).
- **JaCoCo** — line and branch coverage reported on every `mvn test` / `mvn verify` run.
- **CodeQL** — `security-and-quality` query suite runs in CI.
- **JMH benchmark** — `StreamBufferThroughputBenchmark` exists for throughput experiments but is **not** part of `mvn verify`; it is run on demand.

## Commit message convention

Commits follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. Use one of the standard types:

- `feat:` — a new feature
- `fix:` — a bug fix
- `docs:` — documentation only
- `test:` — adding or correcting tests
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `chore:` — build, tooling, or housekeeping
- `ci:` — CI/CD configuration changes

Example: `fix: prevent over-read on closed stream in read(byte[], int, int)`.

## Communication channels

- **GitHub Issues:** https://github.com/bernardladenthin/streambuffer/issues — bug reports, feature requests, and general questions.
- **GitHub Security Advisories (private):** https://github.com/bernardladenthin/streambuffer/security/advisories/new — vulnerability reports only. See [`SECURITY.md`](SECURITY.md).
- **GitHub Discussions:** **not enabled** for this project. Please use Issues for all non-security communication.

## Code of Conduct

This project adopts the [Contributor Covenant 2.0](https://www.contributor-covenant.org/version/2/0/code_of_conduct/). All contributors and maintainers are expected to abide by it. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Report incidents to **bernard.ladenthin@gmail.com**.

## Releasing

The Maven Central release procedure lives in [`docs/RELEASE.md`](docs/RELEASE.md). Only maintainers run releases.

## License of contributions

By submitting a pull request you agree that your contributions will be licensed under the **Apache License, Version 2.0** — the same license that covers this project. See [`LICENSE`](LICENSE) for the full text.
