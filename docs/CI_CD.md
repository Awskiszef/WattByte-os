# CI/CD on GitHub

Repository: `Awskiszef/WattByte`, default branch `main`. Visibility and the state of the public release: `docs/security/PUBLIC_RELEASE_REPORT.md`.
This page separates what is **active** from what is **prepared** and what **needs a different GitHub plan or a person**.
Workflows: `.github/workflows/ci.yml`, `release.yml`; Dependabot: `.github/dependabot.yml`. How to run each step locally: `docs/CI.md`.
How to contribute: `CONTRIBUTING.md`. What the optimisation changed and what is measured versus estimated: `docs/CI_OPTIMIZATION_REPORT.md`.

> **Status of the restructured pipeline: configured, statically verified, NOT RUN on GitHub.** The previous pipeline passed (pull request 19,
> 15 of 15 jobs). The one in this file was written after GitHub began refusing every job of the account ("recent account payments have
> failed or your spending limit needs to be increased"). What was verified instead: YAML validity, the pin checker, 32 unit tests of the scope
> classifier and the gate, a dry run of the classifier on real diffs; GitHub's parser accepted the file (pull request 28 created the jobs under their new names) but refused to start any of them (a re-run on 2026-10-30 at 20:18 UTC was refused the same way). Until a run is green, treat each statement about runtime behaviour as unproven.
> The commands of the jobs (PostgreSQL tests, production and image smoke tests, Gitleaks, end to end, Dart client check, release guard) were also run by hand on a Mac with Docker: that proves the commands, not the workflow, the caches or the scope rules. Results: `docs/security/PUBLIC_RELEASE_REPORT.md`.

## Workflows

| Workflow | Runs on | What |
|---|---|---|
| `CI` (`ci.yml`) | pull request, push to `main`, weekly schedule (Monday 03:17 UTC), manual | **FAST** for pull requests, **FULL** for the schedule, manual runs and risky pushes (below). The last job, **`CI result`**, is the one required check. |
| `Release` (`release.yml`) | manual only | gated on the default branch and a green CI run; Android is built unsigned without secrets and signed in a separate job; iOS signs with an App Store Connect key. **Never run so far; no signing material exists.** |

Every workflow: `permissions: contents: read` (the release `guard` job adds `actions: read`), actions pinned to full commit SHAs
(`scripts/check-workflow-pins.mjs`), job timeouts, `pull_request` only (never `pull_request_target`), no secret in a pull-request job, no deployment.

## FAST and FULL

`changes` lists the files a change touches (`scripts/ci-changes.mjs`, rules and tests in `scripts/ci-changes.test.mjs`) and publishes one flag per job.

| Change touches | Jobs that run besides `hygiene` |
|---|---|
| only documentation (`docs/`, `*.md`, `LICENSE`, `NOTICE`, repository metadata) | none |
| `apps/web` | `web` (lint, typecheck, tests, Next.js build) |
| `apps/api`, `packages/contracts`, `apps/ai`, `packages/device-specs` | `ts` for the package and its dependents (`ai` → `contracts` → `api`), `api-production`, `contracts`, `e2e`; the catalog also the app jobs |
| `apps/mobile` Dart code | `flutter-static`, `flutter-test` (one time zone), `e2e`, `android` (debug build) |
| date or time code in `apps/mobile` (a pattern in the diff) | the same plus the two other time zones |
| Android project, plugin Kotlin, release guard | the same plus the bundle, the three release-guard builds and `kotlin` |
| iOS project, plugin Swift, `pubspec.*` | `ios` (macOS; ten times the minute price) |
| lockfile, workspace files, root configs, `.nvmrc` | every TypeScript package on Node 22 and 24 |
| `.github/workflows`, `scripts/ci-*` | everything, including `ios` |
| a path no rule knows | everything except `ios` (a new directory makes CI slower, never blind) |

FULL (every job, Node 22 and 24, three time zones, release-guard builds, macOS) runs on the schedule, on manual runs, and on a push to `main` that changes a
shared input or spans two components. **`hygiene` always runs**: unit tests of the scripts, tree and history secret scans, Gitleaks, workflow pins, docs check,
`pnpm audit` (production and dev dependencies).

**`CI result`** (`scripts/ci-gate.mjs`): a job the change needs must have *succeeded*; skipped counts only for a job the change does not need; failed, cancelled or
missing never pass. A test (`scripts/ci-gate.test.mjs`) fails when `ci.yml` and the gate disagree about a job. If the base commit cannot be determined the
classifier runs everything instead of guessing.

## Caches, concurrency, forks

* Dependencies: `setup-node` caches the pnpm store (key: lockfile); `flutter-action` caches the SDK and pub; `setup-gradle` caches Gradle and writes it **only on the default
  branch** (pull requests read it); the Next.js build cache (`apps/web/.next/cache`) uses a key from the lockfile and the sources. GitHub scopes caches per ref: a pull request
  can read the cache of `main` but cannot write to it. No cache holds a secret. Not measured: hit rates need runs.
* Concurrency: a new push to a pull request cancels the older run; runs on `main`, scheduled and manual runs are never cancelled by a later one; the release workflow is
  never cancelled.
* Forks: `pull_request` gives a fork a read-only token and no secrets; first-time contributors need a maintainer's approval before workflows run (a repository setting, see
  `docs/security/PUBLIC_RELEASE_REPORT.md`). The release workflow can only be started by someone with write access and signs only inside the `release` environment.

