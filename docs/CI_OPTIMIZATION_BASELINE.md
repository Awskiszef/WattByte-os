# CI baseline (before the optimisation)

Measured on 2026-10-30 from the GitHub Actions API (`gh api repos/Awskiszef/WattByte/actions/runs` and `.../runs/<id>/jobs`) for **all 75 runs the repository
has ever had** (08:45 to 12:32 UTC that day; the repository had no CI before). Nothing here is read from a billing page: the billing API needs a token scope this
session does not have, so **minutes are computed from job durations** (each job rounded up to a whole minute, macOS counted ten times, as GitHub documents).
The plan allowance used for comparison (2,000 Linux-equivalent minutes per month on the Free plan for private repositories) is GitHub's published figure, not read
from the account.

## What the old pipeline was

`ci.yml` on every pull request and every push to `main`: 15 jobs (secret scan, TypeScript on Node 22 and 24 with PostgreSQL, API production build with Docker, audit,
contracts, Flutter static, release-guard, Flutter tests in three time zones, end-to-end, Android debug APK + AAB + three release-guard builds, Kotlin, the `CI result`
job). A second workflow `ios.yml` built the app on macOS when iOS paths changed. For the first few runs `ci.yml` also had two macOS jobs (Apple Silicon and Intel).
Nothing looked at what a change touched: a one-line documentation change cost the same as a change to the whole app.

## Measured

| | Value |
|---|---|
| Workflow runs in total | 75 (CI 41, iOS 7, Dependabot Updates 27) |
| Jobs | 660 (574 ran; 86 produced no steps: refused by GitHub, see below) |
| CI runs by result | 10 success, 18 failure, 13 cancelled (the cancelled are superseded pushes) |
| Linux minutes billed (CI + iOS workflow, jobs that ran) | **2,172** |
| macOS minutes (raw) | 201, which is **2,010** Linux-equivalent minutes |
| Total Linux-equivalent minutes of those runs | **about 4,180**, i.e. roughly twice the 2,000-minute Free allowance, in about four hours |
| Dependabot Updates runs | 27 runs, about 84 minutes wall time (they run on GitHub-hosted runners too); 9 failed |
| First refusal | 11:51 UTC: "recent account payments have failed or your spending limit needs to be increased" (the 86 jobs without steps) |

The refusal is consistent with the allowance being used up, but the account's actual billing state was not read, so it remains a hypothesis (docs/CI_CD.md, "Status").

## One green pull request, per job (run 41042857531, 15 of 15 jobs)

| Job | Minutes | Billed |
|---|---:|---:|
| Flutter tests, TZ UTC | 11.5 | 12 |
| Android (debug APK, AAB, three release-guard builds) | 11.0 | 11 |
| Flutter tests, TZ America/New_York | 10.8 | 11 |
| Flutter tests, TZ Europe/Warsaw | 7.6 | 8 |
| TypeScript + PostgreSQL, Node 22 | 5.1 | 6 |
| TypeScript + PostgreSQL, Node 24 | 4.3 | 5 |
| End to end | 2.4 | 3 |
| API production build | 1.9 | 2 |
| Contracts | 1.4 | 2 |
| Flutter release configuration guard | 1.2 | 2 |
| Flutter format, analyze | 1.1 | 2 |
| Kotlin | 0.7 | 1 |
| Secret scan | 0.3 | 1 |
| Dependency audit | 0.3 | 1 |
| CI result | 0.1 | 1 |
| **Total** | wall time 12.8 min | **68** (62 and 72 in two other green runs) |

Observations that drove the design:

* Per-job rounding: eight of the 15 jobs ran under 2 minutes and are billed 1 to 2, so splitting small checks into separate jobs costs more than it saves.
* The three Flutter time-zone runs are 30 billed minutes of 68; the Android job is 11. Together they are 60 % of an ordinary pull request.
* Every pull request ran everything: a documentation change, a Next.js copy change and a Flutter change cost the same 68 minutes.
* The macOS job is the most expensive minute: the 43 macOS runs were 48 % of all billed-equivalent minutes (the Intel build was a duplicate that could never have passed:
  no iOS 26 SDK on that image).
* Dependabot pull requests each started a complete run, and in a pnpm workspace they conflict on `pnpm-lock.yaml` (pull request 24 conflicted after 23 merged), so a
  merge forced another full run.
* Cache effectiveness: `setup-node` and `flutter-action` caches were enabled, but **no hit rate was recorded** and none can be computed from the data collected here.
  Treat cache savings as unmeasured.

## Not available

Queue time (the API gives `created_at` and `started_at` per job, but it was not analysed), artifact and cache storage in bytes, per-run
billing, spending limits and budgets (need the `user` token scope and the account owner).
