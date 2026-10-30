# Security policy

## Reporting a vulnerability

Please do **not** open a public issue or pull request for a security problem.

Use GitHub's private vulnerability reporting: on the repository page choose **Security** > **Report a vulnerability**
(https://github.com/Awskiszef/WattByte/security/advisories/new). Include what you found, how to reproduce it, the version or
commit, and what an attacker gains. We aim to acknowledge a report within 7 days and to tell you what we plan to do within 30.
Please give us a reasonable time to fix the problem before you disclose it.

Please do not run tests against a production deployment, access other people's data, or send high volumes of traffic.

## Supported versions

WattByte has no released version yet. Fixes go to `main`; once releases exist, only the latest release is supported.

## What is in scope

The API (`apps/api`), the AI gateway (`apps/ai`), the mobile app (`apps/mobile`), the website (`apps/web`) and the CI/release
workflows (`.github/workflows`). Findings in third-party dependencies are welcome if WattByte uses the vulnerable code path.

## Known limitations

The known, documented gaps (for example no e-mail verification or password reset yet) are listed in
[docs/security.md](docs/security.md). Reports about those
are still useful if you can show a concrete attack.

## Secrets

This repository must never contain credentials. If you find one, report it as above instead of using it.
