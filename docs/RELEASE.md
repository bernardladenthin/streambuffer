# Release Process

The maintainer-facing release procedure is **centralized in the workspace repo**:
[`../workspace/workflows/release-process.md`](../workspace/workflows/release-process.md).

streambuffer is a single-module Maven project (one `pom.xml`, one `README.md` dependency
snippet), so the canonical procedure applies, with one repo-specific step:

- **After a release is on Maven Central, raise `japicmp.baseline.version` in `pom.xml` to it.** The
  API compatibility gate (japicmp, `mvn verify`) compares every build with that release and fails
  when the version step is too small for the change under semantic versioning; with an old baseline
  it measures against the wrong release.
