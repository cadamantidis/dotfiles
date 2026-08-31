#!/usr/bin/env bash
# Opens (or updates) a GitHub Issue in this repo when scan.sh finds new
# (non-baselined) secrets. Never includes secret values — only rule id,
# repo, file, commit, and gitleaks' own Fingerprint. GitHub's default
# issue-notification emails are the actual alert channel here.
#
# Usage: notify.sh [findings-json-path]
#   Falls back to $NEW_FINDINGS_PATH, then a default tmp path, if no arg given.
set -euo pipefail

FINDINGS_PATH="${1:-${NEW_FINDINGS_PATH:-${TMPDIR:-/tmp}/security-sweep-new-findings.json}}"
LABEL="security-sweep"

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "error: '$bin' is required but not found on PATH" >&2
    exit 1
  }
done

if [ ! -f "$FINDINGS_PATH" ]; then
  echo "error: findings file not found: $FINDINGS_PATH" >&2
  exit 1
fi

count=$(jq 'length' "$FINDINGS_PATH")
if [ "$count" -eq 0 ]; then
  echo "No new findings — nothing to alert on."
  exit 0
fi

gh label create "$LABEL" \
  --color "B60205" \
  --description "New secret(s) found by the scheduled git-history sweep" \
  --force >/dev/null

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

{
  echo "gitleaks found **$count new secret(s)** across the account's public repos, not present in any prior sweep's baseline."
  echo
  echo "Secret values are intentionally not included here. Use the repo/file/commit below to check it out locally, or match the \`Fingerprint\` against a fresh \`gitleaks\` run."
  echo
  echo "| Repo | Rule | File | Commit | Fingerprint |"
  echo "|---|---|---|---|---|"
  jq -r '.[] | "| \(.Repo) | \(.RuleID) | \(.File) | \(.Commit[0:12]) | \(.Fingerprint) |"' "$FINDINGS_PATH"
  echo
  echo "_Swept $(date -u +"%Y-%m-%dT%H:%M:%SZ")._"
} > "$BODY_FILE"

existing_issue="$(gh issue list --state open --label "$LABEL" --limit 1 --json number -q '.[0].number // empty')"

if [ -n "$existing_issue" ]; then
  echo "Updating existing issue #$existing_issue"
  gh issue comment "$existing_issue" --body-file "$BODY_FILE"
else
  echo "Opening a new issue"
  gh issue create --title "security-sweep: new secret(s) detected" --body-file "$BODY_FILE" --label "$LABEL"
fi
