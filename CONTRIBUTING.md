# Contributing to WattByte

The repository is **private**: `https://github.com/Awskiszef/WattByte`. `main` is the stable, integrated line. Nothing is committed
to it directly; every change arrives through a pull request that has a green CI result.

## The workflow

1. **Branch from an up-to-date `main`**, one logical change per branch:
   `feature/<what>`, `fix/<what>`, `security/<what>`, `refactor/<what>`, `docs/<what>`, `release/<version>`.
   ```bash
   git switch main && git pull --ff-only && git switch -c fix/short-description
   ```
2. **Implement and test locally** (`docs/DEVELOPMENT.md`): lint, typecheck and the tests of what you touched; `pnpm test:db` for the API;
   `node scripts/secret-scan.mjs` before committing.
3. **Commit** with a message that says why (`fix(api): ...`, `feat(mobile): ...`, `docs: ...`); reference the audit row
   (`[G-14]`) when there is one. No secrets, no `.env`, no build output.
4. **Push the branch**, never `main`: `git push -u origin fix/short-description`.
5. **Open a pull request** against `main` (`gh pr create`); fill in the template: what, how it was checked, risk, what was not done.
6. **CI runs** (`docs/CI_CD.md`). Read the result of *this* pull request, not your local one. A red or missing check is not a pass.
7. **Review.** A reviewer, or you on a solo project, reads the diff and the CI result; a claim in the description that the CI
   does not back up is not accepted.
8. **Merge** when `CI result` is green and conversations are resolved. Prefer **squash merge** for a small change; the
   repository allows squash and rebase merges, not merge commits. The remote branch is deleted automatically after the merge.
9. **Update local `main`** and delete the local branch.

Rules that never bend: no force push, no `git reset --hard` on shared work, no rewriting of pushed history, no unresolved merge
conflicts in a pull request, no production deployment from a pull request.

## Enforcement: what is real today

On the GitHub Free plan **branch protection and rulesets are not available for a private repository**, so the rules above are
conventions backed by checks, not enforced by GitHub:

* A local `pre-push` hook (`.githooks/pre-push`) refuses a direct push to `main` and force pushes.
  Enable it once per clone: `git config core.hooksPath .githooks`.
* CI fails visibly on a pull request; merging a red one is still *possible* for the owner.
* `.github/rulesets/main.json` and `scripts/github-protect-main.sh` hold the intended protection (pull request required, `CI result`
  required, no force push, no deletion, conversations resolved). After upgrading to GitHub Pro run
  `bash scripts/github-protect-main.sh`; it verifies that the ruleset is active and exits non-zero when it is not.

## Dependencies

Dependabot opens grouped weekly pull requests for minor and patch updates; majors are ignored on purpose and are done as planned
migrations on their own branch (for example zod 3 to 4, which also removes the one accepted audit exception). `pnpm audit --prod`
must stay green; an ignored advisory needs a written reason in `pnpm-workspace.yaml`.

## Releases

Nothing is deployed from CI. A release is prepared on `release/<version>`, run by hand through the `Release` workflow after the
checklist in `docs/RELEASE.md`, and never from a pull request.
