#!/bin/bash
# Copyright 2026 ATLASHC Paweł Dolatowski
# SPDX-License-Identifier: Apache-2.0

# Applies the repository settings the project relies on, then READS EACH ONE BACK and exits non-zero if GitHub does not report it.
#
#   bash scripts/github-configure-repo.sh [owner/repo]        (default: the origin repository; needs admin rights)
#
# What it sets, and why:
#   * squash merges only, merged branches deleted, auto-merge off, no wiki: one reviewed commit per change, no stale branches;
#   * Actions: the default token is read-only and workflows cannot approve pull requests; workflows of EVERY outside contributor
#     wait for a maintainer's approval (a fork's pull request runs without any secret either way);
#   * private vulnerability reporting (SECURITY.md points at it), secret scanning with push protection, Dependabot alerts and
#     security updates (free on public repositories).
# The branch ruleset is applied separately: scripts/github-protect-main.sh.
set -eu
repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
fail=0
check() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "ok    $1 = $2"; else echo "FAIL  $1 = $2 (expected $3)" >&2; fail=1; fi
}

gh api -X PATCH "repos/$repo" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true -F allow_auto_merge=false -F has_wiki=false -F has_projects=false >/dev/null
gh api -X PATCH "repos/$repo" --input - >/dev/null <<'JSON'
{ "security_and_analysis": { "secret_scanning": { "status": "enabled" }, "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
gh api -X PUT "repos/$repo/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors >/dev/null
gh api -X PUT "repos/$repo/private-vulnerability-reporting" >/dev/null
gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/$repo/automated-security-fixes" >/dev/null

r="$(gh api "repos/$repo")"
get() { printf '%s' "$r" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
check "visibility" "$(get 'd["visibility"]')" "public"
check "default branch" "$(get 'd["default_branch"]')" "main"
check "squash merge only" "$(get '(d["allow_squash_merge"], d["allow_merge_commit"], d["allow_rebase_merge"])')" "(True, False, False)"
check "delete branch on merge" "$(get 'd["delete_branch_on_merge"]')" "True"
check "auto-merge" "$(get 'd["allow_auto_merge"]')" "False"
check "secret scanning" "$(get 'd["security_and_analysis"]["secret_scanning"]["status"]')" "enabled"
check "secret scanning push protection" "$(get 'd["security_and_analysis"]["secret_scanning_push_protection"]["status"]')" "enabled"
w="$(gh api "repos/$repo/actions/permissions/workflow")"
check "default workflow token" "$(printf '%s' "$w" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["default_workflow_permissions"], d["can_approve_pull_request_reviews"])')" "read False"
check "fork pull request approval" "$(gh api "repos/$repo/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy)" "all_external_contributors"
check "private vulnerability reporting" "$(gh api "repos/$repo/private-vulnerability-reporting" --jq .enabled)" "true"
if gh api "repos/$repo/vulnerability-alerts" >/dev/null 2>&1; then check "Dependabot alerts" "enabled" "enabled"; else check "Dependabot alerts" "disabled" "enabled"; fi
check "Dependabot security updates" "$(gh api "repos/$repo/automated-security-fixes" --jq .enabled)" "true"
exit "$fail"
