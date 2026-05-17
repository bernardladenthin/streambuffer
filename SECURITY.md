# Security Policy

## Supported versions

Only the latest released version of streambuffer receives security fixes. Once a new release is published, the previous release is no longer supported and users are encouraged to upgrade promptly.

| Version                | Supported |
|------------------------|-----------|
| 1.2.x (latest release) | Yes       |
| < 1.2                  | No        |

## Reporting a vulnerability — primary channel

**Please do not report security vulnerabilities through public GitHub Issues.**

Use GitHub's built-in Private Vulnerability Reporting to disclose vulnerabilities confidentially:

**https://github.com/bernardladenthin/streambuffer/security/advisories/new**

This allows you to submit details privately. A maintainer will review the report and respond through the advisory thread.

## Reporting a vulnerability — fallback

If you are unable to use GitHub's private reporting, contact the maintainer directly by email:

- **Primary:** bernard.ladenthin@gmail.com
- **Secondary:** bernard@ladenthin.net

When reporting, please include:

- A clear description of the vulnerability and its potential impact
- Steps to reproduce (minimal Java code if applicable)
- The streambuffer version(s) affected
- Any suggested mitigation or fix

## Response SLA

We aim to:

- **Acknowledge** vulnerability reports within **14 days** of receipt.
- **Provide a remediation timeline** within **30 days** of acknowledgement.

## Coordinated disclosure

This project follows **coordinated disclosure** with a **90-day embargo**:

1. The reporter submits the vulnerability privately.
2. The maintainer investigates and develops a fix.
3. A patched release is prepared and published.
4. The vulnerability details remain under embargo until the fix is publicly released, or for a maximum of 90 days from the date of acknowledgement — whichever comes first.
5. A GitHub Security Advisory is published after the fix is available, crediting the reporter (unless they prefer to remain anonymous).

We ask reporters to honour the embargo period and not disclose vulnerability details publicly until a fix has been released or the embargo expires.

## Scope

**In scope:**

- The streambuffer source code under `src/main/java/net/ladenthin/streambuffer/` and its published Maven Central artifact (`net.ladenthin:streambuffer`).
- Build and release configuration (`pom.xml`, GitHub Actions workflows under `.github/workflows/`) where it affects the integrity of published artifacts.

**Out of scope:**

- Third-party runtime, test, or build dependencies — these are tracked and updated by **Dependabot** and scanned by **CodeQL** (and Snyk / FOSSA). Report dependency CVEs to the upstream project.
- Issues in the JDK, Maven, or other tools used to build streambuffer.

## Security update notifications

To stay informed about security updates:

- **Watch the repository:** GitHub → *Watch* → *Custom* → enable **Security alerts** and **Releases**.
- **Subscribe to releases:** https://github.com/bernardladenthin/streambuffer/releases — every fixed release is published here and to Maven Central.
- **GitHub Security Advisories:** https://github.com/bernardladenthin/streambuffer/security/advisories — public advisories appear here after the embargo lifts.