## Repository settings that are active (verified through the API on 2026-10-30)

| Setting | State |
|---|---|
| Default branch | `main` |
| Merge methods | squash and rebase; merge commits off; branch deleted after merge; auto-merge off |
| Actions | enabled; default workflow permissions **read**; workflows cannot approve pull requests. The repository setting *Require actions to be pinned to a full-length commit SHA* is **off on purpose**: it also applies to actions that third-party composite actions call internally, and `subosito/flutter-action` calls `actions/cache@v5` by tag, which would stop every Flutter job. Our own files are checked by `scripts/check-workflow-pins.mjs` instead; the nested tag references of the composite actions remain a supply-chain exposure (listed below). |
| Dependabot | version updates (`dependabot.yml`: weekly, one group per ecosystem, cooldown, no majors), vulnerability alerts and security updates on |
| Environments | `development`, `staging`, `production`, `release` exist; `production` and `release` accept deployments from `main` only |

## Not active (plan limits of a Free account on a private repository)

| Wanted | Why not | Instead |
|---|---|---|
| Protected `main` (pull request required, required checks, no force push, no deletion), rulesets | API: "Upgrade to GitHub Pro or make this repository public" | local `pre-push` hook, the workflow in `CONTRIBUTING.md`, `scripts/github-protect-main.sh` + `.github/rulesets/main.json` ready to apply (on a public repository the same API is free) |
| Required reviewers on `production` / `release` | "billing plan does not support the required reviewers protection rule" | the `guard` job of the release workflow, a branch restriction to `main`, nothing is deployed from CI |
| GitHub secret scanning and push protection | "not available for this repository" (private, no GitHub Secret Protection) | `scripts/secret-scan.mjs`, `scripts/secret-scan-history.mjs` and Gitleaks in `CI`; the local `pre-push` hook does not scan |
| Dependency review action on pull requests | needs the dependency graph for private repositories (GitHub Advanced Security) | `pnpm audit` and Dependabot alerts |
| Code owner review | needs protection | `.github/CODEOWNERS` documents the owners |

## Environments and secrets

No repository or environment secret exists, and none was copied from a local `.env`. The signing secrets listed in
`docs/CI.md` ("Release workflow") are added to the **`release` environment** only, by the owner, when a signed build is wanted.
`production` is a placeholder for the day there is something to deploy; nothing deploys today.

## Known gaps

* Composite actions we use (`subosito/flutter-action`, `gradle/actions/setup-gradle`, `pnpm/action-setup`) reference other actions by tag internally; we pin the composite itself to a commit, not what it calls. Replacing `flutter-action` with a pinned manual install would remove the largest case.
* The restructured `CI` has not run on GitHub (billing refusal, above). The macOS job is part of `CI result` when the change needs it.
* The Dependabot configuration (`groups` with `applies-to`, `cooldown`) is validated by GitHub only when it is read; look at the repository's Dependabot page after the first run.
* `pnpm audit` is green because of one documented exception (zod, `pnpm-workspace.yaml`, plan in `docs/ZOD4_MIGRATION.md`), not because the advisory is gone.
