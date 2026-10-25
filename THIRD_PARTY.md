<!--
SPDX-FileCopyrightText: 2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>

SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Third-party license and attribution notes

The project is Apache-2.0. Its only compile dependencies are optional annotation libraries
(Error Prone annotations and JSpecify, Apache-2.0; Checker Framework qualifiers, MIT): consumers
do not receive them transitively, and the JVM never loads them, so the library has no runtime
dependency.
JMH 1.37, JCStress 0.16, Lincheck 3.7, JUnit and jqwik are test-only tools.
Lincheck includes LGPL-3.0-or-later source files as well as its declared MPL license.
A FOSSA scan of the old master revision does not cover this current build.

## Review evidence

See [the dependency license review](docs/dependency-license-review.md) in the source repository
for exact-version evidence and remaining decisions. This inventory is not an approval of all
licenses found by a scanner. Test-tool redistribution requires a separate review.

For unchanged Maven components, source is available from
`https://repo.maven.apache.org/maven2/<groupId with slashes>/<artifactId>/<version>/`
as `<artifactId>-<version>-sources.jar`; POMs and upstream source repositories provide provenance.
Preserve copyright, license and NOTICE files when redistributing dependencies.

streambuffer ships no fat JAR, so `.github/collect-third-party-licenses.py`, which collects
dependency legal files into the runnable fat JARs of BitcoinAddressFinder and srcmorph, is kept
here byte-identical with them but not run.
This source-location statement does not clear unknown proprietary or historical Git findings.
