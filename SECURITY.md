# Security Policy

## Supported Versions

Only the latest minor release of the current major version receives security fixes.

| Version | Supported |
|---------|-----------|
| 1.2.x (latest release) | Yes |
| < 1.2 | No |

Once a new minor or patch release is published, the previous release is no longer supported. Users are encouraged to upgrade promptly.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub Issues.**

### Primary: GitHub Private Vulnerability Reporting

Use GitHub's built-in private vulnerability reporting to disclose vulnerabilities confidentially:

**https://github.com/bernardladenthin/streambuffer/security/advisories/new**

This allows you to submit details privately. A maintainer will review the report and respond through the advisory thread.

### Secondary: Maintainer Email

If you are unable to use GitHub's private reporting, you may contact the maintainer directly at:

**bernard.ladenthin@gmail.com**

> **Note:** This email address is taken from the project's `pom.xml` developer record and has not been separately confirmed as a security contact. GitHub Private Vulnerability Reporting is the preferred channel.

When reporting, please include:

- A clear description of the vulnerability and its potential impact
- Steps to reproduce (minimal Java code if applicable)
- The streambuffer version(s) affected
- Any suggested mitigation or fix

## Response SLA

We aim to acknowledge vulnerability reports within 14 days of receipt and to provide a remediation timeline within 30 days.

## Disclosure Policy

This project follows **coordinated disclosure**:

1. The reporter submits the vulnerability privately.
2. The maintainer investigates and develops a fix.
3. A patched release is prepared and published.
4. The vulnerability details remain under embargo until the fix is publicly released.
5. A GitHub Security Advisory is published after the fix is available, crediting the reporter (unless they prefer to remain anonymous).

We ask reporters to honour the embargo period and not disclose vulnerability details publicly until a fix has been released.
