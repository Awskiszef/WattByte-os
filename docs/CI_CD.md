# CI/CD on GitHub

Repository: private, `Awskiszef/WattByte`, default branch `main`. This page separates what is **active** from what is **prepared** and
what **needs a different GitHub plan or a person**. Workflows: `.github/workflows/ci.yml`, `ios.yml`, `release.yml`; Dependabot:
`.github/dependabot.yml`. How to run each step locally: `docs/CI.md`. How to contribute: `CONTRIBUTING.md`.

## Workflows

| Workflow | Runs on | What |
|---|---|---|
| `CI` (`ci.yml`) | pull request, push to `main`, manual | secret scans (tree, history, Gitleaks), dependency audit, TypeScript on Node 22 and 24 with PostgreSQL, API production build + smoke test + Docker image, contracts and generated Dart client, Flutter format/analyze/tests in three time zones, release-guard matrix, end-to-end (Dart client to API to PostgreSQL), Android debug build, Kotlin unit tests. The last job, **`CI result`**, fails unless every other job succeeded. |
| `iOS` (`ios.yml`) | manual; push to `main` and pull requests that touch the app or its iOS code (path filters) | iOS simulator and device-SDK build (unsigned), widget link check, Swift checks. macOS minutes cost ten times a Linux minute, which is why it is not part of `CI result`; run it by hand before merging native changes. |
| `Release` (`release.yml`) | manual only | gated on the default branch and a green CI run; Android is built unsigned without secrets and signed in a separate job; iOS signs with an App Store Connect key. **Never run so far; no signing material exists.** |

Every workflow: `permissions: contents: read` (the release `guard` job adds `actions: read`), actions pinned to full commit SHAs
(`scripts/check-workflow-pins.mjs` checks the files in CI), `concurrency` groups, job timeouts, no `pull_request_target`, no secrets in pull-request jobs, no deployment.

## Repository settings that are active (verified through the API)

| Setting | State |
|---|---|
| Visibility | private |
| Default branch | `main` |
| Merge methods | squash and rebase; merge commits off; branch deleted after merge; auto-merge off |
| Actions | enabled; default workflow permissions **read**; workflows cannot approve pull requests. The repository setting *Require actions to be pinned to a full-length commit SHA* is **off on purpose**: it also applies to actions that third-party composite actions call internally, and `subosito/flutter-action` calls `actions/cache@v5` by tag, which would stop every Flutter job. Our own files are checked by `scripts/check-workflow-pins.mjs` instead; the nested tag references of the composite actions remain a supply-chain exposure (listed below). |
| Dependabot | version updates (`dependabot.yml`: weekly, grouped, no majors), vulnerability alerts and security updates on |
| Environments | `development`, `staging`, `production`, `release` exist; `production` and `release` accept deployments from `main` only |

## Not active (plan limits of a Free account on a private repository)

| Wanted | Why not | Instead |
|---|---|---|
| Protected `main` (pull request required, required checks, no force push, no deletion), rulesets | API: "Upgrade to GitHub Pro or make this repository public" | local `pre-push` hook, the workflow in `CONTRIBUTING.md`, `scripts/github-protect-main.sh` + `.github/rulesets/main.json` ready to apply after the upgrade |
| Required reviewers on `production` / `release` | "billing plan does not support the required reviewers protection rule" | the `guard` job of the release workflow, a branch restriction to `main`, nothing is deployed from CI |
| GitHub secret scanning and push protection | "not available for this repository" (needs GitHub Secret Protection) | `scripts/secret-scan.mjs`, `scripts/secret-scan-history.mjs` and Gitleaks in `CI`; the local `pre-push` hook does not scan |
| Dependency review action on pull requests | needs the dependency graph for private repositories (GitHub Advanced Security) | `pnpm audit --prod` and Dependabot alerts |
| Code owner review | needs protection | `.github/CODEOWNERS` documents the owners |

## Environments and secrets

No repository or environment secret exists, and none was copied from a local `.env`. The signing secrets listed in
`docs/CI.md` ("Release workflow") are added to the **`release` environment** only, by the owner, when a signed build is wanted.
`production` is a placeholder for the day there is something to deploy; nothing deploys today.

## Known gaps

* Composite actions we use (`subosito/flutter-action`, `gradle/actions/setup-gradle`, `pnpm/action-setup`) reference other actions by tag internally; we pin the composite itself to a commit, not what it calls. Replacing `flutter-action` with a pinned manual install would remove the largest case.
* The macOS build is not part of the required check (see above); run `iOS` by hand.
* The CI has run a handful of times; the first run was red for the reasons listed in `docs/remediation/FINAL_REPORT.md`, pull request 19 was green. Anything not run on GitHub yet (Release, signed builds) is unverified.
* `pnpm audit --prod` is green because of one documented exception (zod, `pnpm-workspace.yaml`), not because the advisory is gone.
