# CI optimisation: before and after

What changed is in `.github/workflows/ci.yml`, `scripts/ci-changes.mjs`, `scripts/ci-gate.mjs` and `.github/dependabot.yml`; how it works is in `docs/CI_CD.md`;
the measured starting point is in `docs/CI_OPTIMIZATION_BASELINE.md`.

> **Everything in the "After" column is an estimate.** The new pipeline has not run on GitHub: Actions refuses every job of the account at the time of writing
> (docs/CI_CD.md, "Status"). "Before" values are measured (one green run, 15 of 15 jobs, plus two other green runs for the range). "After" values apply the *measured*
> duration of each job that still runs, plus an estimate for the jobs that did not exist before (marked ~). They are reasons to expect savings, not results.
> No percentage saving is claimed. Cache hit rates cannot be stated.

## Per scenario (billed Linux-equivalent minutes, each job rounded up, macOS ten times)

| Change | Jobs before | Minutes before | Jobs after | Minutes after (est.) | What runs besides `changes`, `hygiene`, `CI result` |
|---|---:|---:|---:|---:|---|
| documentation only | 15 | 68 | 3 | ~4 | nothing |
| `apps/web` only | 15 | 68 | 4 | ~8 | `web` (~4) |
| `apps/api` only | 15 | 68 | 7 | ~17 | `ts` Node 22 (6), `api-production` (2), `contracts` (2), `e2e` (3) |
| `apps/mobile` Dart code, no date logic | 15 | 68 | 7 | ~25 | `flutter-static` (~3), `flutter-test` Warsaw (8), `e2e` (3), `android` APK only (~7) |
| the same, with date or time code | 15 | 68 | 9 | ~48 | + UTC (12) and America/New_York (11) |
| iOS project or plugin Swift | 15 + 1 macOS | 68 + 30 | 8 | ~55 (25 + 30 macOS) | the mobile set plus `ios` |
| lockfile / workspace files | 15 | 68 | 9 | ~24 | every TypeScript package on Node 22 and 24, `web`, `e2e`, `api-production`; no Flutter |
| FULL (weekly, manual, risky push) | 15 (+ macOS when iOS paths) | 68 (+30) | 16 (incl. 1 macOS) | ~100 (incl. 30 macOS) | everything; more than before because `web` and macOS are now included |

The pre-merge and post-merge split matters for the comparison: a pull request is scoped (FAST); the push to `main` after the merge additionally runs Node 24 for TypeScript
changes and all three time zones for app changes, so what a pull request leaves out is checked once more right after it lands. A mobile merge therefore costs the pull-request
run plus a run on `main` with all three time zones (about 31 billed minutes for the Flutter tests alone); it does not wait for the weekly run.

## Requested metrics

| Metric | Before | After |
|---|---|---|
| Jobs for an ordinary pull request | 15 | 3 (docs) to 9 (app with date logic), depending on the change |
| Time of an ordinary pull request (wall) | 12.8 min measured | not measured; jobs run in parallel, so wall time follows the slowest job that still runs (Flutter tests ~8 to 12 min for an app change, ~6 min for API only, ~1 to 2 min for docs) |
| Minutes consumed | 68 per pull request (62 to 72) | ~4 to ~48, see above (estimate) |
| Estimated cost in money | not computed: the price list was not verified in this session | not computed |
| macOS jobs | the iOS workflow on iOS paths; two macOS jobs per run in the first runs (43 macOS jobs in total, about 48 % of all billed-equivalent minutes) | one, only for iOS, native-dependency or workflow changes, the weekly run and manual runs |
| Android builds | debug APK + AAB + 3 release-guard builds on every pull request | debug APK for app changes; AAB and release-guard builds only for Android-native, release-guard or workflow changes and in FULL |
| `pnpm install` per pull request | 5 | 0 (docs), 1 (web), 4 (API), 1 (app) |
| Cache hit rate | not recorded | not measurable before a run |
| Time of the full CI | 12.8 min | not measured; adds `web`, Node 24 on every TypeScript change and macOS |
| Number of tests | API 777 (563 run without PostgreSQL), AI 841, Flutter 2,260 (47 skipped), web 33, device specs 6, scripts 133, Kotlin 15 | unchanged: no test was removed or disabled |
| Tests skipped conditionally | 0 | whole jobs, decided by the change: Flutter time-zone runs UTC and New_York (unless date code or a push to `main`), Node 24 (unless shared inputs, a push to `main` or FULL), AAB and release-guard builds (unless Android-native), macOS |

## Did the optimisation lose any check?

Compared check by check with the old pipeline:

| Old behaviour | New behaviour | Risk | Mitigation |
|---|---|---|---|
| everything on every pull request | only what the change reaches | a path rule that does not know a dependency would skip a needed job | unknown paths run everything; shared inputs widen the scope; 33 tests pin the rules; the gate refuses a skipped job the change needs |
| Node 24 on every pull request | pull requests: Node 22; shared inputs, every push to `main` and FULL: both | a Node-24-only failure shows after the merge | runs on the push to `main`, one run later |
| three time zones on every pull request | pull requests: Europe/Warsaw; three zones for date/time code, every push to `main` that touches the app, FULL | a time-zone regression in code the heuristic does not recognise (it matches `DateTime`, `Duration(`, `toLocal(`, `DST`, `TZ`, `DateFormat`, `Calendar`, …) shows after the merge | the push-to-`main` run and the weekly run; the DST and date-boundary tests run in every zone anyway |
| AAB and three release builds on every pull request | only for Android-native, release-guard or workflow changes and FULL | a Dart-only change that breaks only the release build | the Dart code is compiled by the debug build and `flutter analyze`; the release guard is also run as a script in `flutter-static` (26 combinations, no Gradle) |
| API production build and Docker image on every pull request | when the API, contracts, AI, catalog, Dockerfile or workflow changed | none expected: nothing else feeds that build | the web and docs paths cannot change it |
| `pnpm audit --prod` | `pnpm audit` (also development dependencies) | stricter: a new advisory in test tooling now blocks | intended |
| separate `iOS` workflow outside `CI result` | `ios` job inside `CI result` when needed | a macOS image outage blocks an iOS change | rerun; macOS is only needed for iOS-relevant changes |

What this pipeline still does **not** prove: that the new `ci.yml` is accepted and behaves as described (no run), that the cache keys hit, that the estimates above hold, and that
`dependabot.yml` is accepted by GitHub. Each of those is settled by the first runs; look at the job list of a documentation-only pull request first (expected: three jobs).
