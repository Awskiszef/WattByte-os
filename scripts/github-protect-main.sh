#!/bin/bash
# Applies .github/rulesets/main.json to the repository as a ruleset and verifies that it is ACTIVE.
#
#   bash scripts/github-protect-main.sh [owner/repo]        (default: the origin repository)
#
# Rulesets and branch protection for a PRIVATE repository need GitHub Pro (or Team/Enterprise); on the Free plan the API answers
# 403 "Upgrade to GitHub Pro or make this repository public". This script then exits 3 and changes nothing: it never reports
# a protection that is not there. Run it after upgrading the plan.
set -eu
repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
file="$(dirname "$0")/../.github/rulesets/main.json"
if ! out="$(gh api "repos/$repo/rulesets" 2>&1)"; then
  echo "cannot read rulesets of $repo: $out" >&2
  case "$out" in *Upgrade*) echo "The plan does not support rulesets for this repository: main is NOT protected." >&2; exit 3 ;; esac
  exit 1
fi
existing="$(printf '%s' "$out" | python3 -c 'import json,sys; print(next((str(r["id"]) for r in json.load(sys.stdin) if r["name"]=="main"), ""))')"
if [ -n "$existing" ]; then
  gh api -X PUT "repos/$repo/rulesets/$existing" --input "$file" >/dev/null
else
  gh api -X POST "repos/$repo/rulesets" --input "$file" >/dev/null
fi
gh api "repos/$repo/rulesets" --jq '.[] | select(.name=="main") | "ruleset main: enforcement=\(.enforcement)"'

# Read back what GitHub actually enforces on `main` (the effective rules, not the ruleset we sent) and fail if anything is missing.
gh api "repos/$repo/rules/branches/main" | python3 -c '
import json, sys
rules = json.load(sys.stdin)
types = {r["type"] for r in rules}
need = {"deletion", "non_fast_forward", "pull_request", "required_status_checks"}
contexts = {c["context"] for r in rules if r["type"] == "required_status_checks" for c in r["parameters"]["required_status_checks"]}
missing = sorted(need - types) + sorted({"CI result", "Public Configuration Security Gate"} - contexts)
print("effective rules on main:", ", ".join(sorted(types)), "| required checks:", ", ".join(sorted(contexts)))
if missing:
    print("NOT ENFORCED:", ", ".join(missing), file=sys.stderr)
    sys.exit(4)
print("verified: force pushes and deletion are blocked, a pull request and both required checks are enforced on main")
'
