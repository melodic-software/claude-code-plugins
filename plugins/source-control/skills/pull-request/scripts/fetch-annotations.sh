#!/usr/bin/env bash
# Exit codes:
#   0  success (zero or more annotations emitted)
#   1  invalid argument, or --dir names no directory
#   2  gh api call failed
#   5  prerequisite missing (gh, jq)

# portability-scope: reads GitHub check-run annotations through the GitHub REST API with gh; the script is the GitHub provider's annotation read.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_NUMBER=""
FAILED_ONLY=0
CHECKOUT=""

usage() {
  cat <<'EOF'
fetch-annotations.sh: fetch the GitHub Actions check-run annotations for a PR's head as JSONL.

Usage:
  fetch-annotations.sh <pr-number> [--failed] [--dir <checkout>]

  --failed  only failure-conclusion check runs
  --dir     any checkout of the PR's repository (default: the current directory)
  FETCH_ANNOT_REPO=owner/name wins over --dir and the default.

Exit codes:
  0  success (zero or more annotations emitted)
  1  invalid argument, or --dir names no directory
  2  gh api call failed
  5  prerequisite missing (gh, jq)
EOF
  exit 0
}

die() {
  printf 'fetch-annotations: %s\n' "$2" >&2
  exit "$1"
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --failed) FAILED_ONLY=1 ;;
  --dir)
    (($# >= 2)) && [[ -n "$2" && -z "$CHECKOUT" ]] || die 1 "--dir needs one value and is given once"
    CHECKOUT="$2"
    shift
    ;;
  --) break ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ -z "$PR_NUMBER" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR_NUMBER="$1"
    ;;
  esac
  shift
done

[[ -n "$PR_NUMBER" ]] || die 1 "<pr-number> required"
[[ -z "$CHECKOUT" || -d "$CHECKOUT" ]] || die 1 "--dir $(printf '%q' "$CHECKOUT") is not a directory"

command -v gh >/dev/null 2>&1 || die 5 "gh CLI required"
command -v jq >/dev/null 2>&1 || die 5 "jq required"

REPO="${FETCH_ANNOT_REPO:-}"
if [[ -z "$REPO" && -n "$CHECKOUT" ]]; then
  REPO=$(bash "$SCRIPT_DIR/target-repo.sh" --dir "$CHECKOUT" | tr -d '\r\n')
elif [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r\n')
fi
[[ "$REPO" == */* ]] || die 2 "cannot resolve owner/repo (set FETCH_ANNOT_REPO=owner/name)"

HEAD_SHA=$(gh pr view "$PR_NUMBER" -R "$REPO" --json headRefOid -q .headRefOid 2>/dev/null | tr -d '\r\n')
[[ -n "$HEAD_SHA" ]] || die 2 "gh pr view $PR_NUMBER failed (no head SHA)"

# `--paginate`: a page holds at most 100 check runs:
# https://docs.github.com/en/rest/checks/runs#list-check-runs-for-a-git-reference
CHECK_RUNS_RAW=$(gh api --paginate "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" 2>/dev/null) ||
  die 2 "gh api check-runs failed (exit $?)"

FILTERED=$(printf '%s' "$CHECK_RUNS_RAW" |
  jq -c --argjson failed_only "$FAILED_ONLY" '
      .check_runs[]
      | {id, name, conclusion, status}
      | select($failed_only == 0
               or (.conclusion | IN("failure", "timed_out", "action_required", "cancelled")))
    ')

if [[ -z "$FILTERED" ]]; then
  exit 0
fi

while IFS= read -r cr; do
  cr_id=$(jq -r '.id' <<<"$cr")
  cr_name=$(jq -r '.name' <<<"$cr")
  [[ -z "$cr_id" || "$cr_id" == "null" ]] && continue

  # `--paginate`: a page holds at most 100 annotations:
  # https://docs.github.com/en/rest/checks/runs#list-check-run-annotations
  ANNOT_RAW=$(gh api --paginate "repos/$REPO/check-runs/$cr_id/annotations?per_page=100" 2>/dev/null) ||
    die 2 "gh api annotations for check-run $cr_id failed (exit $?)"
  printf '%s' "$ANNOT_RAW" |
    jq -c --argjson cr_id "$cr_id" --arg cr_name "$cr_name" '
        if type == "array" then .[] else . end
        | {
            check_run_id: $cr_id,
            check_run_name: $cr_name,
            level: .annotation_level,
            path: .path,
            start_line: .start_line,
            end_line: .end_line,
            title: .title,
            message: .message
          }
      ' 2>/dev/null || true
done <<<"$FILTERED"

exit 0
