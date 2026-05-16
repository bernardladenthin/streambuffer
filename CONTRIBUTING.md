# Contributing to streambuffer

Thank you for your interest in contributing to **streambuffer** — a single-class Java library that bridges `OutputStream` and `InputStream` through a dynamic, unbounded FIFO queue.

## 1. How to Build and Run

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

## 2. Filing Issues

Please open a GitHub Issue at:

**https://github.com/bernardladenthin/streambuffer/issues**

Before opening a new issue, search existing issues to avoid duplicates. Include:

- A minimal reproducible example (Java code snippet + observed vs. expected behaviour)
- Java version and OS
- streambuffer version (or commit SHA if building from source)

## 3. Pull Request Workflow

1. **Fork** the repository on GitHub.
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/my-descriptive-name
   ```
3. **Make your changes** with tests (see [Test Policy](#5-test-policy) below).
4. **Run the full test suite** locally before pushing:
   ```bash
   mvn verify
   ```
5. **Push** your branch to your fork and open a **Pull Request** against `bernardladenthin/streambuffer:main`.
6. Address any review comments and push updates to the same branch.
7. A maintainer will merge once the PR is approved and CI passes.

Keep PRs focused: one logical change per PR makes review faster.

## 4. Coding Standards

- **Java version:** source and binary compatibility targets Java 8; tests may use Java 17 features.
- **Encoding:** UTF-8 (enforced by `project.build.sourceEncoding` in `pom.xml`).
- **Javadoc:** use HTML entities for operators and symbols — never bare Unicode in Javadoc comments. See [`CLAUDE.md`](CLAUDE.md) for the full entity table (`&lt;`, `&gt;`, `&#x2264;`, etc.).
- **Thread safety:** all accesses to the internal `Deque` must remain guarded by `bufferLock`; state fields must remain `volatile`.
- **Formatting:** follow the style of existing source files (consistent indentation, brace placement, etc.). No external formatter is currently enforced by the build, so match the surrounding code.

## 5. Test Policy

> Every new feature or behavior change MUST include automated tests. Pull requests that add or change functionality without corresponding tests will be asked to add tests before merge. Bug fixes SHOULD include a regression test.

Tests live in `src/test/java/net/ladenthin/streambuffer/StreamBufferTest.java` and use JUnit 4 with `DataProviderRunner`. Most behavioural tests are parameterized across three write strategies (`ByteArray`, `Int`, `ByteArrayWithParameter`). New tests should follow the same pattern where applicable.

## 6. Communication Channels

- **GitHub Issues:** https://github.com/bernardladenthin/streambuffer/issues — bug reports, feature requests, and general questions
- **GitHub Discussions:** not currently enabled; use Issues for all communication

## 7. License of Contributions

By submitting a pull request you agree that your contributions will be licensed under the **Apache License, Version 2.0** — the same license that covers this project. See [`LICENSE-2.0.txt`](LICENSE-2.0.txt) for the full text.
