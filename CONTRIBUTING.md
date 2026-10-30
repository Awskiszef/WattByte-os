# Contributing to WattByte

WattByte is licensed under the [Apache License 2.0](LICENSE). By submitting a contribution you agree that it is licensed under
the same terms (Apache-2.0 section 5). Please do not submit code you do not have the right to license this way.

`main` is the stable, integrated line. Nothing is committed to it directly; every change arrives through a pull request whose
CI result is green. Security problems are **not** reported as issues or pull requests: see [SECURITY.md](SECURITY.md).

## The workflow

1. **Fork** the repository (outside contributors) or branch from an up-to-date `main` (maintainers), one logical change per branch:
   `feature/<what>`, `fix/<what>`, `security/<what>`, `refactor/<what>`, `docs/<what>`, `release/<version>`.
   ```bash
   git switch main && git pull --ff-only && git switch -c fix/short-description
   ```
2. **Implement and test locally** ([docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)): lint, typecheck and the tests of what you touched;
   `pnpm test:db` for the API; `node scripts/secret-scan.mjs` before committing.
3. **Commit** with a message that says why (`fix(api): ...`, `feat(mobile): ...`, `docs: ...`). No secrets, no `.env`, no build
   output, no personal data in code, tests, fixtures or screenshots.
4. **Push the branch**, never `main`, and **open a pull request** against `main`; fill in the template: what, how it was checked,
   risk, what was not done.
5. **CI runs** ([docs/CI_CD.md](docs/CI_CD.md)). Read the result of *this* pull request, not your local one. A red, skipped or
   missing check is not a pass. Workflows from a fork run without any secret and with read-only permissions.
6. **Review.** A maintainer reads the diff and the CI result; a claim in the description that the CI does not back up is not accepted.
7. **Merge** when `CI result` is green and conversations are resolved. Squash merge is the default; merge commits are not used.

Rules that never bend: no force push to shared branches, no rewriting of pushed history, no unresolved merge conflicts in a pull
request, no production deployment from a pull request.

## Enforcement

Branch protection (pull request required, `CI result` required, no force push, no deletion) is defined in
`.github/rulesets/main.json` and applied with `bash scripts/github-protect-main.sh`, which exits non-zero when the ruleset is not
active. A local `pre-push` hook (`.githooks/pre-push`; enable once per clone with `git config core.hooksPath .githooks`)
refuses a direct push to `main` and force pushes. The current state is recorded in [docs/CI_CD.md](docs/CI_CD.md).

## Dependencies

Dependabot opens grouped weekly pull requests for minor and patch updates and security updates; majors are not opened
automatically and are done as planned migrations on their own branch (for example [zod 3 to 4](docs/ZOD4_MIGRATION.md)).
`pnpm audit` must stay green; an ignored advisory needs a written reason in `pnpm-workspace.yaml`.

## Releases

Nothing is deployed from CI. A release is prepared on `release/<version>`, run by hand through the `Release` workflow after the
checklist in [docs/RELEASE.md](docs/RELEASE.md), and never from a pull request.
