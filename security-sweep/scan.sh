#!/usr/bin/env bash
# Sweeps every repo (public and private) under a GitHub account's full git
# history for secrets with gitleaks, using a per-repo baseline so only
# genuinely new findings get surfaced. See README.md for the full design.
#
# Requires on PATH: gh (authenticated), git, gitleaks, jq.
#
# Env vars:
#   GH_OWNER          GitHub account to sweep (default: cadamantidis)
#   NEW_FINDINGS_PATH  where to write the aggregated new-findings JSON
#                      (default: $TMPDIR/security-sweep-new-findings.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/state"
CONFIG_FILE="$SCRIPT_DIR/.gitleaks.toml"
GH_OWNER="${GH_OWNER:-cadamantidis}"
NEW_FINDINGS_PATH="${NEW_FINDINGS_PATH:-${TMPDIR:-/tmp}/security-sweep-new-findings.json}"

for bin in gh git gitleaks jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "error: '$bin' is required but not found on PATH" >&2
    exit 1
  }
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$STATE_DIR"
echo "[]" > "$NEW_FINDINGS_PATH"

echo "Discovering repos for $GH_OWNER..."
mapfile -t REPOS < <(gh repo list "$GH_OWNER" --source --no-archived --limit 1000 --json nameWithOwner -q '.[].nameWithOwner')

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "error: no repos found for $GH_OWNER" >&2
  exit 1
fi
echo "Found ${#REPOS[@]} repo(s): ${REPOS[*]}"

for repo in "${REPOS[@]}"; do
  safe_name="${repo//\//__}"
  baseline_file="$STATE_DIR/${safe_name}.json"
  clone_dir="$WORK_DIR/${safe_name}"
  report_file="$WORK_DIR/${safe_name}-report.json"

  echo "=== $repo ==="
  gh repo clone "$repo" "$clone_dir" -- --quiet

  baseline_args=()
  if [ -f "$baseline_file" ]; then
    baseline_args=(--baseline-path "$baseline_file")
  fi

  set +e
  gitleaks detect \
    --source "$clone_dir" \
    --config "$CONFIG_FILE" \
    "${baseline_args[@]}" \
    --report-path "$report_file" \
    --report-format json \
    --exit-code 2 \
    --no-banner
  gl_exit=$?
  set -e

  case "$gl_exit" in
    0) : ;; # clean scan, nothing new
    2) : ;; # new (non-baselined) findings — handled below
    *)
      echo "error: gitleaks exited $gl_exit scanning $repo — treating as a hard failure, not a 'leaks found' result" >&2
      exit "$gl_exit"
      ;;
  esac

  if [ "$gl_exit" -eq 2 ]; then
    jq --arg repo "$repo" '[.[] | . + {Repo: $repo}]' "$report_file" > "$WORK_DIR/tagged.json"
    jq -s '.[0] + .[1]' "$NEW_FINDINGS_PATH" "$WORK_DIR/tagged.json" > "$WORK_DIR/merged.json"
    mv "$WORK_DIR/merged.json" "$NEW_FINDINGS_PATH"
  fi

  # Roll the baseline forward: everything known before, plus whatever this
  # run just surfaced (report_file only contains non-baselined findings when
  # a baseline was supplied, so a plain union is correct either way).
  if [ -f "$baseline_file" ]; then
    jq -s '(.[0] + .[1]) | unique_by(.Fingerprint)' "$baseline_file" "$report_file" > "$WORK_DIR/next-baseline.json"
  else
    cp "$report_file" "$WORK_DIR/next-baseline.json"
  fi
  mv "$WORK_DIR/next-baseline.json" "$baseline_file"

  rm -rf "$clone_dir"
done

new_count=$(jq 'length' "$NEW_FINDINGS_PATH")
echo "--- done: ${#REPOS[@]} repo(s) scanned, $new_count new finding(s) ---"
echo "New findings written to: $NEW_FINDINGS_PATH"
