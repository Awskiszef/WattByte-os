# Project status

WattByte is pre-release software: there is no published app version, no store listing and no hosted service that this repository
operates for you. This page says what exists and what a contributor should not assume.

## What exists

| Part | State |
|---|---|
| Mobile app (`apps/mobile`, Flutter, Android and iOS) | Implemented: measurement, local storage, offline-first sync queue, localisation (English, Polish), native Android and iOS integrations (widgets). Tested with unit, widget and end-to-end suites; see [docs/REGRESSION_TESTS.md](REGRESSION_TESTS.md). Device testing is incomplete ([docs/DEVICE_TEST_PLAN.md](DEVICE_TEST_PLAN.md)). |
| API (`apps/api`, Fastify, PostgreSQL) | Implemented: accounts and sessions, per-day aggregate sync, quotas, retention, health and readiness probes, OpenAPI contract, reference Dockerfile (non-root, health check). Integration tests run against PostgreSQL. |
| AI gateway (`apps/ai`) | Implemented as a library: provider routing, retries, fallback, spend limits. The tests are hermetic (mock transports); no provider key is needed to run them. |
| Website (`apps/web`, Next.js) | Implemented. The operator details on its legal pages are placeholders in this repository (`apps/web/src/config/operator.ts`); replace them before you deploy. |
| CI | Scope-aware: only the jobs a change can affect run, a required result job refuses a skipped job the change needed, and a Public Configuration Security Gate runs on every change ([docs/CI_CD.md](CI_CD.md)). |

## What you should not assume

* **Releases.** Signed builds are produced by a manually started workflow with the maintainer's own signing secrets, which are not part of this repository. Build your own by following [docs/RELEASE.md](RELEASE.md) with your own accounts and keys.
* **Known security gaps.** There is no e-mail verification or password reset yet. The list of documented limitations is in [SECURITY.md](../SECURITY.md) and [docs/security.md](security.md).
* **Production readiness.** Treat the API as a reference implementation. Operating it for real needs a deployment, backups and monitoring of your own ([docs/OPERATIONS.md](OPERATIONS.md)).
* **Third-party services.** AI providers, the Eurostat price source and store accounts need credentials or accounts of your own; none is required to compile the code or to run the offline tests.

## Where to start

[README.md](../README.md) for the quickstarts, [docs/DEVELOPMENT.md](DEVELOPMENT.md) for prerequisites and every test command, [CONTRIBUTING.md](../CONTRIBUTING.md) before your first pull request.
